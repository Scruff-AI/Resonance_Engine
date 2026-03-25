/* ============================================================================
 * PROBE — Stress-Response Forensics
 *
 * Same physics as precipitation v2, but with four timed perturbations:
 *
 *   Probe A  (cy 600-649):   Metabolic Injection — add mass to the grid
 *   Probe B  (cy 800):       Lattice Shear — rotate top 25% velocity by 90°
 *   Probe C  (cy 1100-1199): VRM Silence — lock omega to 1.25
 *   Probe D  (cy 1400-1499): Vacuum Trap — 10 particles get 10x accretion
 *
 *   0-500:    Warmup + precipitation + plateau formation
 *   500-599:  Baseline (pre-probe calm)
 *   600-649:  PROBE A — mass injection
 *   650-799:  Recovery A
 *   800:      PROBE B — shear rotation (instantaneous)
 *   801-1099: Recovery B
 *   1100-1199:PROBE C — VRM silence
 *   1200-1399:Recovery C
 *   1400-1499:PROBE D — vacuum trap
 *   1500-1700:Recovery D + final observation
 *
 * Build:  nvcc -O3 -arch=sm_89 -o probe /src/src/probe.cu -lnvidia-ml -lpthread
 * ============================================================================ */
#include <cuda_runtime.h>
#include <nvml.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <chrono>

/* ---- Grid --------------------------------------------------------------- */
#define NX    1024
#define NY    1024
#define NN    (NX * NY)
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)
#define NUM_BLOCKS GBLK(NN)

/* ---- Protocol ----------------------------------------------------------- */
#define STEPS_PER_BATCH    500
#define BATCHES_PER_CYCLE  200
#define MAX_CYCLES         1700

/* ---- VRM ---------------------------------------------------------------- */
#define OMEGA_BASE     (1.0f / 0.8f)
#define VRM_ALPHA      10.0f
#define OMEGA_CLAMP_LO 0.6f
#define OMEGA_CLAMP_HI 1.95f

/* ---- Shear layer -------------------------------------------------------- */
#define U_TOP       1.994e-4f
#define U_BOT       0.997e-4f
#define COS135      (-0.70710678f)
#define SIN135      ( 0.70710678f)
#define SHEAR_DELTA 2.0f

/* ---- Precipitation ------------------------------------------------------ */
#define RHO_THRESH      1.01f
#define DRAIN_RADIUS    16
#define SINK_RADIUS     24
#define SINK_RATE       0.005f
#define MAX_PARTICLES   256

/* ---- Torque bias -------------------------------------------------------- */
#define TORQUE_STRENGTH 1e-8f

/* ---- Probe schedule ----------------------------------------------------- */
#define PROBE_A_START   600
#define PROBE_A_END     649
#define PROBE_B_CYCLE   800
#define PROBE_C_START   1100
#define PROBE_C_END     1199
#define PROBE_D_START   1400
#define PROBE_D_END     1499
#define PROBE_D_COUNT   10       /* how many particles get boosted           */
#define PROBE_D_MULT    10.0f    /* accretion multiplier for trapped ones    */

/* ---- D2Q9 --------------------------------------------------------------- */
__constant__ int   d_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
__constant__ int   d_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
__constant__ float d_w[Q]  = { 4.f/9,
                               1.f/9, 1.f/9, 1.f/9, 1.f/9,
                               1.f/36,1.f/36,1.f/36,1.f/36 };

static const int   h_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
static const int   h_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
static const float h_w[Q]  = { 4.f/9,
                                1.f/9, 1.f/9, 1.f/9, 1.f/9,
                                1.f/36,1.f/36,1.f/36,1.f/36 };

/* ---- Particle ----------------------------------------------------------- */
struct Particle {
    float x, y;
    float vx, vy;
    float mass;
    int   alive;
    int   birth_cycle;
    float latent_energy;
};

/* ============================================================================
 * KERNELS — Same as precipitation v2
 * ============================================================================ */

__global__ void collide_stream(
    const float* __restrict__ f_src, float* __restrict__ f_dst,
    float* __restrict__ rho_out, float* __restrict__ ux_out,
    float* __restrict__ uy_out, float omega, int nx, int ny)
{
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N = nx * ny;
    if (idx >= N) return;
    const int x = idx % nx, y = idx / nx;

    float fl[Q];
    #pragma unroll
    for (int i = 0; i < Q; i++) {
        int sx = (x - d_ex[i] + nx) % nx;
        int sy = (y - d_ey[i] + ny) % ny;
        fl[i] = f_src[i * N + sy * nx + sx];
    }

    float rho = 0.f, ux = 0.f, uy = 0.f;
    #pragma unroll
    for (int i = 0; i < Q; i++) {
        rho += fl[i];
        ux  += (float)d_ex[i] * fl[i];
        uy  += (float)d_ey[i] * fl[i];
    }
    if (rho > 1e-10f) { ux /= rho; uy /= rho; }
    rho_out[idx] = rho;  ux_out[idx] = ux;  uy_out[idx] = uy;

    const float u2 = ux*ux + uy*uy;
    #pragma unroll
    for (int i = 0; i < Q; i++) {
        float eu  = (float)d_ex[i]*ux + (float)d_ey[i]*uy;
        float feq = d_w[i] * rho * (1.f + 3.f*eu + 4.5f*eu*eu - 1.5f*u2);
        f_dst[i * N + idx] = fl[i] - omega * (fl[i] - feq);
    }
}

