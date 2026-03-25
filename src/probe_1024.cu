/* ============================================================================
 * PROBE 1024x1024 - ORIGINAL BEAST VERSION
 * Scaled back from GTX 1050 adaptation to original Beast specs
 * 
 * Original: 1024x1024 grid with 194 guardians
 * GTX 1050: 256x256 grid with 13 guardians (0.25 linear, 0.0625 area scaling)
 * 
 * Now: Back to 1024x1024 with 194 guardians
 * ============================================================================ */

#include <cuda_runtime.h>
#include <nvml.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <chrono>

/* ---- Grid --------------------------------------------------------------- */
#define NX    1024     /* ORIGINAL BEAST: 1024 (was 256 for GTX 1050) */
#define NY    1024     /* ORIGINAL BEAST: 1024 (was 256 for GTX 1050) */
#define NN    (NX * NY)  /* 1,048,576 nodes (was 65,536) */
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)
#define NUM_BLOCKS GBLK(NN)

/* ---- Protocol ----------------------------------------------------------- */
#define STEPS_PER_BATCH    500
#define BATCHES_PER_CYCLE  200
#define MAX_CYCLES         0          /* REMOVED LIMIT: Run indefinitely */

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
#define RHO_THRESH      1.00022f    /* Same threshold */
#define DRAIN_RADIUS    16          /* SCALED BACK: 4 ÷ 0.25 = 16 */
#define SINK_RADIUS     24          /* SCALED BACK: 6 ÷ 0.25 = 24 */
#define SINK_RATE       0.005f      /* SCALED BACK: 0.0003125 ÷ 0.0625 = 0.005 */
#define MAX_PARTICLES   194         /* ORIGINAL BEAST: 194 guardians */

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
    float latent;
    int born_cycle;
    char state[16];
};

/* ---- CUDA error checking ------------------------------------------------ */
#define CUDA_CHECK(call)                                             \
    do {                                                             \
        cudaError_t err = (call);                                    \
        if (err != cudaSuccess) {                                    \
            fprintf(stderr, "CUDA error at %s:%d: %s\n",             \
                    __FILE__, __LINE__, cudaGetErrorString(err));    \
            exit(EXIT_FAILURE);                                      \
        }                                                            \
    } while(0)

/* ---- Format time -------------------------------------------------------- */
static void fmt_time(long long sec, char* buf) {
    int h = (int)(sec / 3600);
    int m = (int)((sec % 3600) / 60);
    int s = (int)(sec % 60);
    snprintf(buf, 32, "%d:%02d:%02d", h, m, s);
}

/* ============================================================================
 *   K E R N E L S
 * ============================================================================ */

/* ---- LBM collide & stream ----------------------------------------------- */
__global__ void lbm_collide_stream(const float* __restrict__ f_src,
                                   float* __restrict__ f_dst,
                                   float* __restrict__ rho,
                                   float* __restrict__ ux,
                                   float* __restrict__ uy,
                                   float omega, int nx, int ny) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N = nx * ny;
    if (idx >= N) return;
    const int x = idx % nx, y = idx / nx;

    float fl[Q];
    for (int i = 0; i < Q; i++) {
        int sx = (x - d_ex[i] + nx) % nx;
        int sy = (y - d_ey[i] + ny) % ny;
        fl[i] = f_src[i * N + sy * nx + sx];
    }

    float rho_val = 0.f, ux_val = 0.f, uy_val = 0.f;
    for (int i = 0; i < Q; i++) {
        rho_val += fl[i];
        ux_val += (float)d_ex[i] * fl[i];
        uy_val += (float)d_ey[i] * fl[i];
    }
    float inv = 1.f / fmaxf(rho_val, 1e-10f);
    ux_val *= inv; uy_val *= inv;
    rho[idx] = rho_val; ux[idx] = ux_val; uy[idx] = uy_val;

    const float u2 = ux_val * ux_val + uy_val * uy_val;
    for (int i = 0; i < Q; i++) {
        float eu = (float)d_ex[i] * ux_val + (float)d_ey[i] * uy_val;
        float feq = d_w[i] * rho_val * (1.f + 3.f*eu + 4.5f*eu*eu - 1.5f*u2);
        f_dst[i * N + idx] = fl[i] - omega * (fl[i] - feq);
    }
}

