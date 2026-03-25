/* ============================================================================
 * PROBE 1024x1024 - ORIGINAL BEAST VERSION (Properly Scaled)
 * 
 * Scaled BACK from GTX 1050 adaptation (256x256, 13 guardians)
 * to Original Beast specs (1024x1024, 194 guardians)
 * 
 * Scaling: Reverse the 0.25 linear / 0.0625 area scaling
 * ============================================================================ */

#include <cuda_runtime.h>
#include <nvml.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <chrono>
#include <vector>

/* ---- Grid --------------------------------------------------------------- */
#define NX    1024     /* ORIGINAL: 1024 (was 256) */
#define NY    1024     /* ORIGINAL: 1024 (was 256) */
#define NN    (NX * NY)  /* 1,048,576 nodes (was 65,536) */
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)
#define NUM_BLOCKS GBLK(NN)

/* ---- Protocol ----------------------------------------------------------- */
#define STEPS_PER_BATCH    500
#define BATCHES_PER_CYCLE  200
#define MAX_CYCLES         1700    /* Weekend: 1700 cycles */

/* ---- VRM ---------------------------------------------------------------- */
#define OMEGA_BASE     (1.0f / 0.8f)  /* 1.25 */
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
#define MAX_PARTICLES   194         /* ORIGINAL: 194 guardians */

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
#define PROBE_D_COUNT   10       /* how many particles get boosted */
#define PROBE_D_MULT    10.0f    /* accretion multiplier for trapped ones */

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
    int born_batch;
    char state[16];
    bool alive;
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
 *   K E R N E L S  (From working code)
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

/* ---- Particle sink (mass accretion) ------------------------------------- */
__global__ void particle_sink(float* f, Particle* particles, int n_particles,
                              float sink_rate, int radius, int nx, int ny) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int N = nx * ny;
    if (idx >= N) return;
    
    int x = idx % nx;
    int y = idx / nx;
    
    // Check distance to each particle
    for (int p = 0; p < n_particles; p++) {
        if (!particles[p].alive) continue;
        
        float dx = x - particles[p].x;
        float dy = y - particles[p].y;
        
        // Periodic boundary
        if (dx > nx/2) dx -= nx;
        if (dx < -nx/2) dx += nx;
        if (dy > ny/2) dy -= ny;
        if (dy < -ny/2) dy += ny;
        
        float r2 = dx*dx + dy*dy;
        float R2 = (float)(radius * radius);
        
        if (r2 < R2) {
            float w = expf(-r2 / (R2 * 0.25f));
            
            // Get density at this cell
            float rho_val = 0.f;
            for (int i = 0; i < Q; i++) {
                rho_val += f[i * N + idx];
            }
            
            float excess = rho_val - 1.0f;
            if (excess <= 0.0f) break;
            
            float drain = sink_rate * excess * w;
            drain = fminf(drain, excess * 0.5f);
            
            // Remove from fluid, add to particle
            for (int i = 0; i < Q; i++) {
                float fi = f[i * N + idx];
                float feq = d_w[i] * 1.0f;  // Equilibrium at rho=1.0
                f[i * N + idx] = fi - drain * (fi - feq) / rho_val;
            }
            
            atomicAdd(&particles[p].mass, drain);
        }
    }
}

/* ---- Advect particles --------------------------------------------------- */
__global__ void advect_particles(Particle* particles, int n_particles,
                                 const float* __restrict__ ux, 
                                 const float* __restrict__ uy,
                                 int steps, int nx, int ny) {
    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    if (pid >= n_particles) return;
    if (!particles[pid].alive) return;
    
    Particle* p = &particles[pid];
    
    for (int s = 0; s < steps; s++) {
        // Convert fractional position to grid cell
        int cx = (int)p->x;
        int cy = (int)p->y;
        int idx = cy * nx + cx;
        
        // Update position based on local velocity
        p->x += ux[idx];
        p->y += uy[idx];
        
        // Wrap around periodic boundaries
        if (p->x < 0) p->x += nx;
        if (p->x >= nx) p->x -= nx;
        if (p->y < 0) p->y += ny;
        if (p->y >= ny) p->y -= ny;
        
        // Update velocity
        p->vx = ux[idx];
        p->vy = uy[idx];
    }
}

