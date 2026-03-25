/* ============================================================================
 * SEED BRAIN SIMPLE - Core Algorithm Only
 * Based on Seed Brain v0.3 but without Linux dependencies
 * ============================================================================ */

#include <cuda_runtime.h>
#include <nvml.h>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cmath>
#include <chrono>
#include <vector>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* ---------- GTX 1050 Parameters (from seed_brain.h) ---------------------- */
#define SB_NX 512
#define SB_NY 512
#define SB_N  (SB_NX * SB_NY)  /* 262,144 nodes */
#define SB_Q  9

/* GTX 1050 ADAPTATION parameters */
#define SB_TAU          0.7273f    /* LBM relaxation time */
#define SB_OMEGA        (1.0f / SB_TAU)  /* 1.375 */
#define SB_TDP          75.0f      /* GTX 1050 TDP */
#define SB_P_IDLE       10.0f      /* GTX 1050 idle power */

/* Dual-Resonance Model */
#define SB_F_METABOLIC      0.005f  /* Carrier freq (Hz) */
#define SB_F_COGNITIVE      0.06f   /* Harmonic freq (Hz) */
#define SB_METABOLIC_PERIOD 200.0f  /* 1/0.005 = 200 seconds */
#define SB_COGNITIVE_PERIOD (1.0f / SB_F_COGNITIVE)  /* 16.67 seconds */

/* ---------- D2Q9 --------------------------------------------------------- */
__constant__ int   d_ex[SB_Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
__constant__ int   d_ey[SB_Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
__constant__ float d_w[SB_Q]  = { 4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9,
                                  1.f/36,1.f/36,1.f/36,1.f/36 };

#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

/* ---------- Guardian Structure ------------------------------------------- */
typedef struct {
    int id;
    float position[2];
    float velocity[2];
    float mass;
    float latent_energy;
    const char* born;  // e.g., "C11"
    const char* state; // e.g., "PULSE"
} Guardian;

#define MAX_GUARDIANS 200
Guardian guardians[MAX_GUARDIANS];
int n_guardians = 0;

/* ---------- LBM Kernel --------------------------------------------------- */
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

    float fl[SB_Q];
    for (int i = 0; i < SB_Q; i++) {
        int sx = (x - d_ex[i] + nx) % nx;
        int sy = (y - d_ey[i] + ny) % ny;
        fl[i] = f_src[i * N + sy * nx + sx];
    }

    float rho_val = 0.f, ux_val = 0.f, uy_val = 0.f;
    for (int i = 0; i < SB_Q; i++) {
        rho_val += fl[i];
        ux_val += (float)d_ex[i] * fl[i];
        uy_val += (float)d_ey[i] * fl[i];
    }
    float inv = 1.f / fmaxf(rho_val, 1e-10f);
    ux_val *= inv; uy_val *= inv;
    rho[idx] = rho_val; ux[idx] = ux_val; uy[idx] = uy_val;

    const float u2 = ux_val * ux_val + uy_val * uy_val;
    for (int i = 0; i < SB_Q; i++) {
        float eu = (float)d_ex[i] * ux_val + (float)d_ey[i] * uy_val;
        float feq = d_w[i] * rho_val * (1.f + 3.f*eu + 4.5f*eu*eu - 1.5f*u2);
        f_dst[i * N + idx] = fl[i] - omega * (fl[i] - feq);
    }
}

/* ---------- Finite Difference Vorticity ---------------------------------- */
__device__ float calculate_vorticity(int x, int y, int nx, int ny, 
                                     float* v_x, float* v_y) {
    if (x <= 0 || x >= nx - 1 || y <= 0 || y >= ny - 1) return 0.0f;
    float dvy_dx = (v_y[y * nx + (x + 1)] - v_y[y * nx + (x - 1)]) * 0.5f;
    float dvx_dy = (v_x[(y + 1) * nx + x] - v_x[(y - 1) * nx + x]) * 0.5f;
    return dvy_dx - dvx_dy; 
}

__global__ void compute_vorticity_map(float* ux, float* uy, float* vorticity,
                                      int nx, int ny) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N = nx * ny;
    if (idx >= N) return;
    
    const int x = idx % nx;
    const int y = idx / nx;
    
    vorticity[idx] = calculate_vorticity(x, y, nx, ny, ux, uy);
}

