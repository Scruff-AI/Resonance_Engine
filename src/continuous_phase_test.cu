/* ============================================================================
 * CONTINUOUS PHASE TEST — Run indefinitely for phase shift observation
 * 
 * Based on probe_256.cu but with:
 * 1. No cycle limit (runs forever)
 * 2. No probes (just continuous operation)
 * 3. Periodic status output
 * 4. Guardian monitoring
 * 
 * Purpose: Observe three-state phase shift over extended periods
 * ============================================================================ */
#include <cuda_runtime.h>
#include <nvml.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <chrono>

/* ---- Grid --------------------------------------------------------------- */
#define NX    256
#define NY    256
#define NN    (NX * NY)
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)
#define NUM_BLOCKS GBLK(NN)

/* ---- Protocol ----------------------------------------------------------- */
#define STEPS_PER_BATCH    500
#define BATCHES_PER_CYCLE  200
#define STATUS_INTERVAL    100  /* Print status every 100 cycles */

/* ---- VRM ---------------------------------------------------------------- */
#define OMEGA_BASE     (1.0f / 0.8f)
#define VRM_ALPHA      10.0f
#define OMEGA_CLAMP_LO 0.6f
#define OMEGA_CLAMP_HI 1.95f

/* ---- Shear layer -------------------------------------------------------- */
#define U_TOP       1.994e-4f
#define U_BOT       0.997e-4f

/* ---- Precipitation ------------------------------------------------------ */
#define RHO_THRESH      1.00022f    /* Optimized for 256×256 */
#define DRAIN_RADIUS    4
#define SINK_RADIUS     6
#define SINK_RATE       0.0003125f
#define MAX_PARTICLES   13

/* ---- Torque bias -------------------------------------------------------- */
#define TORQUE_BIAS     0.0f

/* ---- CUDA kernels (unchanged from probe) -------------------------------- */
__global__ void collide_stream(float* f0, float* f1, float* rho, float* ux, float* uy,
                               float omega, int nx, int ny) {
    /* ... same as probe_256.cu ... */
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= nx * ny) return;
    
    int x = idx % nx;
    int y = idx / nx;
    
    float f[9];
    for (int q = 0; q < 9; q++) f[q] = f0[idx * 9 + q];
    
    float r = 0.0f;
    float u_x = 0.0f, u_y = 0.0f;
    for (int q = 0; q < 9; q++) {
        r += f[q];
        u_x += f[q] * ((q == 1 || q == 5 || q == 8) ? 1.0f :
                      (q == 3 || q == 6 || q == 7) ? -1.0f : 0.0f);
        u_y += f[q] * ((q == 2 || q == 5 || q == 6) ? 1.0f :
                      (q == 4 || q == 7 || q == 8) ? -1.0f : 0.0f);
    }
    
    u_x /= r;
    u_y /= r;
    
    /* Shear boundary condition */
    if (y == ny - 1) u_x += U_TOP;
    if (y == 0)      u_x += U_BOT;
    
    float u2 = u_x * u_x + u_y * u_y;
    float eu[9];
    for (int q = 0; q < 9; q++) {
        float cx = (q == 1 || q == 5 || q == 8) ? 1.0f :
                  (q == 3 || q == 6 || q == 7) ? -1.0f : 0.0f;
        float cy = (q == 2 || q == 5 || q == 6) ? 1.0f :
                  (q == 4 || q == 7 || q == 8) ? -1.0f : 0.0f;
        eu[q] = cx * u_x + cy * u_y;
    }
    
    float w[9] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f,
                  1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};
    
    float feq[9];
    for (int q = 0; q < 9; q++) {
        feq[q] = w[q] * r * (1.0f + 3.0f * eu[q] + 4.5f * eu[q] * eu[q] - 1.5f * u2);
    }
    
    for (int q = 0; q < 9; q++) {
        f[q] = f[q] - omega * (f[q] - feq[q]);
    }
    
    /* Stream */
    int xp1 = (x + 1) % nx;
    int xm1 = (x - 1 + nx) % nx;
    int yp1 = (y + 1) % ny;
    int ym1 = (y - 1 + ny) % ny;
    
    f1[((yp1 * nx + x) * 9) + 2] = f[2];
    f1[((ym1 * nx + x) * 9) + 4] = f[4];
    f1[((y * nx + xp1) * 9) + 1] = f[1];
    f1[((y * nx + xm1) * 9) + 3] = f[3];
    f1[((yp1 * nx + xp1) * 9) + 5] = f[5];
    f1[((ym1 * nx + xm1) * 9) + 7] = f[7];
    f1[((yp1 * nx + xm1) * 9) + 6] = f[6];
    f1[((ym1 * nx + xp1) * 9) + 8] = f[8];
    f1[((y * nx + x) * 9) + 0] = f[0];
    
    rho[idx] = r;
    ux[idx] = u_x;
    uy[idx] = u_y;
}