__global__ void apply_torque_bias(
    float* f, const float* __restrict__ ux, const float* __restrict__ uy,
    const float* __restrict__ rho, float strength, int nx, int ny)
{
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N = nx * ny;
    if (idx >= N) return;
    const int x = idx % nx, y = idx / nx;

    int xp  = (x + 1) % nx, xm = (x - 1 + nx) % nx;
    int yp  = (y + 1) % ny, ym = (y - 1 + ny) % ny;

    float duy_dx = (uy[y * nx + xp] - uy[y * nx + xm]) * 0.5f;
    float dux_dy = (ux[yp * nx + x] - ux[ym * nx + x]) * 0.5f;
    float omega_z = duy_dx - dux_dy;

    float local_ux = ux[idx];
    float local_uy = uy[idx];
    float fx = -strength * local_uy * omega_z;
    float fy =  strength * local_ux * omega_z;

    #pragma unroll
    for (int i = 0; i < Q; i++) {
        float eu = (float)d_ex[i] * local_ux + (float)d_ey[i] * local_uy;
        float Fi = d_w[i] * (
            3.f * ((float)d_ex[i] * fx + (float)d_ey[i] * fy) +
            9.f * eu * ((float)d_ex[i] * fx + (float)d_ey[i] * fy)
            - 3.f * (local_ux * fx + local_uy * fy)
        );
        f[i * N + idx] += Fi;
    }
}

__global__ void field_reduce(
    const float* __restrict__ ux, const float* __restrict__ uy,
    const float* __restrict__ rho,
    float* bsmin, float* bsmax, float* brmin, float* brmax, int N)
{
    __shared__ float ss_min[BLOCK], ss_max[BLOCK];
    __shared__ float sr_min[BLOCK], sr_max[BLOCK];
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int tid = threadIdx.x;

    float spd = 0, r = 1.0f;
    if (idx < N) {
        float u = ux[idx], v = uy[idx];
        spd = sqrtf(u*u + v*v);
        r   = rho[idx];
    }
    ss_min[tid] = spd;  ss_max[tid] = spd;
    sr_min[tid] = r;    sr_max[tid] = r;
    __syncthreads();

    for (int h = blockDim.x/2; h > 0; h >>= 1) {
        if (tid < h) {
            ss_min[tid] = fminf(ss_min[tid], ss_min[tid+h]);
            ss_max[tid] = fmaxf(ss_max[tid], ss_max[tid+h]);
            sr_min[tid] = fminf(sr_min[tid], sr_min[tid+h]);
            sr_max[tid] = fmaxf(sr_max[tid], sr_max[tid+h]);
        }
        __syncthreads();
    }
    if (tid == 0) {
        bsmin[blockIdx.x] = ss_min[0];  bsmax[blockIdx.x] = ss_max[0];
        brmin[blockIdx.x] = sr_min[0];  brmax[blockIdx.x] = sr_max[0];
    }
}

__global__ void rho_sum_reduce(const float* __restrict__ rho,
                                double* __restrict__ block_sums, int N)
{
    __shared__ double s[BLOCK];
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int tid = threadIdx.x;
    s[tid] = (idx < N) ? (double)rho[idx] : 0.0;
    __syncthreads();
    for (int h = blockDim.x/2; h > 0; h >>= 1) {
        if (tid < h) s[tid] += s[tid + h];
        __syncthreads();
    }
    if (tid == 0) block_sums[blockIdx.x] = s[0];
}

__global__ void enstrophy_reduce(
    const float* __restrict__ ux, const float* __restrict__ uy,
    double* __restrict__ block_ens, int nx, int ny)
{
    __shared__ double s[BLOCK];
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int tid = threadIdx.x;
    int N   = nx * ny;
    double ens = 0;
    if (idx < N) {
        int x = idx % nx, y = idx / nx;
        int xp = (x+1) % nx, xm = (x-1+nx) % nx;
        int yp = (y+1) % ny, ym = (y-1+ny) % ny;
        float duy_dx = (uy[y*nx+xp] - uy[y*nx+xm]) * 0.5f;
        float dux_dy = (ux[yp*nx+x] - ux[ym*nx+x]) * 0.5f;
        float w = duy_dx - dux_dy;
        ens = (double)(w * w);
    }
    s[tid] = ens;
    __syncthreads();
    for (int h = blockDim.x/2; h > 0; h >>= 1) {
        if (tid < h) s[tid] += s[tid+h];
        __syncthreads();
    }
    if (tid == 0) block_ens[blockIdx.x] = s[0];
}

__global__ void precipitate_drain(
    float* f, int cx, int cy, int radius,
    double* d_drained, int nx, int ny)
{
    int side  = 2 * radius + 1;
    int total = side * side;
    int tid   = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= total) return;

    int lx = tid % side - radius;
    int ly = tid / side - radius;
    float r2 = (float)(lx*lx + ly*ly);
    float R2 = (float)(radius * radius);
    if (r2 > R2) return;

    int gx  = (cx + lx + nx) % nx;
    int gy  = (cy + ly + ny) % ny;
    int idx = gy * nx + gx;
    int N   = nx * ny;

    float sigma2 = R2 * 0.25f;
    float weight = expf(-r2 / (2.0f * sigma2));

    float rho = 0;
    for (int i = 0; i < Q; i++) rho += f[i * N + idx];
    if (rho <= 1.0f) return;

    float excess  = rho - 1.0f;
    float drain   = excess * weight;
    float new_rho = rho - drain;
    float scale   = new_rho / rho;

    for (int i = 0; i < Q; i++)
        f[i * N + idx] *= scale;

    atomicAdd(d_drained, (double)drain);
}