/* ---------- Guardian Detection ------------------------------------------- */
void detect_guardians(const float* vorticity, const float* ux, const float* uy,
                      const float* rho, uint64_t current_step, 
                      int cognitive_cycle) {
    // Simple detection: local maxima of vorticity with mass accumulation
    static uint64_t last_detection = 0;
    if (current_step - last_detection < 10000) return; // Every 10k steps
    last_detection = current_step;
    
    // Threshold from weekend experiments (calibrated)
    float vorticity_threshold = 0.0001f;
    float mass_threshold = 1000.0f;
    
    for (int y = 1; y < SB_NY - 1; y++) {
        for (int x = 1; x < SB_NX - 1; x++) {
            int idx = y * SB_NX + x;
            float w = fabsf(vorticity[idx]);
            
            // Check if local maximum and above threshold
            if (w > vorticity_threshold &&
                w > fabsf(vorticity[idx - 1]) &&
                w > fabsf(vorticity[idx + 1]) &&
                w > fabsf(vorticity[idx - SB_NX]) &&
                w > fabsf(vorticity[idx + SB_NX])) {
                
                // Check if already tracked
                bool existing = false;
                for (int g = 0; g < n_guardians; g++) {
                    float dx = guardians[g].position[0] - x;
                    float dy = guardians[g].position[1] - y;
                    if (dx*dx + dy*dy < 25.0f) { // Within 5 cells
                        existing = true;
                        // Update existing guardian
                        guardians[g].position[0] = x;
                        guardians[g].position[1] = y;
                        guardians[g].velocity[0] = ux[idx];
                        guardians[g].velocity[1] = uy[idx];
                        guardians[g].mass += rho[idx] - 1.0f;
                        guardians[g].latent_energy += w;
                        break;
                    }
                }
                
                // Create new guardian
                if (!existing && n_guardians < MAX_GUARDIANS) {
                    guardians[n_guardians].id = n_guardians;
                    guardians[n_guardians].position[0] = x;
                    guardians[n_guardians].position[1] = y;
                    guardians[n_guardians].velocity[0] = ux[idx];
                    guardians[n_guardians].velocity[1] = uy[idx];
                    guardians[n_guardians].mass = rho[idx] - 1.0f;
                    guardians[n_guardians].latent_energy = w;
                    
                    // Format: "C11", "C12", etc.
                    char* born_str = (char*)malloc(8);
                    snprintf(born_str, 8, "C%d", cognitive_cycle);
                    guardians[n_guardians].born = born_str;
                    
                    guardians[n_guardians].state = "PULSE";
                    n_guardians++;
                }
            }
        }
    }
}

/* ---------- Save Guardian Census ----------------------------------------- */
void save_guardian_census(uint64_t current_step) {
    FILE* json = fopen("guardian_census_simple.json", "w");
    if (!json) return;
    
    fprintf(json, "{\n");
    fprintf(json, "  \"total_guardians\": %d,\n", n_guardians);
    fprintf(json, "  \"guardians\": [\n");
    
    for (int g = 0; g < n_guardians; g++) {
        if (g > 0) fprintf(json, ",\n");
        
        fprintf(json, "    {\n");
        fprintf(json, "      \"id\": %d,\n", guardians[g].id);
        fprintf(json, "      \"born\": \"%s\",\n", guardians[g].born);
        fprintf(json, "      \"position\": [%.1f, %.1f],\n", 
                guardians[g].position[0], guardians[g].position[1]);
        fprintf(json, "      \"velocity\": [%.6f, %.6f],\n",
                guardians[g].velocity[0], guardians[g].velocity[1]);
        fprintf(json, "      \"mass\": %.3f,\n", guardians[g].mass);
        fprintf(json, "      \"latent_energy\": %.6f,\n", 
                guardians[g].latent_energy);
        fprintf(json, "      \"state\": \"%s\"\n", guardians[g].state);
        fprintf(json, "    }");
    }
    
    fprintf(json, "\n  ]\n");
    fprintf(json, "}\n");
    fclose(json);
}

/* ======================================================================== */
/*   M A I N                                                                */
/* ======================================================================== */