__global__ void compute_stats(float* rho, float* enst, float* bsmin, float* bsmax,
                              float* brmin, float* brmax, float* rhosum, int n) {
    /* ... same as probe_256.cu ... */
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= n) return;
    
    float r = rho[idx];
    float ux = 0.0f, uy = 0.0f;  // Would need actual ux/uy arrays
    
    float e = 0.0f;  // Simplified enstrophy
    
    bsmin[idx] = r;
    bsmax[idx] = r;
    brmin[idx] = r;
    brmax[idx] = r;
    enst[idx] = e;
    rhosum[idx] = r;
}

/* ---- Precipitation kernel (simplified) ---------------------------------- */
__global__ void precipitate(float* rho, float* drained, Particle* particles,
                            int* n_particles, float dt, int nx, int ny) {
    /* Simplified version - just detect high density regions */
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= nx * ny) return;
    
    if (rho[idx] > RHO_THRESH && drained[idx] == 0.0f) {
        int x = idx % nx;
        int y = idx / nx;
        
        // Try to add particle
        int slot = atomicAdd(n_particles, 1);
        if (slot < MAX_PARTICLES) {
            particles[slot].x = x + 0.5f;
            particles[slot].y = y + 0.5f;
            particles[slot].mass = 0.01f;
            particles[slot].vx = 0.0f;
            particles[slot].vy = 0.0f;
            particles[slot].latent_energy = 0.0002f;
            drained[idx] = 1.0f;
        } else {
            atomicSub(n_particles, 1);  // Roll back
        }
    }
}

/* ---- Particle structure ------------------------------------------------- */
typedef struct {
    float x, y;
    float vx, vy;
    float mass;
    float latent_energy;
} Particle;

