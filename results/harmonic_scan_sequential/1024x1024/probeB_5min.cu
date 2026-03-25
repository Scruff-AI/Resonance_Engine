/* ============================================================================
 * PROBE B 5-MINUTE TEST - Immediate telemetry
 * Real physics, guardian tracking - 5 minute test
 * ============================================================================ */

#include <cuda_runtime.h>
#include <nvml.h>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cmath>
#include <chrono>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define NX    1024
#define NY    1024
#define NN    (NX * NY)
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

#define TOTAL_STEPS      300000     // ~5 minutes at 5.5k steps/sec
#define STEPS_PER_BATCH  1000
#define SAMPLE_INTERVAL  10000      // Sample every 10k steps

#define OMEGA  1.0f

#define MAX_GUARDIANS 200
#define GUARDIAN_THRESHOLD 1.01f

typedef struct {
    float x, y;
    float vx, vy;
    float mass;
    int alive;
    uint64_t born_step;
} Guardian;

Guardian guardians[MAX_GUARDIANS];
int n_guardians = 0;

__constant__ int   d_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
__constant__ int   d_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
__constant__ float d_w[Q]  = { 4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9,
                               1.f/36,1.f/36,1.f/36,1.f/36 };

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

void update_guardians(const float* rho, const float* ux, const float* uy,
                      uint64_t current_step) {
    for (int y = 1; y < NY - 1; y++) {
        for (int x = 1; x < NX - 1; x++) {
            int idx = y * NX + x;
            float rho_val = rho[idx];
            
            if (rho_val > GUARDIAN_THRESHOLD &&
                rho_val > rho[idx - 1] && rho_val > rho[idx + 1] &&
                rho_val > rho[idx - NX] && rho_val > rho[idx + NX]) {
                
                int existing = -1;
                for (int g = 0; g < n_guardians; g++) {
                    if (guardians[g].alive) {
                        float dx = guardians[g].x - x;
                        float dy = guardians[g].y - y;
                        if (dx*dx + dy*dy < 25.0f) {
                            existing = g;
                            break;
                        }
                    }
                }
                
                if (existing >= 0) {
                    guardians[existing].x = x;
                    guardians[existing].y = y;
                    guardians[existing].vx = ux[idx];
                    guardians[existing].vy = uy[idx];
                    guardians[existing].mass += rho_val - 1.0f;
                } else if (n_guardians < MAX_GUARDIANS) {
                    guardians[n_guardians].x = x;
                    guardians[n_guardians].y = y;
                    guardians[n_guardians].vx = ux[idx];
                    guardians[n_guardians].vy = uy[idx];
                    guardians[n_guardians].mass = rho_val - 1.0f;
                    guardians[n_guardians].alive = 1;
                    guardians[n_guardians].born_step = current_step;
                    n_guardians++;
                }
            }
        }
    }
}