__global__ void particle_sink(
    float* f, Particle* particles, int n_particles,
    float sink_rate, int radius, int nx, int ny)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int N   = nx * ny;
    if (idx >= N) return;

    int x = idx % nx;
    int y = idx / nx;
    float R2 = (float)(radius * radius);

    float rho = 0;
    for (int i = 0; i < Q; i++) rho += f[i * N + idx];

    float excess = rho - 1.0f;
    if (excess <= 0.0f) return;

    for (int p = 0; p < n_particles; p++) {
        if (!particles[p].alive) continue;

        int dx = x - (int)particles[p].x;
        int dy = y - (int)particles[p].y;
        if (dx >  nx/2) dx -= nx;  if (dx < -nx/2) dx += nx;
        if (dy >  ny/2) dy -= ny;  if (dy < -ny/2) dy += ny;
        float r2 = (float)(dx*dx + dy*dy);
        if (r2 >= R2) continue;

        float w     = expf(-r2 / (R2 * 0.25f));
        float drain = sink_rate * excess * w;
        drain = fminf(drain, excess * 0.5f);
        float scale = (rho - drain) / rho;

        for (int i = 0; i < Q; i++)
            f[i * N + idx] *= scale;

        atomicAdd(&particles[p].mass, drain);
        rho   -= drain;
        excess = rho - 1.0f;
        if (excess <= 0.0f) break;
    }
}

/* ---- Probe D variant: boosted accretion for first N particles ----------- */
__global__ void particle_sink_boosted(
    float* f, Particle* particles, int n_particles,
    float sink_rate, float boost_mult, int boost_count,
    int radius, int nx, int ny)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int N   = nx * ny;
    if (idx >= N) return;

    int x = idx % nx;
    int y = idx / nx;
    float R2 = (float)(radius * radius);

    float rho = 0;
    for (int i = 0; i < Q; i++) rho += f[i * N + idx];

    float excess = rho - 1.0f;
    if (excess <= 0.0f) return;

    for (int p = 0; p < n_particles; p++) {
        if (!particles[p].alive) continue;

        int dx = x - (int)particles[p].x;
        int dy = y - (int)particles[p].y;
        if (dx >  nx/2) dx -= nx;  if (dx < -nx/2) dx += nx;
        if (dy >  ny/2) dy -= ny;  if (dy < -ny/2) dy += ny;
        float r2 = (float)(dx*dx + dy*dy);
        if (r2 >= R2) continue;

        float rate = (p < boost_count) ? sink_rate * boost_mult : sink_rate;

        float w     = expf(-r2 / (R2 * 0.25f));
        float drain = rate * excess * w;
        drain = fminf(drain, excess * 0.5f);
        float scale = (rho - drain) / rho;

        for (int i = 0; i < Q; i++)
            f[i * N + idx] *= scale;

        atomicAdd(&particles[p].mass, drain);
        rho   -= drain;
        excess = rho - 1.0f;
        if (excess <= 0.0f) break;
    }
}

__global__ void advect_particles(
    Particle* particles, int n_particles,
    const float* __restrict__ ux, const float* __restrict__ uy,
    int steps, int nx, int ny)
{
    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    if (pid >= n_particles || !particles[pid].alive) return;

    Particle& p = particles[pid];
    int ix = ((int)p.x) % nx;  if (ix < 0) ix += nx;
    int iy = ((int)p.y) % ny;  if (iy < 0) iy += ny;
    int cell = iy * nx + ix;

    p.vx = ux[cell];
    p.vy = uy[cell];
    p.x += p.vx * steps;
    p.y += p.vy * steps;

    while (p.x <  0)   p.x += nx;
    while (p.x >= nx)   p.x -= nx;
    while (p.y <  0)   p.y += ny;
    while (p.y >= ny)   p.y -= ny;
}

__global__ void update_ghost_signature(
    Particle* particles, int n_particles,
    const float* __restrict__ ux, const float* __restrict__ uy,
    int nx, int ny)
{
    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    if (pid >= n_particles || !particles[pid].alive) return;

    Particle& p = particles[pid];
    int ix = ((int)p.x) % nx;  if (ix < 0) ix += nx;
    int iy = ((int)p.y) % ny;  if (iy < 0) iy += ny;
    int cell = iy * nx + ix;

    float speed = sqrtf(ux[cell]*ux[cell] + uy[cell]*uy[cell]);
    p.latent_energy = 0.99f * p.latent_energy + 0.01f * speed;
}

/* ---- PROBE A: Mass injection kernel ------------------------------------- 
 * Add a small density bump across the entire grid.
 * Not trying to be uniform — inject energy proportional to local density,
 * so hot spots get hotter and quiet spots barely change.
 * The fluid decides where to put it.
 * -------------------------------------------------------------------- */
__global__ void probe_inject_mass(float* f, float injection_factor, int N)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= N) return;

    /* Scale all distribution functions up by a tiny factor */
    for (int i = 0; i < Q; i++)
        f[i * N + idx] *= (1.0f + injection_factor);
}

/* ---- PROBE B: Lattice shear — rotate velocity in top 25% by 90° --------
 * For y >= 768: (ux, uy) → (-uy, ux)
 * This is done by reconstructing f from the rotated equilibrium,
 * blended with a fraction of the non-equilibrium part.
 * -------------------------------------------------------------------- */