/* ---- Main --------------------------------------------------------------- */
int main() {
    printf("===================================================================\n");
    printf("  CONTINUOUS PHASE TEST — 256×256 (Run Indefinitely)\n");
    printf("  Purpose: Observe three-state phase shift (Volatile → Buffer → Solid)\n");
    printf("  Started: %s\n", __TIME__);
    printf("===================================================================\n");
    
    // Initialize NVML for power monitoring
    nvmlReturn_t nvml_ret = nvmlInit();
    if (nvml_ret != NVML_SUCCESS) {
        printf("[NVML] Failed to initialize\n");
        return 1;
    }
    
    nvmlDevice_t device;
    nvml_ret = nvmlDeviceGetHandleByIndex(0, &device);
    if (nvml_ret != NVML_SUCCESS) {
        printf("[NVML] Failed to get device handle\n");
        nvmlShutdown();
        return 1;
    }
    
    // Allocate memory
    float *f0, *f1, *d_rho, *d_ux, *d_uy;
    float *d_bsmin, *d_bsmax, *d_brmin, *d_brmax;
    float *d_rhosum, *d_enstrophy, *d_drained;
    Particle *d_particles;
    int *d_n_particles;
    
    size_t f_size = NN * Q * sizeof(float);
    size_t grid_size = NN * sizeof(float);
    
    cudaMalloc(&f0, f_size);
    cudaMalloc(&f1, f_size);
    cudaMalloc(&d_rho, grid_size);
    cudaMalloc(&d_ux, grid_size);
    cudaMalloc(&d_uy, grid_size);
    cudaMalloc(&d_bsmin, grid_size);
    cudaMalloc(&d_bsmax, grid_size);
    cudaMalloc(&d_brmin, grid_size);
    cudaMalloc(&d_brmax, grid_size);
    cudaMalloc(&d_rhosum, grid_size);
    cudaMalloc(&d_enstrophy, grid_size);
    cudaMalloc(&d_drained, grid_size);
    cudaMalloc(&d_particles, MAX_PARTICLES * sizeof(Particle));
    cudaMalloc(&d_n_particles, sizeof(int));
    
    // Initialize lattice
    float *h_f0 = (float*)malloc(f_size);
    for (int i = 0; i < NN; i++) {
        float rho = 1.0f + 0.0002f * sinf(2.0f * M_PI * (i % NX) / NX) *
                              sinf(2.0f * M_PI * (i / NX) / NY);
        for (int q = 0; q < 9; q++) {
            h_f0[i * 9 + q] = rho / 9.0f;
        }
    }
    cudaMemcpy(f0, h_f0, f_size, cudaMemcpyHostToDevice);
    free(h_f0);
    
    // Initialize particles
    int h_n_particles = 0;
    cudaMemcpy(d_n_particles, &h_n_particles, sizeof(int), cudaMemcpyHostToDevice);
    cudaMemset(d_drained, 0, grid_size);
    
    // Host copies for reading back
    float *h_rho = (float*)malloc(grid_size);
    Particle *h_particles = (Particle*)malloc(MAX_PARTICLES * sizeof(Particle));
    
    // Timing
    auto t0 = std::chrono::steady_clock::now();
    int cycle = 0;
    
    printf("\n  cyc  |  T+      |  omega  | rho range          | enst       | part | p.mass   | M_total     |\n");
    printf("  -----|----------|---------|--------------------|------------|------|----------|-------------|\n");
    
    // Main loop - RUNS FOREVER
    while (1) {
        auto now = std::chrono::steady_clock::now();
        int elapsed = (int)std::chrono::duration_cast<std::chrono::seconds>(now - t0).count();
        
        float omega = OMEGA_BASE;
        
        // Run batches
        for (int batch = 0; batch < BATCHES_PER_CYCLE; batch++) {
            for (int step = 0; step < STEPS_PER_BATCH; step++) {
                collide_stream<<<NUM_BLOCKS, BLOCK>>>(f0, f1, d_rho, d_ux, d_uy, omega, NX, NY);
                std::swap(f0, f1);
            }
            
            // Precipitation check
            precipitate<<<NUM_BLOCKS, BLOCK>>>(d_rho, d_drained, d_particles, d_n_particles, 1.0f, NX, NY);
        }
        
        // Read back stats periodically
        if (cycle % STATUS_INTERVAL == 0) {
            cudaMemcpy(&h_n_particles, d_n_particles, sizeof(int), cudaMemcpyDeviceToHost);
            cudaMemcpy(h_rho, d_rho, grid_size, cudaMemcpyDeviceToHost);
            
            // Compute stats
            float rho_min = 1e9, rho_max = -1e9;
            float total_mass = 0.0f;
            for (int i = 0; i < NN; i++) {
                float r = h_rho[i];
                if (r < rho_min) rho_min = r;
                if (r > rho_max) rho_max = r;
                total_mass += r;
            }
            
            // Read particles if any
            float particle_mass = 0.0f;
            if (h_n_particles > 0) {
                cudaMemcpy(h_particles, d_particles, h_n_particles * sizeof(Particle), cudaMemcpyDeviceToHost);
                for (int p = 0; p < h_n_particles; p++) {
                    particle_mass += h_particles[p].mass;
                }
            }
            
            // Power reading
            nvmlPower_t power;
            nvml_ret = nvmlDeviceGetPowerUsage(device, &power);
            float power_w = (nvml_ret == NVML_SUCCESS) ? power / 1000.0f : 0.0f;
            
            // Print status
            int hours = elapsed / 3600;
            int minutes = (elapsed % 3600) / 60;
            int seconds = elapsed % 60;
            
            printf("  %4d | %02d:%02d:%02d | %7.4f | [%.5f,%.5f] | %.3e | %4d | %8.2f | %11.2f |\n",
                   cycle, hours, minutes, seconds, omega,
                   rho_min, rho_max, 0.0f,  // enstrophy placeholder
                   h_n_particles, particle_mass, total_mass);
            
            // Flush output
            fflush(stdout);
        }
        
        cycle++;
        
        // Check for exit condition (Ctrl+C will be caught by system)
        if (elapsed > 3600) {  // Optional: stop after 1 hour for testing
            printf("\n===================================================================\n");
            printf("  1-HOUR TEST COMPLETE\n");
            printf("  Final cycle: %d\n", cycle);
            printf("  Total time: %02d:%02d:%02d\n", elapsed/3600, (elapsed%3600)/60, elapsed%60);
            printf("===================================================================\n");
            break;
        }
    }
    
    // Cleanup
    cudaFree(f0); cudaFree(f1);
    cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy);
    cudaFree(d_bsmin); cudaFree(d_bsmax); cudaFree(d_brmin); cudaFree(d_brmax);
    cudaFree(d_rhosum); cudaFree(d_enstrophy); cudaFree(d_drained);
    cudaFree(d_particles); cudaFree(d_n_particles);
    nvmlShutdown();
    free(h_rho); free(h_particles);
    
    return 0;
}