/* ---- Reduce to find max rho --------------------------------------------- */
__global__ void rho_max_reduce(const float* rho, float* maxval, int* maxidx, int N) {
    extern __shared__ float sdata[];
    int tid = threadIdx.x;
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    
    float myval = (i < N) ? rho[i] : -1e30f;
    int myidx = (i < N) ? i : -1;
    
    sdata[tid] = myval;
    __syncthreads();
    
    for (unsigned int s = blockDim.x / 2; s > 0; s >>= 1) {
        if (tid < s) {
            if (sdata[tid + s] > sdata[tid]) {
                sdata[tid] = sdata[tid + s];
            }
        }
        __syncthreads();
    }
    
    if (tid == 0) {
        maxval[blockIdx.x] = sdata[0];
        // For simplicity, we just store block max, not exact index
    }
}

/* ---- Particle update ---------------------------------------------------- */
__global__ void update_particles(Particle* particles, int n_particles,
                                 const float* rho, const float* ux, const float* uy,
                                 int nx, int ny, float sink_rate, int sink_radius) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= n_particles) return;
    
    Particle* p = &particles[idx];
    
    // Convert fractional position to grid cell
    int cx = (int)p->x;
    int cy = (int)p->y;
    
    // Accrete mass from surrounding area
    float acc = 0.0f;
    for (int dy = -sink_radius; dy <= sink_radius; dy++) {
        for (int dx = -sink_radius; dx <= sink_radius; dx++) {
            int gx = (cx + dx + nx) % nx;
            int gy = (cy + dy + ny) % ny;
            int gi = gy * nx + gx;
            
            // Sink mass from grid to particle
            float drho = (rho[gi] - 1.0f) * sink_rate;
            acc += drho;
        }
    }
    
    p->mass += acc;
    
    // Update position based on local velocity
    int gi = cy * nx + cx;
    p->x += ux[gi];
    p->y += uy[gi];
    
    // Wrap around
    if (p->x < 0) p->x += nx;
    if (p->x >= nx) p->x -= nx;
    if (p->y < 0) p->y += ny;
    if (p->y >= ny) p->y -= ny;
    
    // Update velocity
    p->vx = ux[gi];
    p->vy = uy[gi];
}

/* ============================================================================
 *   M A I N
 * ============================================================================ */