__global__ void probe_rotate_top(float* f, float* rho, float* ux, float* uy,
                                  int nx, int ny)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int N = nx * ny;
    if (idx >= N) return;
    int y = idx / nx;

    /* Only affect top 25% */
    if (y < ny * 3 / 4) return;

    float r = rho[idx];
    float old_ux = ux[idx];
    float old_uy = uy[idx];

    /* 90° rotation: (ux, uy) → (-uy, ux) */
    float new_ux = -old_uy;
    float new_uy =  old_ux;

    float u2_new = new_ux * new_ux + new_uy * new_uy;

    /* Reconstruct equilibrium with rotated velocity */
    for (int i = 0; i < Q; i++) {
        float eu = (float)d_ex[i] * new_ux + (float)d_ey[i] * new_uy;
        float feq_new = d_w[i] * r * (1.f + 3.f*eu + 4.5f*eu*eu - 1.5f*u2_new);
        /* Hard set to new equilibrium — maximum disruption */
        f[i * N + idx] = feq_new;
    }
}

/* ============================================================================
 * HOST
 * ============================================================================ */

static void init_shear_layer(float* h_f, int nx, int ny)
{
    for (int y = 0; y < ny; y++) {
        float yrel  = (float)y - ny * 0.5f;
        float blend = 0.5f * (1.f + tanhf(yrel / SHEAR_DELTA));
        float umag  = U_BOT + (U_TOP - U_BOT) * blend;
        float ux    = umag * COS135;
        float uy    = umag * SIN135;
        float u2    = ux*ux + uy*uy;
        for (int x = 0; x < nx; x++) {
            int idx = y * nx + x;
            for (int i = 0; i < Q; i++) {
                float eu = h_ex[i]*ux + h_ey[i]*uy;
                h_f[i * (nx*ny) + idx] =
                    h_w[i] * (1.f + 3.f*eu + 4.5f*eu*eu - 1.5f*u2);
            }
        }
    }
}

static const char* fmt_time(int sec, char* buf)
{
    sprintf(buf, "%d:%02d:%02d", sec/3600, (sec%3600)/60, sec%60);
    return buf;
}

/* ============================================================================
 * MAIN
 * ============================================================================ */