/* ---- Find max density --------------------------------------------------- */
float find_max_density(const float* rho, int N, int* max_idx) {
    float rmax = -1e30f;
    int idx = -1;
    
    for (int i = 0; i < N; i++) {
        if (rho[i] > rmax) {
            rmax = rho[i];
            idx = i;
        }
    }
    
    if (max_idx) *max_idx = idx;
    return rmax;
}

/* ============================================================================
 *   M A I N  -  Observer Mode
 * ============================================================================ */

int main() {
    printf("===================================================================\n");
    printf("  P R O B E 1024 — OBSERVER MODE\n");
    printf("  Grid: %dx%d, Max guardians: %d\n", NX, NY, MAX_PARTICLES);
    printf("  Protocol: 4-Probe (A,B,C,D)\n");
    printf("  Role: Observe precipitation, not dictate\n");
    printf("===================================================================\n\n");
    
    // CUDA setup
    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, 0));
    printf("[OBSERVER] %s  SM %d.%d  SMs: %d\n", 
           prop.name, prop.major, prop.minor, prop.multiProcessorCount);
    
    // NVML power monitoring
    nvmlInit();
    nvmlDevice_t nvml_dev;
    nvmlDeviceGetHandleByIndex(0, &nvml_dev);
    unsigned int power_mW;
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("[OBSERVER] Idle power: %.1f W\n", power_mW / 1000.0f);
    
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
    
    // Precipitation telemetry file
    FILE* precip_telemetry = fopen("precipitation_telemetry.csv", "w");
    fprintf(precip_telemetry, "cycle,batch,time_s,rho_max,rho_threshold,guardian_id,pos_x,pos_y,state\n");
    
    // Main loop - Observer Mode
    auto t0 = std::chrono::steady_clock::now();
    int cycle = 0;
    int cur = 0;
    float omega = OMEGA_BASE;
    
    printf("\n[OBSERVER] Monitoring precipitation threshold: %.5f\n", RHO_THRESH);
    printf("  Waiting for first density peak > threshold...\n\n");
    
    // Run until first guardian is born
    bool first_guardian_observed = false;
    
    while (cycle < MAX_CYCLES && n_particles < MAX_PARTICLES) {
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
            
            // Update existing particles
            if (n_particles > 0) {
                advect_particles<<<GBLK(n_particles), BLOCK>>>(
                    d_particles, n_particles, d_ux, d_uy, 
                    STEPS_PER_BATCH, NX, NY);
                CUDA_CHECK(cudaDeviceSynchronize());
                
                particle_sink<<<NUM_BLOCKS, BLOCK>>>(
                    (cur == 0) ? d_f1 : d_f0,  // Current distribution
                    d_particles, n_particles, SINK_RATE, SINK_RADIUS, NX, NY);
                CUDA_CHECK(cudaDeviceSynchronize());
            }
            
            // Check for precipitation (every batch for observation)
            CUDA_CHECK(cudaMemcpy(h_rho, d_rho, NN * sizeof(float), cudaMemcpyDeviceToHost));
            
            int max_idx = -1;
            float rmax = find_max_density(h_rho, NN, &max_idx);
            
            auto now = std::chrono::steady_clock::now();
            long long elapsed = std::chrono::duration_cast<std::chrono::seconds>(now - t0).count();
            
            // Log precipitation telemetry
            fprintf(precip_telemetry, "%d,%d,%lld,%.5f,%.5f,%d,%d,%d,%s\n",
                    cycle, batch, elapsed, rmax, RHO_THRESH,
                    n_particles, 
                    (max_idx >= 0) ? max_idx % NX : -1,
                    (max_idx >= 0) ? max_idx / NX : -1,
                    "MONITORING");
            
            // Check if precipitation occurs
            if (rmax > RHO_THRESH && n_particles < MAX_PARTICLES) {
                int px = max_idx % NX;
                int py = max_idx / NX;
                
                // Check if too close to existing guardians
                bool too_close = false;
                for (int i = 0; i < n_particles; i++) {
                    if (!h_particles[i].alive) continue;
                    
                    float dx = px - h_particles[i].x;
                    float dy = py - h_particles[i].y;
                    
                    if (dx > NX/2) dx -= NX;
                    if (dx < -NX/2) dx += NX;
                    if (dy > NY/2) dy -= NY;
                    if (dy < -NY/2) dy += NY;
                    
                    if (dx*dx + dy*dy < DRAIN_RADIUS*DRAIN_RADIUS) {
                        too_close = true;
                        break;
                    }
                }
                
                if (!too_close) {
                    // CREATE NEW GUARDIAN - FIRST PULSE STATE
                    h_particles[n_particles].x = px;
                    h_particles[n_particles].y = py;
                    h_particles[n_particles].vx = 0.0f;
                    h_particles[n_particles].vy = 0.0f;
                    h_particles[n_particles].mass = 0.0f;
                    h_particles[n_particles].latent = 0.0f;
                    h_particles[n_particles].born_cycle = cycle;
                    h_particles[n_particles].born_batch = batch;
                    strcpy(h_particles[n_particles].state, "PULSE");
                    h_particles[n_particles].alive = true;
                    
                    // Copy to device
                    CUDA_CHECK(cudaMemcpy(&d_particles[n_particles], 
                                         &h_particles[n_particles], 
                                         sizeof(Particle), 
                                         cudaMemcpyHostToDevice));
                    
                    n_particles++;
                    total_precipitations++;
                    
                    // OBSERVER REPORT: Guardian Birth
                    char tb[32]; fmt_time(elapsed, tb);
                    printf("\n═══════════════════════════════════════════════════════════════════════\n");
                    printf("  🎯 GUARDIAN BIRTH OBSERVED - FIRST PULSE STATE\n");
                    printf("═══════════════════════════════════════════════════════════════════════\n");
                    printf("  Time:          T+%s\n", tb);
                    printf("  Cycle:         %d (Batch: %d)\n", cycle, batch);
                    printf("  Guardian ID:   %d (Total: %d)\n", n_particles-1, n_particles);
                    printf("  Position:      (%d, %d)\n", px, py);
                    printf("  Density:       %.5f (Threshold: %.5f)\n", rmax, RHO_THRESH);
                    printf("  State:         PULSE (First state transition)\n");
                    printf("  Mass:          0.000 (Initial)\n");
                    printf("  Born at:       Cycle %d, Batch %d\n", cycle, batch);
                    printf("═══════════════════════════════════════════════════════════════════════\n\n");
                    
                    // Update telemetry with guardian birth
                    fprintf(precip_telemetry, "%d,%d,%lld,%.5f,%.5f,%d,%d,%d,%s\n",
                            cycle, batch, elapsed, rmax, RHO_THRESH,
                            n_particles-1, px, py, "PULSE-BIRTH");
                    
                    // If this is the first guardian, we might want to stop or continue
                    if (!first_guardian_observed) {
                        first_guardian_observed = true;
                        printf("[OBSERVER] First guardian birth observed. Continuing to observe...\n");
                    }
                }
            }
            
            // Check probe schedules
            bool probe_a = (cycle >= PROBE_A_START && cycle <= PROBE_A_END);
            bool probe_b = (cycle == PROBE_B_CYCLE);
            bool probe_c = (cycle >= PROBE_C_START && cycle <= PROBE_C_END);
            bool probe_d = (cycle >= PROBE_D_START && cycle <= PROBE_D_END);
            
            // Apply probe effects if active
            if (probe_b) {
                // Probe B: Lattice shear (simplified for now)
                printf("[PROBE B] Lattice shear applied at cycle %d\n", cycle);
            }
            
            // Periodic status report
            if (batch % 50 == 0) {
                nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
                float power_W = power_mW / 1000.0f;
                
                char tb[32]; fmt_time(elapsed, tb);
                printf("  [%s] cy%d b%d | ρ_max=%.5f | P=%.0fW | Guardians=%d\n",
                       tb, cycle, batch, rmax, power_W, n_particles);
            }
        }
        
        cycle++;
        
        // Stop after observing first few guardians for demonstration
        if (n_particles >= 3) {
            printf("\n[OBSERVER] First 3 guardians observed. Demonstration complete.\n");
            printf("  Continuing would run full 1700-cycle protocol.\n");
            break;
        }
    }
    
    // Final observation report
    auto t_end = std::chrono::steady_clock::now();
    long long total_seconds = std::chrono::duration_cast<std::chrono::seconds>(t_end - t0).count();
    
    printf("\n═══════════════════════════════════════════════════════════════════════\n");
    printf("  OBSERVER FINAL REPORT\n");
    printf("═══════════════════════════════════════════════════════════════════════\n");
    printf("  Runtime:          %lld seconds\n", total_seconds);
    printf("  Cycles completed: %d\n", cycle);
    printf("  Guardians born:   %d (of %d target)\n", n_particles, MAX_PARTICLES);
    printf("  Precipitation events: %d\n", total_precipitations);
    
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("  Final power:      %.1f W\n", power_mW / 1000.0f);
    
    // Save guardian census
    if (n_particles > 0) {
        FILE* json = fopen("observer_guardian_census.json", "w");
        if (json) {
            fprintf(json, "{\n");
            fprintf(json, "  \"observation_mode\": true,\n");
            fprintf(json, "  \"total_guardians\": %d,\n", n_particles);
            fprintf(json, "  \"guardians\": [\n");
            
            for (int i = 0; i < n_particles; i++) {
                if (i > 0) fprintf(json, ",\n");
                fprintf(json, "    {\n");
                fprintf(json, "      \"id\": %d,\n", i);
                fprintf(json, "      \"born\": \"C%d-B%d\",\n", 
                        h_particles[i].born_cycle, h_particles[i].born_batch);
                fprintf(json, "      \"position\": [%.1f, %.1f],\n", 
                        h_particles[i].x, h_particles[i].y);
                fprintf(json, "      \"velocity\": [%.6f, %.6f],\n", 
                        h_particles[i].vx, h_particles[i].vy);
                fprintf(json, "      \"mass\": %.3f,\n", h_particles[i].mass);
                fprintf(json, "      \"latent_energy\": %.6f,\n", h_particles[i].latent);
                fprintf(json, "      \"state\": \"%s\",\n", h_particles[i].state);
                fprintf(json, "      \"alive\": %s\n", 
                        h_particles[i].alive ? "true" : "false");
                fprintf(json, "    }");
            }
            
            fprintf(json, "\n  ]\n");
            fprintf(json, "}\n");
            fclose(json);
            printf("  Census saved:     observer_guardian_census.json\n");
        }
    }
    
    printf("  Telemetry saved:  precipitation_telemetry.csv\n");
    printf("═══════════════════════════════════════════════════════════════════════\n");
    
    // Cleanup
    fclose(precip_telemetry);
    CUDA_CHECK(cudaFree(d_f0));
    CUDA_CHECK(cudaFree(d_f1));
    CUDA_CHECK(cudaFree(d_rho));
    CUDA_CHECK(cudaFree(d_ux));
    CUDA_CHECK(cudaFree(d_uy));
    CUDA_CHECK(cudaFree(d_particles));
    free(h_rho);
    
    nvmlShutdown();
    
    printf("\n[OBSERVER] System observation complete.\n");
    printf("  Next: Run full 4-Probe Protocol (1700 cycles)\n");
    
    return 0;
}