int main() {
    printf("===================================================================\n");
    printf("  P R O B E 1024 — ORIGINAL BEAST VERSION\n");
    printf("  Grid: %dx%d, Max guardians: %d\n", NX, NY, MAX_PARTICLES);
    printf("===================================================================\n\n");
    
    // CUDA setup
    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, 0));
    printf("[CUDA] %s  SM %d.%d  SMs: %d\n", prop.name, prop.major, prop.minor, prop.multiProcessorCount);
    
    // NVML power monitoring
    nvmlInit();
    nvmlDevice_t nvml_dev;
    nvmlDeviceGetHandleByIndex(0, &nvml_dev);
    unsigned int power_mW;
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("[NVML] Idle: %.1f W\n", power_mW / 1000.0f);
    
    // Allocate LBM arrays
    float *d_f0, *d_f1, *d_rho, *d_ux, *d_uy;
    float *h_rho;
    
    CUDA_CHECK(cudaMalloc(&d_f0, Q * NN * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&d_f1, Q * NN * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&d_rho, NN * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&d_ux, NN * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&d_uy, NN * sizeof(float)));
    
    h_rho = (float*)malloc(NN * sizeof(float));
    
    // Initialize distribution (equilibrium + shear)
    float* h_f0 = (float*)malloc(Q * NN * sizeof(float));
    for (int y = 0; y < NY; y++) {
        float uy_shear = U_TOP - (U_TOP - U_BOT) * ((float)y / (NY - 1));
        for (int x = 0; x < NX; x++) {
            int idx = y * NX + x;
            float ux_val = 0.0f;
            float uy_val = uy_shear;
            float rho_val = 1.0f;
            
            for (int i = 0; i < Q; i++) {
                float eu = (float)h_ex[i] * ux_val + (float)h_ey[i] * uy_val;
                float feq = h_w[i] * rho_val * (1.f + 3.f*eu + 4.5f*eu*eu - 1.5f*(ux_val*ux_val + uy_val*uy_val));
                h_f0[i * NN + idx] = feq;
            }
        }
    }
    CUDA_CHECK(cudaMemcpy(d_f0, h_f0, Q * NN * sizeof(float), cudaMemcpyHostToDevice));
    free(h_f0);
    
    // Particle system
    Particle* d_particles;
    CUDA_CHECK(cudaMalloc(&d_particles, MAX_PARTICLES * sizeof(Particle)));
    CUDA_CHECK(cudaMemset(d_particles, 0, MAX_PARTICLES * sizeof(Particle)));
    
    Particle h_particles[MAX_PARTICLES];
    memset(h_particles, 0, sizeof(h_particles));
    int n_particles = 0;
    int total_precipitations = 0;
    
    // Main loop
    auto t0 = std::chrono::steady_clock::now();
    int cycle = 0;
    int cur = 0;
    float omega = OMEGA_BASE;
    
    printf("\n  cyc  |  T+      |  omega  | speed range  | rho range          | enst       | part | p.mass   | M_total     | probe\n");
    printf("  -----|----------|---------|-------------- |--------------------|------------|------|----------|-------------|------\n");
    
    // Run for 30 minutes (1800 seconds)
    while (true) {
        // Run one cycle (200 batches of 500 steps each)
        for (int batch = 0; batch < BATCHES_PER_CYCLE; batch++) {
            // Run STEPS_PER_BATCH LBM steps
            for (int s = 0; s < STEPS_PER_BATCH; s++) {
                lbm_collide_stream<<<NUM_BLOCKS, BLOCK>>>(
                    (cur == 0) ? d_f0 : d_f1,
                    (cur == 0) ? d_f1 : d_f0,
                    d_rho, d_ux, d_uy, omega, NX, NY);
                CUDA_CHECK(cudaDeviceSynchronize());
                cur = 1 - cur;
            }
            
            // Update particles
            if (n_particles > 0) {
                update_particles<<<GBLK(n_particles), BLOCK>>>(
                    d_particles, n_particles, d_rho, d_ux, d_uy,
                    NX, NY, SINK_RATE, SINK_RADIUS);
                CUDA_CHECK(cudaDeviceSynchronize());
            }
            
            // Check for new guardians (every 10 batches)
            if (batch % 10 == 0 && n_particles < MAX_PARTICLES) {
                // Copy rho to host to find max
                CUDA_CHECK(cudaMemcpy(h_rho, d_rho, NN * sizeof(float), cudaMemcpyDeviceToHost));
                
                float rmax = -1e30f;
                int rmax_idx = -1;
                for (int i = 0; i < NN; i++) {
                    if (h_rho[i] > rmax) {
                        rmax = h_rho[i];
                        rmax_idx = i;
                    }
                }
                
                // Check if precipitation occurs
                if (rmax > RHO_THRESH) {
                    int px = rmax_idx % NX;
                    int py = rmax_idx / NX;
                    
                    // Create new guardian
                    h_particles[n_particles].x = px;
                    h_particles[n_particles].y = py;
                    h_particles[n_particles].mass = 0.0f;
                    h_particles[n_particles].latent = 0.0f;
                    h_particles[n_particles].born_cycle = cycle;
                    strcpy(h_particles[n_particles].state, "PULSE");
                    
                    // Copy back to device
                    CUDA_CHECK(cudaMemcpy(&d_particles[n_particles], &h_particles[n_particles], 
                                         sizeof(Particle), cudaMemcpyHostToDevice));
                    
                    n_particles++;
                    total_precipitations++;
                    
                    // Report
                    auto now = std::chrono::steady_clock::now();
                    long long elapsed = std::chrono::duration_cast<std::chrono::seconds>(now - t0).count();
                    char tb[32]; fmt_time(elapsed, tb);
                    printf("  ** NEW GUARDIAN  T+%s  cy%d b%d  (%d,%d)  rho=%.5f  total=%d\n",
                           tb, cycle, batch, px, py, rmax, n_particles);
                }
            }
        }
        
        // End of cycle reporting
        nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
        float power_W = power_mW / 1000.0f;
        
        auto now = std::chrono::steady_clock::now();
        long long elapsed = std::chrono::duration_cast<std::chrono::seconds>(now - t0).count();
        char tb[32]; fmt_time(elapsed, tb);
        
        // Calculate total mass
        float total_mass = 0.0f;
        for (int i = 0; i < n_particles; i++) {
            total_mass += h_particles[i].mass;
        }
        
        printf("  %4d | %s | %6.3f |              | [1.00000,%.5f] |            | %4d | %8.2f | %11.2f | ---\n",
               cycle, tb, omega, 1.00000f, n_particles, total_mass / n_particles, total_mass);
        
        cycle++;
        
        // Stop after 30 minutes (1800 seconds)
        if (elapsed > 1800) {
            printf("\n[TIME] 30 minutes reached (confirmation test complete)\n");
            break;
        }
    }
    
    // Final report
    auto t_end = std::chrono::steady_clock::now();
    long long total_seconds = std::chrono::duration_cast<std::chrono::seconds>(t_end - t0).count();
    
    printf("\n===================================================================\n");
    printf("  FINAL REPORT - PROBE 1024\n");
    printf("===================================================================\n");
    printf("  Cycles run:       %d\n", cycle);
    printf("  Total guardians:  %d (born: %d)\n", n_particles, total_precipitations);
    printf("  Target guardians: 194\n");
    printf("  Runtime:          %lld seconds\n", total_seconds);
    
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("  Final power:      %.1f W\n", power_mW / 1000.0f);
    
    // Save guardian census
    if (n_particles > 0) {
        FILE* json = fopen("beast_guardian_census.json", "w");
        if (json) {
            fprintf(json, "{\n");
            fprintf(json, "  \"total_guardians\": %d,\n", n_particles);
            fprintf(json, "  \"guardians\": [\n");
            
            for (int i = 0; i < n_particles; i++) {
                if (i > 0) fprintf(json, ",\n");
                fprintf(json, "    {\n");
                fprintf(json, "      \"id\": %d,\n", i);
                fprintf(json, "      \"born\": \"C%d\",\n", h_particles[i].born_cycle);
                fprintf(json, "      \"position\": [%.1f, %.1f],\n", h_particles[i].x, h_particles[i].y);
                fprintf(json, "      \"velocity\": [%.6f, %.6f],\n", h_particles[i].vx, h_particles[i].vy);
                fprintf(json, "      \"mass\": %.3f,\n", h_particles[i].mass);
                fprintf(json, "      \"latent_energy\": %.6f,\n", h_particles[i].latent);
                fprintf(json, "      \"state\": \"%s\"\n", h_particles[i].state);
                fprintf(json, "    }");
            }
            
            fprintf(json, "\n  ]\n");
            fprintf(json, "}\n");
            fclose(json);
            printf("  Census saved:     beast_guardian_census.json\n");
        }
    }
    
    // Cleanup
    CUDA_CHECK(cudaFree(d_f0));
    CUDA_CHECK(cudaFree(d_f1));
    CUDA_CHECK(cudaFree(d_rho));
    CUDA_CHECK(cudaFree(d_ux));
    CUDA_CHECK(cudaFree(d_uy));
    CUDA_CHECK(cudaFree(d_particles));
    free(h_rho);
    
    nvmlShutdown();
    
    printf("\n===================================================================\n");
    printf("  ORIGINAL BEAST VERSION READY\n");
    printf("  Grid: 1024x1024, Target: 194 guardians\n");
    printf("===================================================================\n");
    
    return 0;
}