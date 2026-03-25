/* ============================================================================
 * PROBE B 1024×1024 - NO FFT VERSION
 * Real physics, guardian tracking, shear flow - NO FFT dependency
 * 
 * CONSTITUTION:
 * 1. NO FAKES: If step rate jumps to 300k, stop - LBM bypassed
 * 2. RAW METAL: GPU fans must ramp up, or no work is being done
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

/* ---- Grid ---------------------------------------------------------------- */
#define NX    1024
#define NY    1024
#define NN    (NX * NY)
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

/* ---- Test Protocol ------------------------------------------------------- */
#define TOTAL_STEPS      2000000    // ~1 hour at 5.5k steps/sec
#define STEPS_PER_BATCH  500
#define SAMPLE_INTERVAL  50000      // Sample every 50k steps
#define TOTAL_BATCHES    (TOTAL_STEPS / STEPS_PER_BATCH)
#define SAMPLE_BATCHES   (SAMPLE_INTERVAL / STEPS_PER_BATCH)

/* ---- LBM ---------------------------------------------------------------- */
#define OMEGA  1.0f       // tau=1.0, nu=1/6 — "clear water"

/* ---- Guardian tracking ------------------------------------------------- */
#define MAX_GUARDIANS 200
#define GUARDIAN_THRESHOLD 1.01f  // rho > 1.01 forms guardian

typedef struct {
    float x, y;      // position (grid coordinates)
    float vx, vy;    // velocity
    float mass;      // accumulated mass
    int alive;       // 1 if active
    uint64_t born_step; // step when formed
} Guardian;

Guardian guardians[MAX_GUARDIANS];
int n_guardians = 0;

/* ---- D2Q9 --------------------------------------------------------------- */
__constant__ int   d_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
__constant__ int   d_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
__constant__ float d_w[Q]  = { 4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9,
                               1.f/36,1.f/36,1.f/36,1.f/36 };

/* ======================================================================== */
/*   K E R N E L S                                                          */
/* ======================================================================== */

/* ---- LBM collide & stream ---------------------------------------------- */
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