int main()
{
    printf("\n===================================================================\n");
    printf("  P R O B E — Stress-Response Forensics\n");
    printf("===================================================================\n");
    printf("  Probe A  cy %d-%d:  Metabolic Injection (+mass)\n",
           PROBE_A_START, PROBE_A_END);
    printf("  Probe B  cy %d:     Lattice Shear (top 25%% rotated 90°)\n",
           PROBE_B_CYCLE);
    printf("  Probe C  cy %d-%d: VRM Silence (omega locked 1.25)\n",
           PROBE_C_START, PROBE_C_END);
    printf("  Probe D  cy %d-%d: Vacuum Trap (%d particles at %dx accretion)\n",
           PROBE_D_START, PROBE_D_END, PROBE_D_COUNT, (int)PROBE_D_MULT);
    printf("===================================================================\n\n");

    /* ---- CUDA ---- */
    cudaSetDevice(0);
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    printf("[CUDA] %s  SM %d.%d  SMs: %d\n",
           prop.name, prop.major, prop.minor, prop.multiProcessorCount);

    /* ---- NVML ---- */
    nvmlInit_v2();
    nvmlDevice_t nvdev;
    nvmlDeviceGetHandleByIndex_v2(0, &nvdev);
    unsigned int pw = 0;
    nvmlDeviceGetPowerUsage(nvdev, &pw);
    printf("[NVML] Idle: %.1f W\n\n", pw / 1000.f);

    /* ---- Allocate ---- */
    size_t fbuf = (size_t)Q * NN * sizeof(float);
    float *f0, *f1, *d_rho, *d_ux, *d_uy;
    cudaMalloc(&f0,    fbuf);
    cudaMalloc(&f1,    fbuf);
    cudaMalloc(&d_rho, NN * sizeof(float));
    cudaMalloc(&d_ux,  NN * sizeof(float));
    cudaMalloc(&d_uy,  NN * sizeof(float));

    float *d_bsmin, *d_bsmax, *d_brmin, *d_brmax;
    cudaMalloc(&d_bsmin, NUM_BLOCKS * sizeof(float));
    cudaMalloc(&d_bsmax, NUM_BLOCKS * sizeof(float));
    cudaMalloc(&d_brmin, NUM_BLOCKS * sizeof(float));
    cudaMalloc(&d_brmax, NUM_BLOCKS * sizeof(float));
    float* h_bsmin = (float*)malloc(NUM_BLOCKS * sizeof(float));
    float* h_bsmax = (float*)malloc(NUM_BLOCKS * sizeof(float));
    float* h_brmin = (float*)malloc(NUM_BLOCKS * sizeof(float));
    float* h_brmax = (float*)malloc(NUM_BLOCKS * sizeof(float));

    double *d_rhosum;
    cudaMalloc(&d_rhosum, NUM_BLOCKS * sizeof(double));
    double* h_rhosum = (double*)malloc(NUM_BLOCKS * sizeof(double));

    double *d_enstrophy;
    cudaMalloc(&d_enstrophy, NUM_BLOCKS * sizeof(double));
    double* h_enstrophy = (double*)malloc(NUM_BLOCKS * sizeof(double));

    double *d_drained;
    cudaMalloc(&d_drained, sizeof(double));

    float* h_rho = (float*)malloc(NN * sizeof(float));

    Particle* d_particles;
    cudaMalloc(&d_particles, MAX_PARTICLES * sizeof(Particle));
    cudaMemset(d_particles, 0, MAX_PARTICLES * sizeof(Particle));
    Particle h_particles[MAX_PARTICLES];
    memset(h_particles, 0, sizeof(h_particles));
    int    n_particles          = 0;
    double total_particle_mass  = 0;
    int    total_precipitations = 0;

    /* ---- Init shear layer ---- */
    float* h_f = (float*)malloc(fbuf);
    init_shear_layer(h_f, NX, NY);

    double M0 = 0;
    for (int idx = 0; idx < NN; idx++) {
        double rl = 0;
        for (int i = 0; i < Q; i++) rl += (double)h_f[i * NN + idx];
        M0 += rl;
    }
    cudaMemcpy(f0, h_f, fbuf, cudaMemcpyHostToDevice);
    cudaMemcpy(f1, h_f, fbuf, cudaMemcpyHostToDevice);
    free(h_f);

    /* ---- Warmup ---- */
    float power_ema = pw / 1000.f;
    int   cur = 0;
    for (int w = 0; w < 5; w++) {
        for (int s = 0; s < STEPS_PER_BATCH; s++) {
            float* src = (cur == 0) ? f0 : f1;
            float* dst = (cur == 0) ? f1 : f0;
            collide_stream<<<NUM_BLOCKS, BLOCK>>>(
                src, dst, d_rho, d_ux, d_uy, OMEGA_BASE, NX, NY);
            cur ^= 1;
        }
        cudaDeviceSynchronize();
        nvmlDeviceGetPowerUsage(nvdev, &pw);
        power_ema = 0.95f * power_ema + 0.05f * (pw / 1000.f);
    }

    /* Re-init */
    h_f = (float*)malloc(fbuf);
    init_shear_layer(h_f, NX, NY);
    cudaMemcpy(f0, h_f, fbuf, cudaMemcpyHostToDevice);
    cudaMemcpy(f1, h_f, fbuf, cudaMemcpyHostToDevice);
    free(h_f);
    cur = 0;
    printf("  Power EMA: %.1f W — lattice re-initialized\n\n", power_ema);

    /* ---- CSV ---- */
    FILE* csv = fopen("probe_beast_run.csv", "w");
    fprintf(csv, "cycle,batch,elapsed_s,omega,power_w,speed_min,speed_max,"
                 "rho_min,rho_max,enstrophy,"
                 "n_particles,particle_mass,m_fluid,m_total,probe\n");

    /* ---- Header ---- */
    printf("  cyc  |  T+      |  omega  | speed range  "
           "| rho range          | enst       | part | p.mass   | M_total     | probe\n");
    printf("  -----|----------|---------|-------------- "
           "|--------------------|------------|------|----------|-------------|------\n");

    auto t0 = std::chrono::steady_clock::now();
    int  cycle = 0;
    float omega = OMEGA_BASE;

    /* Snapshot values for delta reporting */
    double pre_probe_m_total   = 0;
    double pre_probe_enstrophy = 0;
    float  pre_probe_rho_max   = 0;
    int    pre_probe_n_particles = 0;
    float  pre_probe_latent[MAX_PARTICLES];
    memset(pre_probe_latent, 0, sizeof(pre_probe_latent));

    while (cycle < MAX_CYCLES) {
        auto now = std::chrono::steady_clock::now();
        int  elapsed = (int)std::chrono::duration_cast<std::chrono::seconds>(
                            now - t0).count();

        /* ---- Identify probe phase ---- */
        const char* probe_label = "---";
        bool probe_a = (cycle >= PROBE_A_START && cycle <= PROBE_A_END);
        bool probe_b = (cycle == PROBE_B_CYCLE);
        bool probe_c = (cycle >= PROBE_C_START && cycle <= PROBE_C_END);
        bool probe_d = (cycle >= PROBE_D_START && cycle <= PROBE_D_END);

        if (probe_a) probe_label = "INJ";
        else if (probe_b) probe_label = "SHEAR";
        else if (probe_c) probe_label = "SILENT";
        else if (probe_d) probe_label = "TRAP";

        /* ---- Snapshot before probe starts ---- */
        if (cycle == PROBE_A_START || cycle == PROBE_B_CYCLE ||
            cycle == PROBE_C_START || cycle == PROBE_D_START) {
            rho_sum_reduce<<<NUM_BLOCKS, BLOCK>>>(d_rho, d_rhosum, NN);
            cudaDeviceSynchronize();
            cudaMemcpy(h_rhosum, d_rhosum, NUM_BLOCKS*sizeof(double),
                       cudaMemcpyDeviceToHost);
            pre_probe_m_total = 0;
            for (int b = 0; b < NUM_BLOCKS; b++) pre_probe_m_total += h_rhosum[b];
            pre_probe_m_total += total_particle_mass;
            pre_probe_n_particles = n_particles;

            /* Save latent energies for comparison */
            for (int p = 0; p < n_particles; p++)
                pre_probe_latent[p] = h_particles[p].latent_energy;

            printf("\n  >>>>>> PROBE START: %s at cycle %d\n", probe_label, cycle);
            printf("  >>>>>> Pre-probe: M_total=%.2f  particles=%d  rho_max=%.5f\n",
                   pre_probe_m_total, n_particles, pre_probe_rho_max);
            fflush(stdout);
        }

        float cy_rmax = 0, cy_rmin = 2.f;
        float cy_smax = 0, cy_smin = 1.f;
        double cy_ens = 0;

        for (int batch = 0; batch < BATCHES_PER_CYCLE; batch++) {

            /* ---- VRM ---- */
            nvmlDeviceGetPowerUsage(nvdev, &pw);
            float p_now = pw / 1000.f;
            power_ema = 0.95f * power_ema + 0.05f * p_now;
            float dp = (p_now - power_ema) / fmaxf(power_ema, 1.f);

            /* ---- PROBE C: VRM Silence — lock omega ---- */
            if (probe_c) {
                omega = OMEGA_BASE;  /* fixed at 1.25 — no hardware coupling */
            } else {
                omega = OMEGA_BASE * (1.f + VRM_ALPHA * dp);
                if (omega < OMEGA_CLAMP_LO) omega = OMEGA_CLAMP_LO;
                if (omega > OMEGA_CLAMP_HI) omega = OMEGA_CLAMP_HI;
            }

            /* ---- LBM steps ---- */
            for (int s = 0; s < STEPS_PER_BATCH; s++) {
                float* src = (cur == 0) ? f0 : f1;
                float* dst = (cur == 0) ? f1 : f0;
                collide_stream<<<NUM_BLOCKS, BLOCK>>>(
                    src, dst, d_rho, d_ux, d_uy, omega, NX, NY);
                cur ^= 1;
            }

            /* ---- Phase 2: Torque bias ---- */
            {
                float* f_cur = (cur == 0) ? f0 : f1;
                apply_torque_bias<<<NUM_BLOCKS, BLOCK>>>(
                    f_cur, d_ux, d_uy, d_rho, TORQUE_STRENGTH, NX, NY);
            }

            /* ---- PROBE A: Mass injection (every batch during active) ---- */
            if (probe_a) {
                float* f_cur = (cur == 0) ? f0 : f1;
                /* injection_factor chosen to add ~5.0 total mass per cycle
                   across 200 batches over 1M cells:
                   5.0 / (200 * 1048576) ≈ 2.4e-8 per cell per batch */
                float injection = 2.4e-8f;
                probe_inject_mass<<<NUM_BLOCKS, BLOCK>>>(f_cur, injection, NN);
            }

            /* ---- PROBE B: Lattice shear (once, first batch of trigger cycle) ---- */
            if (probe_b && batch == 0) {
                float* f_cur = (cur == 0) ? f0 : f1;
                probe_rotate_top<<<NUM_BLOCKS, BLOCK>>>(
                    f_cur, d_rho, d_ux, d_uy, NX, NY);
                cudaDeviceSynchronize();
                printf("  ****** SHEAR APPLIED: Top 25%% velocity rotated 90° ******\n");
                fflush(stdout);
            }

            /* ---- Field stats ---- */
            field_reduce<<<NUM_BLOCKS, BLOCK>>>(
                d_ux, d_uy, d_rho, d_bsmin, d_bsmax, d_brmin, d_brmax, NN);
            cudaDeviceSynchronize();
            cudaMemcpy(h_bsmin, d_bsmin, NUM_BLOCKS*sizeof(float),
                       cudaMemcpyDeviceToHost);
            cudaMemcpy(h_bsmax, d_bsmax, NUM_BLOCKS*sizeof(float),
                       cudaMemcpyDeviceToHost);
            cudaMemcpy(h_brmin, d_brmin, NUM_BLOCKS*sizeof(float),
                       cudaMemcpyDeviceToHost);
            cudaMemcpy(h_brmax, d_brmax, NUM_BLOCKS*sizeof(float),
                       cudaMemcpyDeviceToHost);

            float smin = h_bsmin[0], smax = h_bsmax[0];
            float rmin = h_brmin[0], rmax = h_brmax[0];
            for (int b = 1; b < NUM_BLOCKS; b++) {
                smin = fminf(smin, h_bsmin[b]);
                smax = fmaxf(smax, h_bsmax[b]);
                rmin = fminf(rmin, h_brmin[b]);
                rmax = fmaxf(rmax, h_brmax[b]);
            }
            if (rmax > cy_rmax) cy_rmax = rmax;
            if (rmin < cy_rmin) cy_rmin = rmin;
            if (smax > cy_smax) cy_smax = smax;
            if (smin < cy_smin) cy_smin = smin;

            /* ---- PRECIPITATION ---- */
            if (rmax > RHO_THRESH && n_particles < MAX_PARTICLES) {
                cudaMemcpy(h_rho, d_rho, NN*sizeof(float),
                           cudaMemcpyDeviceToHost);
                float best = 0;
                int   hot  = 0;
                for (int i = 0; i < NN; i++) {
                    if (h_rho[i] > best) { best = h_rho[i]; hot = i; }
                }
                int hx = hot % NX, hy = hot / NX;

                bool skip = false;
                for (int p = 0; p < n_particles; p++) {
                    if (!h_particles[p].alive) continue;
                    int ddx = hx - (int)h_particles[p].x;
                    int ddy = hy - (int)h_particles[p].y;
                    if (ddx >  NX/2) ddx -= NX;
                    if (ddx < -NX/2) ddx += NX;
                    if (ddy >  NY/2) ddy -= NY;
                    if (ddy < -NY/2) ddy += NY;
                    if (ddx*ddx + ddy*ddy < DRAIN_RADIUS*DRAIN_RADIUS) {
                        skip = true; break;
                    }
                }

                if (!skip) {
                    double zero = 0;
                    cudaMemcpy(d_drained, &zero, sizeof(double),
                               cudaMemcpyHostToDevice);
                    int side = 2 * DRAIN_RADIUS + 1;
                    int dtot = side * side;
                    float* f_cur = (cur == 0) ? f0 : f1;
                    precipitate_drain<<<GBLK(dtot), BLOCK>>>(
                        f_cur, hx, hy, DRAIN_RADIUS, d_drained, NX, NY);
                    cudaDeviceSynchronize();

                    double drained = 0;
                    cudaMemcpy(&drained, d_drained, sizeof(double),
                               cudaMemcpyDeviceToHost);

                    if (drained > 1e-4) {
                        int slot = n_particles;
                        h_particles[slot].x             = (float)hx;
                        h_particles[slot].y             = (float)hy;
                        h_particles[slot].vx            = 0;
                        h_particles[slot].vy            = 0;
                        h_particles[slot].mass          = (float)drained;
                        h_particles[slot].alive         = 1;
                        h_particles[slot].birth_cycle   = cycle;
                        h_particles[slot].latent_energy = 0;
                        n_particles++;
                        total_precipitations++;

                        cudaMemcpy(d_particles, h_particles,
                                   n_particles * sizeof(Particle),
                                   cudaMemcpyHostToDevice);

                        now = std::chrono::steady_clock::now();
                        elapsed = (int)std::chrono::duration_cast<
                            std::chrono::seconds>(now - t0).count();
                        char tb[32]; fmt_time(elapsed, tb);
                        printf("  ** NEW GUARDIAN  T+%s  cy%d b%d  "
                               "(%d,%d)  rho=%.5f  accreted=%.4f  "
                               "total=%d  [%s]\n",
                               tb, cycle, batch, hx, hy,
                               best, drained, n_particles, probe_label);
                        fflush(stdout);
                    }
                }
            }

            /* ---- Particle dynamics ---- */
            if (n_particles > 0) {
                float* f_cur = (cur == 0) ? f0 : f1;

                advect_particles<<<GBLK(n_particles), BLOCK>>>(
                    d_particles, n_particles,
                    d_ux, d_uy, STEPS_PER_BATCH, NX, NY);

                /* ---- PROBE D: Vacuum trap — boosted accretion ---- */
                if (probe_d) {
                    particle_sink_boosted<<<NUM_BLOCKS, BLOCK>>>(
                        f_cur, d_particles, n_particles,
                        SINK_RATE, PROBE_D_MULT, PROBE_D_COUNT,
                        SINK_RADIUS, NX, NY);
                } else {
                    particle_sink<<<NUM_BLOCKS, BLOCK>>>(
                        f_cur, d_particles, n_particles,
                        SINK_RATE, SINK_RADIUS, NX, NY);
                }

                update_ghost_signature<<<GBLK(n_particles), BLOCK>>>(
                    d_particles, n_particles, d_ux, d_uy, NX, NY);

                cudaDeviceSynchronize();

                cudaMemcpy(h_particles, d_particles,
                           n_particles * sizeof(Particle),
                           cudaMemcpyDeviceToHost);

                total_particle_mass = 0;
                for (int p = 0; p < n_particles; p++)
                    if (h_particles[p].alive)
                        total_particle_mass += h_particles[p].mass;
            }

            /* CSV every 10th batch */
            if (batch % 10 == 0) {
                enstrophy_reduce<<<NUM_BLOCKS, BLOCK>>>(
                    d_ux, d_uy, d_enstrophy, NX, NY);
                cudaDeviceSynchronize();
                cudaMemcpy(h_enstrophy, d_enstrophy,
                           NUM_BLOCKS*sizeof(double), cudaMemcpyDeviceToHost);
                double ens = 0;
                for (int b = 0; b < NUM_BLOCKS; b++) ens += h_enstrophy[b];
                cy_ens = ens;

                now = std::chrono::steady_clock::now();
                elapsed = (int)std::chrono::duration_cast<
                    std::chrono::seconds>(now - t0).count();

                rho_sum_reduce<<<NUM_BLOCKS, BLOCK>>>(d_rho, d_rhosum, NN);
                cudaDeviceSynchronize();
                cudaMemcpy(h_rhosum, d_rhosum, NUM_BLOCKS*sizeof(double),
                           cudaMemcpyDeviceToHost);
                double Mf = 0;
                for (int b = 0; b < NUM_BLOCKS; b++) Mf += h_rhosum[b];

                fprintf(csv,
                    "%d,%d,%d,%.4f,%.1f,%.6e,%.6e,%.6f,%.6f,%.6e,"
                    "%d,%.4f,%.2f,%.2f,%s\n",
                    cycle, batch, elapsed, omega, p_now,
                    smin, smax, rmin, rmax, ens,
                    n_particles, total_particle_mass,
                    Mf, Mf + total_particle_mass, probe_label);
            }
        } /* batch */

        /* ---- Cycle summary ---- */
        now = std::chrono::steady_clock::now();
        elapsed = (int)std::chrono::duration_cast<
            std::chrono::seconds>(now - t0).count();
        char tb[32]; fmt_time(elapsed, tb);

        rho_sum_reduce<<<NUM_BLOCKS, BLOCK>>>(d_rho, d_rhosum, NN);
        cudaDeviceSynchronize();
        cudaMemcpy(h_rhosum, d_rhosum, NUM_BLOCKS*sizeof(double),
                   cudaMemcpyDeviceToHost);
        double M_fluid = 0;
        for (int b = 0; b < NUM_BLOCKS; b++) M_fluid += h_rhosum[b];
        double M_all = M_fluid + total_particle_mass;

        printf("  %4d | %s | %.4f | %.6e "
               "| [%.5f,%.5f] | %.3e | %4d | %8.2f | %11.2f | %s\n",
               cycle, tb, omega,
               cy_smax - cy_smin,
               cy_rmin, cy_rmax, cy_ens,
               n_particles, total_particle_mass, M_all, probe_label);

        pre_probe_rho_max = cy_rmax;

        /* Ghost signature report every 50 cycles + at probe boundaries */
        bool ghost_report = (n_particles > 0 && cycle > 0 &&
                            (cycle % 50 == 0 ||
                             cycle == PROBE_A_END + 1 ||
                             cycle == PROBE_B_CYCLE + 1 ||
                             cycle == PROBE_C_END + 1 ||
                             cycle == PROBE_D_END + 1));

        if (ghost_report) {
            printf("  [GHOST] Particle positions (first 20):\n");
            for (int p = 0; p < n_particles && p < 20; p++) {
                if (!h_particles[p].alive) continue;
                float delta_latent = h_particles[p].latent_energy -
                                     pre_probe_latent[p];
                printf("    #%d  pos(%6.1f,%6.1f)  mass=%.2f  "
                       "latent=%.3e  delta=%+.3e  %s\n",
                       p, h_particles[p].x, h_particles[p].y,
                       h_particles[p].mass, h_particles[p].latent_energy,
                       delta_latent,
                       h_particles[p].latent_energy < 1e-6 ?
                           "SILENCE" : "PULSE");
            }
        }

        /* ---- Post-probe delta reports ---- */
        if (cycle == PROBE_A_END + 1 || cycle == PROBE_B_CYCLE + 50 ||
            cycle == PROBE_C_END + 1 || cycle == PROBE_D_END + 1) {
            printf("\n  <<<<<< PROBE RECOVERY REPORT at cycle %d\n", cycle);
            printf("  <<<<<< M_total: %.2f  (delta from pre-probe: %+.2f)\n",
                   M_all, M_all - pre_probe_m_total);
            printf("  <<<<<< Particles: %d (was %d)\n",
                   n_particles, pre_probe_n_particles);
            if (n_particles > pre_probe_n_particles) {
                printf("  <<<<<< ** NEW GUARDIANS BORN from the perturbation\n");
            }
            printf("  <<<<<< Enstrophy: %.3e\n", cy_ens);
            fflush(stdout);
        }

        fflush(stdout);
        fflush(csv);
        cycle++;
    }

    /* ---- Final report ---- */
    printf("\n===================================================================\n");
    printf("  PROBE — FINAL REPORT\n");
    printf("===================================================================\n");
    printf("  Cycles run:       %d\n", cycle);
    printf("  Total guardians:  %d (born: %d)\n", n_particles, total_precipitations);

    rho_sum_reduce<<<NUM_BLOCKS, BLOCK>>>(d_rho, d_rhosum, NN);
    cudaDeviceSynchronize();
    cudaMemcpy(h_rhosum, d_rhosum, NUM_BLOCKS*sizeof(double),
               cudaMemcpyDeviceToHost);
    double Mf = 0;
    for (int b = 0; b < NUM_BLOCKS; b++) Mf += h_rhosum[b];

    printf("  M0:               %.6f\n", M0);
    printf("  M_fluid (final):  %.6f\n", Mf);
    printf("  M_particles:      %.4f\n", total_particle_mass);
    printf("  M_total:          %.6f\n", Mf + total_particle_mass);

    /* Full particle census */
    if (n_particles > 0) {
        printf("\n  FULL GUARDIAN CENSUS:\n");
        printf("    #   | born | pos            | vel              | mass     | latent\n");
        printf("    ----|------|----------------|------------------|----------|--------\n");
        for (int p = 0; p < n_particles; p++) {
            if (!h_particles[p].alive) continue;
            printf("    %3d | C%-3d | (%6.1f,%6.1f) | (%+.2e,%+.2e) | %8.3f | %.3e %s\n",
                   p, h_particles[p].birth_cycle,
                   h_particles[p].x, h_particles[p].y,
                   h_particles[p].vx, h_particles[p].vy,
                   h_particles[p].mass, h_particles[p].latent_energy,
                   h_particles[p].latent_energy < 1e-6 ? "[SILENT]" : "[PULSE]");
        }
    }

    printf("===================================================================\n");

    fclose(csv);
    cudaFree(f0); cudaFree(f1);
    cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy);
    cudaFree(d_bsmin); cudaFree(d_bsmax);
    cudaFree(d_brmin); cudaFree(d_brmax);
    cudaFree(d_rhosum); cudaFree(d_enstrophy);
    cudaFree(d_drained); cudaFree(d_particles);
    nvmlShutdown();
    free(h_bsmin); free(h_bsmax); free(h_brmin); free(h_brmax);
    free(h_rhosum); free(h_enstrophy); free(h_rho);
    return 0;
}