int main() {
    printf("=======================================================================\n");
    printf("  SEED BRAIN SIMPLE - Core Algorithm\n");
    printf("  Based on Seed Brain v0.3 (GTX 1050 adaptation)\n");
    printf("  Grid: %dx%d, tau: %.4f, omega: %.3f\n", 
           SB_NX, SB_NY, SB_TAU, SB_OMEGA);
    printf("=======================================================================\n\n");
    
    // CUDA setup
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    printf("[CUDA] %s  SM %d.%d\n", prop.name, prop.major, prop.minor);
    
    // NVML power monitoring
    nvmlInit();
    nvmlDevice_t nvml_dev;
    nvmlDeviceGetHandleByIndex(0, &nvml_dev);
    unsigned int power_mW;
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("[NVML] Idle power: %.1f W (GTX 1050: %.1f W)\n", 
           power_mW / 1000.0f, SB_P_IDLE);
    
    // Allocate memory
    float *f0, *f1, *rho, *ux, *uy, *vorticity;
    float *h_ux, *h_uy, *h_vorticity, *h_rho;
    
    cudaMalloc(&f0, SB_Q * SB_N * sizeof(float));
    cudaMalloc(&f1, SB_Q * SB_N * sizeof(float));
    cudaMalloc(&rho, SB_N * sizeof(float));
    cudaMalloc(&ux, SB_N * sizeof(float));
    cudaMalloc(&uy, SB_N * sizeof(float));
    cudaMalloc(&vorticity, SB_N * sizeof(float));
    
    h_ux = (float*)malloc(SB_N * sizeof(float));
    h_uy = (float*)malloc(SB_N * sizeof(float));
    h_vorticity = (float*)malloc(SB_N * sizeof(float));
    h_rho = (float*)malloc(SB_N * sizeof(float));
    
    // Initialize distribution (equilibrium + small noise)
    float* h_f0 = (float*)malloc(SB_Q * SB_N * sizeof(float));
    for (int i = 0; i < SB_Q * SB_N; i++) {
        h_f0[i] = 1.0f + 0.01f * (rand() / (float)RAND_MAX - 0.5f);
    }
    cudaMemcpy(f0, h_f0, SB_Q * SB_N * sizeof(float), cudaMemcpyHostToDevice);
    free(h_f0);
    
    // Prepare telemetry
    FILE* telemetry = fopen("seed_brain_telemetry.csv", "w");
    fprintf(telemetry, "step,cognitive_cycle,power_w,steps_per_sec,n_guardians,total_mass\n");
    
    auto t0 = std::chrono::steady_clock::now();
    uint64_t total_steps = 0;
    int cur = 0;
    int cognitive_cycle = 0;
    
    printf("\n[EXPERIMENT] Running Seed Brain simple...\n");
    printf("  Steps   | Cycle | Power | Steps/sec | Guardians | Total Mass\n");
    printf("  --------|-------|-------|-----------|-----------|------------\n");
    
    // Target: Run for ~1 metabolic cycle (200s) = 12 cognitive cycles
    int target_cognitive_cycles = 12;
    int steps_per_cognitive_cycle = (int)(SB_COGNITIVE_PERIOD * 5500); // ~5.5k steps/sec
    
    for (int cycle = 0; cycle < target_cognitive_cycles; cycle++) {
        cognitive_cycle = cycle + 1; // C1, C2, ..., C12
        
        // Run one cognitive cycle
        for (int step = 0; step < steps_per_cognitive_cycle; step += 500) {
            // Run 500 LBM steps
            for (int s = 0; s < 500; s++) {
                lbm_collide_stream<<<GBLK(SB_N), BLOCK>>>(
                    (cur == 0) ? f0 : f1,
                    (cur == 0) ? f1 : f0,
                    rho, ux, uy, SB_OMEGA, SB_NX, SB_NY);
                cudaDeviceSynchronize();
                cur = 1 - cur;
            }
            total_steps += 500;
            
            // Compute vorticity and detect guardians every 10k steps
            if (total_steps % 10000 == 0) {
                compute_vorticity_map<<<GBLK(SB_N), BLOCK>>>(ux, uy, vorticity, SB_NX, SB_NY);
                cudaDeviceSynchronize();
                
                // Copy to host
                cudaMemcpy(h_ux, ux, SB_N * sizeof(float), cudaMemcpyDeviceToHost);
                cudaMemcpy(h_uy, uy, SB_N * sizeof(float), cudaMemcpyDeviceToHost);
                cudaMemcpy(h_vorticity, vorticity, SB_N * sizeof(float), cudaMemcpyDeviceToHost);
                cudaMemcpy(h_rho, rho, SB_N * sizeof(float), cudaMemcpyDeviceToHost);
                
                detect_guardians(h_vorticity, h_ux, h_uy, h_rho, total_steps, cognitive_cycle);
            }
        }
        
        // Report at end of each cognitive cycle
        nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
        float power_W = power_mW / 1000.0f;
        
        auto t_now = std::chrono::steady_clock::now();
        double elapsed = std::chrono::duration<double>(t_now - t0).count();
        float steps_per_sec = total_steps / elapsed;
        
        // Calculate total mass
        float total_mass = 0.0f;
        for (int g = 0; g < n_guardians; g++) {
            total_mass += guardians[g].mass;
        }
        
        fprintf(telemetry, "%llu,%d,%.1f,%.0f,%d,%.3f\n",
                total_steps, cognitive_cycle, power_W, steps_per_sec, 
                n_guardians, total_mass);
        
        printf("  %7llu | C%-4d | %5.0f | %8.0f | %9d | %10.0f\n",
               total_steps, cognitive_cycle, power_W, steps_per_sec, 
               n_guardians, total_mass);
        
        // Save census every 3 cycles (C3, C6, C9, C12)
        if (cognitive_cycle % 3 == 0) {
            save_guardian_census(total_steps);
        }
        
        // Check time limit (don't run full 200s for test)
        if (elapsed > 30.0) { // 30 seconds for test
            printf("\n[TIME] 30 seconds reached (test complete)\n");
            break;
        }
    }
    
    auto t_end = std::chrono::steady_clock::now();
    double runtime = std::chrono::duration<double>(t_end - t0).count();
    
    // Final results
    printf("\n=======================================================================\n");
    printf("  SEED BRAIN SIMPLE - RESULTS\n");
    printf("=======================================================================\n");
    
    printf("\nEXPERIMENT SUMMARY:\n");
    printf("  Total steps:    %llu\n", total_steps);
    printf("  Runtime:        %.1f seconds\n", runtime);
    printf("  Steps/sec:      %.0f\n", total_steps / runtime);
    printf("  Cognitive cycles: %d\n", cognitive_cycle);
    
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("  Final power:    %.1f W (GTX 1050 TDP: %.1f W)\n", 
           power_mW / 1000.0f, SB_TDP);
    
    printf("\nGUARDIAN DETECTION:\n");
    printf("  Total guardians: %d\n", n_guardians);
    printf("  Target (weekend): 194 guardians\n");
    
    if (n_guardians > 0) {
        float avg_mass = 0.0f;
        for (int g = 0; g < n_guardians; g++) {
            avg_mass += guardians[g].mass;
        }
        avg_mass /= n_guardians;
        
        printf("  Average mass:    %.3f (weekend: ~3000)\n", avg_mass);
        printf("  Born at cycles:  ");
        for (int g = 0; g < n_guardians && g < 5; g++) {
            printf("%s ", guardians[g].born);
        }
        if (n_guardians > 5) printf("...");
        printf("\n");
    }
    
    // Save final census
    save_guardian_census(total_steps);
    
    printf("\nCOMPARISON TO WEEKEND EXPERIMENTS:\n");
    printf("  Grid:            %dx%d (matches GTX 1050 adaptation)\n", SB_NX, SB_NY);
    printf("  Tau:             %.4f (matches weekend: 0.7273)\n", SB_TAU);
    printf("  Omega:           %.3f (matches weekend: 1.375)\n", SB_OMEGA);
    printf("  TDP target:      %.1f W (GTX 1050: 75W)\n", SB_TDP);
    
    printf("\nOutput files:\n");
    printf("  seed_brain_telemetry.csv    - Telemetry data\n");
    printf("  guardian_census_simple.json - Guardian census (weekend format)\n");
    
    // Cleanup
    fclose(telemetry);
    cudaFree(f0); cudaFree(f1);
    cudaFree(rho); cudaFree(ux); cudaFree(uy); cudaFree(vorticity);
    free(h_ux); free(h_uy); free(h_vorticity); free(h_rho);
    
    // Free born strings
    for (int g = 0; g < n_guardians; g++) {
        free((void*)guardians[g].born);
    }
    
    nvmlShutdown();
    
    return 0;
}