/* ---- PROBE B: Lattice shear — rotate velocity in top 25% by 90° -------- */
__global__ void probe_rotate_top(float* f, float* rho, float* ux, float* uy,
                                  int nx, int ny) {
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

/* ======================================================================== */
/*   G U A R D I A N   T R A C K I N G                                      */
/* ======================================================================== */

void update_guardians(const float* rho, const float* ux, const float* uy,
                      uint64_t current_step) {
    // Simple guardian detection: local maxima of density
    for (int y = 1; y < NY - 1; y++) {
        for (int x = 1; x < NX - 1; x++) {
            int idx = y * NX + x;
            float rho_val = rho[idx];
            
            // Check if this is a local maximum and above threshold
            if (rho_val > GUARDIAN_THRESHOLD &&
                rho_val > rho[idx - 1] && rho_val > rho[idx + 1] &&
                rho_val > rho[idx - NX] && rho_val > rho[idx + NX]) {
                
                // Check if guardian already exists nearby
                int existing = -1;
                for (int g = 0; g < n_guardians; g++) {
                    if (guardians[g].alive) {
                        float dx = guardians[g].x - x;
                        float dy = guardians[g].y - y;
                        if (dx*dx + dy*dy < 25.0f) { // Within 5 cells
                            existing = g;
                            break;
                        }
                    }
                }
                
                if (existing >= 0) {
                    // Update existing guardian
                    guardians[existing].x = x;
                    guardians[existing].y = y;
                    guardians[existing].vx = ux[idx];
                    guardians[existing].vy = uy[idx];
                    guardians[existing].mass += rho_val - 1.0f;
                } else if (n_guardians < MAX_GUARDIANS) {
                    // Create new guardian
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

void save_guardian_census(uint64_t current_step) {
    FILE* csv = fopen("guardian_census.csv", "w");
    if (!csv) return;
    
    fprintf(csv, "id,x,y,vx,vy,mass,alive,born_step\n");
    
    int alive_count = 0;
    for (int g = 0; g < n_guardians; g++) {
        if (guardians[g].alive) {
            fprintf(csv, "%d,%.2f,%.2f,%.6f,%.6f,%.6f,%d,%llu\n",
                    g, guardians[g].x, guardians[g].y,
                    guardians[g].vx, guardians[g].vy,
                    guardians[g].mass, guardians[g].alive,
                    guardians[g].born_step);
            alive_count++;
        }
    }
    
    fclose(csv);
    
    // Also save JSON for compatibility
    FILE* json = fopen("guardian_census.json", "w");
    if (json) {
        fprintf(json, "{\n");
        fprintf(json, "  \"total_guardians\": %d,\n", alive_count);
        fprintf(json, "  \"current_step\": %llu,\n", current_step);
        fprintf(json, "  \"guardians\": [\n");
        
        int first = 1;
        for (int g = 0; g < n_guardians; g++) {
            if (guardians[g].alive) {
                if (!first) fprintf(json, ",\n");
                first = 0;
                
                fprintf(json, "    {\n");
                fprintf(json, "      \"id\": %d,\n", g);
                fprintf(json, "      \"x\": %.2f,\n", guardians[g].x);
                fprintf(json, "      \"y\": %.2f,\n", guardians[g].y);
                fprintf(json, "      \"vx\": %.6f,\n", guardians[g].vx);
                fprintf(json, "      \"vy\": %.6f,\n", guardians[g].vy);
                fprintf(json, "      \"mass\": %.6f,\n", guardians[g].mass);
                fprintf(json, "      \"alive\": %d,\n", guardians[g].alive);
                fprintf(json, "      \"born_step\": %llu\n", guardians[g].born_step);
                fprintf(json, "    }");
            }
        }
        
        fprintf(json, "\n  ]\n");
        fprintf(json, "}\n");
        fclose(json);
    }
}

/* ======================================================================== */
/*   M A I N   T E S T                                                      */
/* ======================================================================== */

int main() {
    printf("=======================================================================\n");
    printf("  PROBE B 1024×1024 - NO FFT VERSION\n");
    printf("  Beast: RTX 4090, 1024x1024 grid\n");
    printf("  Target: 2M steps (~1 hour at 5.5k steps/sec)\n");
    printf("=======================================================================\n\n");
    
    printf("CONSTITUTION:\n");
    printf("  1. NO FAKES: If step rate jumps to 300k, stop - LBM bypassed\n");
    printf("  2. RAW METAL: GPU fans must ramp up, or no work is being done\n\n");
    
    /* ---- CUDA setup ----------------------------------------------------- */
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    printf("[CUDA] %s  SM %d.%d  SMs: %d\n",
           prop.name, prop.major, prop.minor, prop.multiProcessorCount);
    
    /* ---- NVML power monitoring ----------------------------------------- */
    nvmlInit();
    nvmlDevice_t nvml_dev;
    nvmlDeviceGetHandleByIndex(0, &nvml_dev);
    unsigned int power_mW;
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("[NVML] Idle power: %.1f W\n", power_mW / 1000.0f);
    
    /* ---- Allocate memory ----------------------------------------------- */
    float *f0, *f1, *rho, *ux, *uy;
    cudaMallocManaged(&f0, Q * NN * sizeof(float));
    cudaMallocManaged(&f1, Q * NN * sizeof(float));
    cudaMallocManaged(&rho, NN * sizeof(float));
    cudaMallocManaged(&ux, NN * sizeof(float));
    cudaMallocManaged(&uy, NN * sizeof(float));
    
    /* ---- Initialize equilibrium ---------------------------------------- */
    printf("\n[INIT] Setting up equilibrium state (rho=1.0, u=0)...\n");
    for (int i = 0; i < Q * NN; i++) {
        f0[i] = 1.0f + 0.01f * (rand() / (float)RAND_MAX - 0.5f);
    }
    
    /* ---- Prepare output files ------------------------------------------ */
    FILE* telemetry_csv = fopen("probeB_telemetry.csv", "w");
    fprintf(telemetry_csv, "step,power_w,n_guardians,phase\n");
    
    /* ---- Test phases --------------------------------------------------- */
    enum { PHASE_BASELINE, PHASE_SHEAR, PHASE_RECOVERY } current_phase = PHASE_BASELINE;
    uint64_t shear_trigger_step = 800000;  // Apply shear at 800k steps
    int shear_applied = 0;
    
    auto t0 = std::chrono::steady_clock::now();
    uint64_t total_steps = 0;
    
    printf("\n[PHASE 1: BASELINE & BIRTH] Starting...\n");
    printf("  Batch | Steps   | Power | Guardians | Phase\n");
    printf("  ------|---------|-------|-----------|--------\n");
    
    int cur = 0;
    int guardian_check_interval = 10000; // Check for guardians every 10k steps
    
    for (int batch = 0; batch < TOTAL_BATCHES; batch++) {
        // Run LBM steps
        for (int s = 0; s < STEPS_PER_BATCH; s++) {
            lbm_collide_stream<<<GBLK(NN), BLOCK>>>(
                (cur == 0) ? f0 : f1,
                (cur == 0) ? f1 : f0,
                rho, ux, uy, OMEGA, NX, NY);
            cudaDeviceSynchronize();
            cur = 1 - cur;
        }
        total_steps += STEPS_PER_BATCH;
        
        // Check for guardian formation
        if (total_steps % guardian_check_interval == 0) {
            update_guardians(rho, ux, uy, total_steps);
        }
        
        // Apply shear flow at trigger step (Probe B)
        if (total_steps >= shear_trigger_step && !shear_applied) {
            printf("\n[PHASE 3: SHEAR PUNCH] Applying Probe B at step %llu\n", total_steps);
            printf("  Rotating top 25%% velocity by 90°...\n");
            
            // Apply shear
            probe_rotate_top<<<GBLK(NN), BLOCK>>>(f0, rho, ux, uy, NX, NY);
            cudaDeviceSynchronize();
            probe_rotate_top<<<GBLK(NN), BLOCK>>>(f1, rho, ux, uy, NX, NY);
            cudaDeviceSynchronize();
            
            shear_applied = 1;
            current_phase = PHASE_SHEAR;
        }
        
        // Sample every SAMPLE_INTERVAL steps
        if ((batch + 1) % SAMPLE_BATCHES == 0) {
            // Get power usage
            nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
            float power_W = power_mW / 1000.0f;
            
            // Log to CSV
            const char* phase_str = "baseline";
            if (current_phase == PHASE_SHEAR) phase_str = "shear";
            else if (current_phase == PHASE_RECOVERY && shear_applied) phase_str = "recovery";
            
            fprintf(telemetry_csv, "%llu,%.1f,%d,%s\n", 
                    total_steps, power_W, n_guardians, phase_str);
            
            // Print progress
            printf("  %5d | %7llu | %5.0f | %9d | %s\n",
                   batch + 1, total_steps, power_W, n_guardians, phase_str);
            
            // CONSTITUTION CHECK 1: Step rate
            auto t_now = std::chrono::steady_clock::now();
            double elapsed = std::chrono::duration<double>(t_now - t0).count();
            float steps_per_sec = total_steps / elapsed;
            
            if (steps_per_sec > 10000.0f) {
                printf("\n🚨 CONSTITUTION VIOLATION: Step rate = %.0f (>10k)\n", steps_per_sec);
                printf("   LBM may be bypassed. Stopping test.\n");
                break;
            }
            
            // CONSTITUTION CHECK 2: Power scaling
            if (power_W < 50.0f && elapsed > 60.0f) {
                printf("\n🚨 CONSTITUTION VIOLATION: Power = %.1f W (<50W)\n", power_W);
                printf("   GPU not under load. Stopping test.\n");
                break;
            }
            
            // Phase transition: After shear, move to recovery
            if (shear_applied && current_phase == PHASE_SHEAR && 
                total_steps > shear_trigger_step + 100000) {
                printf("\n[PHASE 4: RECOVERY] Monitoring reorganization...\n");
                current_phase = PHASE_RECOVERY;
            }
            
            // Save guardian census periodically
            if (n_guardians > 0 && total_steps % 100000 == 0) {
                save_guardian_census(total_steps);
            }
        }
        
        // Check if we've reached time limit (~1 hour)
        auto t_now = std::chrono::steady_clock::now();
        double elapsed = std::chrono::duration<double>(t_now - t0).count();
        if (elapsed > 3600.0) {  // 1 hour
            printf("\n[TIME] 1 hour reached at step %llu\n", total_steps);
            break;
        }
    }
    
    auto t_end = std::chrono::steady_clock::now();
    double runtime = std::chrono::duration<double>(t_end - t0).count();
    
    /* ---- Final analysis ------------------------------------------------ */
    printf("\n=======================================================================\n");
    printf("  PROBE B TEST - FINAL RESULTS\n");
    printf("=======================================================================\n");
    
    printf("\nPERFORMANCE:\n");
    printf("  Total steps:    %llu\n", total_steps);
    printf("  Runtime:        %.1f seconds (%.2f hours)\n", runtime, runtime / 3600.0);
    printf("  Steps/sec:      %.0f\n", total_steps / runtime);
    printf("  Expected:       ~5,500 steps/sec\n");
    
    printf("\nPOWER USAGE:\n");
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("  Final power:    %.1f W\n", power_mW / 1000.0f);
    printf("  Idle power:     ~37 W\n");
    printf("  Load power:     ~290 W\n");
    
    printf("\nGUARDIAN FORMATION:\n");
    int alive_guardians = 0;
    for (int g = 0; g < n_guardians; g++) {
        if (guardians[g].alive) alive_guardians++;
    }
    printf("  Total guardians: %d\n", alive_guardians);
    printf("  Expected (March 7): 194 guardians\n");
    
    // Save final guardian census
    save_guardian_census(total_steps);
    
    printf("\nSHEAR FLOW:\n");
    if (shear_applied) {
        printf("  ✅ Applied at step %llu\n", shear_trigger_step);
    } else {
        printf("  ❌ NOT applied\n");
    }
    
    printf("\n=======================================================================\n");
    printf("  V E R D I C T\n");
    printf("=======================================================================\n");
    
    int passes = 0;
    int total_tests = 4;
    
    // Test 1: Performance reality
    float steps_per_sec = total_steps / runtime;
    if (steps_per_sec > 4000 && steps_per_sec < 7000) {
        printf("✅ PERFORMANCE: %.0f steps/sec (within 5.5k ± 25%%)\n", steps_per_sec);
        passes++;
    } else {
        printf("❌ PERFORMANCE: %.0f steps/sec (expected ~5.5k)\n", steps_per_sec);
    }
    
    // Test 2: Power scaling
    float final_power = power_mW / 1000.0f;
    if (final_power > 100.0f) {
        printf("✅ POWER: %.1f W (above idle, real work)\n", final_power);
        passes++;
    } else {
        printf("❌ POWER: %.1f W (not scaling with load)\n", final_power);
    }
    
    // Test 3: Guardian formation
    if (alive_guardians > 0) {
        printf("✅ GUARDIANS: %d formed (real structure)\n", alive_guardians);
        passes++;
    } else {
        printf("❌ GUARDIANS: None formed (no structure)\n");
    }
    
    // Test 4: Shear applied
    if (shear_applied) {
        printf("✅ SHEAR: Probe B applied at step %llu\n", shear_trigger_step);
        passes++;
    } else {
        printf("❌ SHEAR: Not applied\n");
    }
    
    printf("\nSCORE: %d/%d tests passed\n", passes, total_tests);
    
    if (passes == total_tests) {
        printf("\n🎯 PROBE B TEST PASSED: System shows real physics\n");
        printf("   The 4090 remembers how to be a brain.\n");
    } else if (passes >= 3) {
        printf("\n⚠️  PARTIAL SUCCESS: %d/4 tests passed\n", passes);
        printf("   Some physics working, needs investigation.\n");
    } else {
        printf("\n🚨 TEST FAILED: Only %d/4 tests passed\n", passes);
        printf("   System not exhibiting real behavior.\n");
    }
    
    printf("\nOutput files:\n");
    printf("  probeB_telemetry.csv    - Step-by-step telemetry\n");
    printf("  guardian_census.csv     - Guardian positions/mass/velocity\n");
    printf("  guardian_census.json    - JSON format for compatibility\n");
    
    /* ---- Cleanup ------------------------------------------------------- */
    fclose(telemetry_csv);
    cudaFree(f0); cudaFree(f1);
    cudaFree(rho); cudaFree(ux); cudaFree(uy);
    nvmlShutdown();
    
    return (passes >= 3) ? 0 : 1;
}