int main() {
    printf("=======================================================================\n");
    printf("  PROBE B 5-MINUTE TEST - Immediate Telemetry\n");
    printf("  Beast: RTX 4090, 1024x1024 grid\n");
    printf("  Target: 300k steps (~5 minutes at 5.5k steps/sec)\n");
    printf("=======================================================================\n\n");
    
    // CUDA setup
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    printf("[CUDA] %s  SM %d.%d  SMs: %d\n",
           prop.name, prop.major, prop.minor, prop.multiProcessorCount);
    
    // NVML power monitoring
    nvmlInit();
    nvmlDevice_t nvml_dev;
    nvmlDeviceGetHandleByIndex(0, &nvml_dev);
    unsigned int power_mW;
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("[NVML] Idle power: %.1f W\n", power_mW / 1000.0f);
    
    // Allocate memory
    float *f0, *f1, *rho, *ux, *uy;
    cudaMallocManaged(&f0, Q * NN * sizeof(float));
    cudaMallocManaged(&f1, Q * NN * sizeof(float));
    cudaMallocManaged(&rho, NN * sizeof(float));
    cudaMallocManaged(&ux, NN * sizeof(float));
    cudaMallocManaged(&uy, NN * sizeof(float));
    
    // Initialize
    printf("\n[INIT] Setting up equilibrium state...\n");
    for (int i = 0; i < Q * NN; i++) {
        f0[i] = 1.0f + 0.01f * (rand() / (float)RAND_MAX - 0.5f);
    }
    
    // Prepare output
    FILE* csv = fopen("probeB_5min.csv", "w");
    fprintf(csv, "step,power_w,n_guardians\n");
    
    auto t0 = std::chrono::steady_clock::now();
    uint64_t total_steps = 0;
    int cur = 0;
    
    printf("\n[RUNNING] Starting 5-minute test...\n");
    printf("  Steps   | Power | Guardians | Steps/sec\n");
    printf("  --------|-------|-----------|-----------\n");
    
    int batches = TOTAL_STEPS / STEPS_PER_BATCH;
    
    for (int batch = 0; batch < batches; batch++) {
        // Run steps
        for (int s = 0; s < STEPS_PER_BATCH; s++) {
            lbm_collide_stream<<<GBLK(NN), BLOCK>>>(
                (cur == 0) ? f0 : f1,
                (cur == 0) ? f1 : f0,
                rho, ux, uy, OMEGA, NX, NY);
            cudaDeviceSynchronize();
            cur = 1 - cur;
        }
        total_steps += STEPS_PER_BATCH;
        
        // Update guardians every 10k steps
        if (total_steps % 10000 == 0) {
            update_guardians(rho, ux, uy, total_steps);
        }
        
        // Report every 10k steps
        if (total_steps % SAMPLE_INTERVAL == 0) {
            nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
            float power_W = power_mW / 1000.0f;
            
            auto t_now = std::chrono::steady_clock::now();
            double elapsed = std::chrono::duration<double>(t_now - t0).count();
            float steps_per_sec = total_steps / elapsed;
            
            fprintf(csv, "%llu,%.1f,%d\n", total_steps, power_W, n_guardians);
            
            printf("  %7llu | %5.0f | %9d | %8.0f\n",
                   total_steps, power_W, n_guardians, steps_per_sec);
            
            // Constitution check
            if (steps_per_sec > 10000.0f) {
                printf("\n🚨 STEP RATE TOO HIGH: %.0f (>10k)\n", steps_per_sec);
                break;
            }
            
            if (power_W < 50.0f && elapsed > 30.0f) {
                printf("\n🚨 POWER TOO LOW: %.1f W (<50W)\n", power_W);
                break;
            }
        }
        
        // Check time limit (5 minutes)
        auto t_now = std::chrono::steady_clock::now();
        double elapsed = std::chrono::duration<double>(t_now - t0).count();
        if (elapsed > 300.0) {  // 5 minutes
            printf("\n[TIME] 5 minutes reached\n");
            break;
        }
    }
    
    auto t_end = std::chrono::steady_clock::now();
    double runtime = std::chrono::duration<double>(t_end - t0).count();
    
    // Final results
    printf("\n=======================================================================\n");
    printf("  5-MINUTE TEST RESULTS\n");
    printf("=======================================================================\n");
    
    printf("\nPERFORMANCE:\n");
    printf("  Total steps:    %llu\n", total_steps);
    printf("  Runtime:        %.1f seconds\n", runtime);
    printf("  Steps/sec:      %.0f\n", total_steps / runtime);
    printf("  Expected:       ~5,500 steps/sec\n");
    
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("\nPOWER:\n");
    printf("  Final power:    %.1f W\n", power_mW / 1000.0f);
    printf("  Idle power:     ~37 W\n");
    printf("  Load power:     ~290 W\n");
    
    printf("\nGUARDIANS:\n");
    int alive_guardians = 0;
    for (int g = 0; g < n_guardians; g++) {
        if (guardians[g].alive) alive_guardians++;
    }
    printf("  Total formed:   %d\n", alive_guardians);
    printf("  Target (5 min): 13 guardians\n");
    
    // Save guardian census
    FILE* guardian_csv = fopen("guardian_census_5min.csv", "w");
    if (guardian_csv) {
        fprintf(guardian_csv, "id,x,y,vx,vy,mass,alive,born_step\n");
        for (int g = 0; g < n_guardians; g++) {
            if (guardians[g].alive) {
                fprintf(guardian_csv, "%d,%.2f,%.2f,%.6f,%.6f,%.6f,%d,%llu\n",
                        g, guardians[g].x, guardians[g].y,
                        guardians[g].vx, guardians[g].vy,
                        guardians[g].mass, guardians[g].alive,
                        guardians[g].born_step);
            }
        }
        fclose(guardian_csv);
    }
    
    printf("\nVERDICT:\n");
    float steps_per_sec = total_steps / runtime;
    
    if (steps_per_sec > 4000 && steps_per_sec < 7000) {
        printf("✅ PERFORMANCE: %.0f steps/sec (real physics)\n", steps_per_sec);
    } else {
        printf("❌ PERFORMANCE: %.0f steps/sec (suspicious)\n", steps_per_sec);
    }
    
    if (power_mW / 1000.0f > 100.0f) {
        printf("✅ POWER: %.1f W (real work)\n", power_mW / 1000.0f);
    } else {
        printf("❌ POWER: %.1f W (not scaling)\n", power_mW / 1000.0f);
    }
    
    if (alive_guardians > 0) {
        printf("✅ GUARDIANS: %d formed (structure exists)\n", alive_guardians);
    } else {
        printf("❌ GUARDIANS: None formed (no structure)\n");
    }
    
    printf("\nOutput files:\n");
    printf("  probeB_5min.csv           - Telemetry data\n");
    printf("  guardian_census_5min.csv  - Guardian positions/mass/velocity\n");
    
    // Cleanup
    fclose(csv);
    cudaFree(f0); cudaFree(f1);
    cudaFree(rho); cudaFree(ux); cudaFree(uy);
    nvmlShutdown();
    
    return 0;
}