/* ============================================================================
 * SEED BRAIN TIMED - Matches GTX 1050 Performance
 * Exact weekend parameters with proper timing
 * ============================================================================ */

#include <cuda_runtime.h>
#include <nvml.h>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cmath>
#include <chrono>
#include <thread>
#include <vector>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* ---------- EXACT WEEKEND PARAMETERS ------------------------------------ */
#define SB_NX 512
#define SB_NY 512
#define SB_N  (SB_NX * SB_NY)  /* 262,144 nodes */
#define SB_Q  9

/* GTX 1050 ADAPTATION parameters (from seed_brain.h) */
#define SB_TAU          0.7273f    /* LBM relaxation time */
#define SB_OMEGA        (1.0f / SB_TAU)  /* 1.375 */
#define SB_TDP          75.0f      /* GTX 1050 TDP */
#define SB_P_IDLE       10.0f      /* GTX 1050 idle power */

/* Dual-Resonance Timing */
#define SB_F_METABOLIC      0.005f  /* Carrier freq (Hz) */
#define SB_F_COGNITIVE      0.06f   /* Harmonic freq (Hz) */
#define SB_METABOLIC_PERIOD 200.0f  /* 1/0.005 = 200 seconds */
#define SB_COGNITIVE_PERIOD (1.0f / SB_F_COGNITIVE)  /* 16.67 seconds */

/* Target performance (from weekend experiments) */
#define TARGET_STEPS_PER_SEC 5500.0f

/* ---------- D2Q9 Constants ---------------------------------------------- */
__constant__ int   d_ex[SB_Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
__constant__ int   d_ey[SB_Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
__constant__ float d_w[SB_Q]  = { 4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9,
                                  1.f/36,1.f/36,1.f/36,1.f/36 };

#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

/* ---------- Guardian Structure ------------------------------------------ */
typedef struct {
    int id;
    float position[2];
    float velocity[2];
    float mass;
    float latent_energy;
    char born[8];      // e.g., "C11"
    char state[16];    // e.g., "PULSE"
} Guardian;

std::vector<Guardian> guardians;

/* ---------- LBM Kernel -------------------------------------------------- */
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

/* ---------- Vorticity Calculation --------------------------------------- */
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

/* ---------- Guardian Detection ------------------------------------------ */
void detect_guardians(float* h_vorticity, float* h_ux, float* h_uy, float* h_rho,
                      uint64_t current_step, int cognitive_cycle) {
    // Detection every 10k steps (matches weekend)
    static uint64_t last_detection = 0;
    if (current_step - last_detection < 10000) return;
    last_detection = current_step;
    
    // Adjusted thresholds for 4090 speed (8× faster than GTX 1050)
    // Vorticity accumulates faster at higher step rate
    float vorticity_threshold = 0.0008f;  // 8× higher than weekend
    float mass_threshold = 100.0f;
    
    for (int y = 1; y < SB_NY - 1; y++) {
        for (int x = 1; x < SB_NX - 1; x++) {
            int idx = y * SB_NX + x;
            float w = fabsf(h_vorticity[idx]);
            
            // Check if local maximum and above threshold
            if (w > vorticity_threshold &&
                w > fabsf(h_vorticity[idx - 1]) &&
                w > fabsf(h_vorticity[idx + 1]) &&
                w > fabsf(h_vorticity[idx - SB_NX]) &&
                w > fabsf(h_vorticity[idx + SB_NX])) {
                
                // Check if already tracked (within 5 cells)
                bool existing = false;
                for (auto& g : guardians) {
                    float dx = g.position[0] - x;
                    float dy = g.position[1] - y;
                    if (dx*dx + dy*dy < 25.0f) {
                        existing = true;
                        // Update existing guardian
                        g.position[0] = x;
                        g.position[1] = y;
                        g.velocity[0] = h_ux[idx];
                        g.velocity[1] = h_uy[idx];
                        g.mass += (h_rho[idx] - 1.0f) * 0.1f; // Scale for speed
                        g.latent_energy += w * 0.1f;
                        break;
                    }
                }
                
                // Create new guardian
                if (!existing) {
                    Guardian g;
                    g.id = guardians.size();
                    g.position[0] = x;
                    g.position[1] = y;
                    g.velocity[0] = h_ux[idx];
                    g.velocity[1] = h_uy[idx];
                    g.mass = (h_rho[idx] - 1.0f) * 0.1f;
                    g.latent_energy = w * 0.1f;
                    snprintf(g.born, sizeof(g.born), "C%d", cognitive_cycle);
                    snprintf(g.state, sizeof(g.state), "PULSE");
                    guardians.push_back(g);
                }
            }
        }
    }
}

/* ---------- Save Guardian Census ---------------------------------------- */
void save_guardian_census(const char* filename) {
    FILE* json = fopen(filename, "w");
    if (!json) return;
    
    fprintf(json, "{\n");
    fprintf(json, "  \"total_guardians\": %zu,\n", guardians.size());
    fprintf(json, "  \"guardians\": [\n");
    
    for (size_t g = 0; g < guardians.size(); g++) {
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
    printf("  SEED BRAIN TIMED - Weekend Experiment Reproduction\n");
    printf("  EXACT weekend parameters with GTX 1050 timing\n");
    printf("=======================================================================\n\n");
    
    printf("WEEKEND PARAMETERS:\n");
    printf("  Grid: %dx%d (512×512)\n", SB_NX, SB_NY);
    printf("  Tau: %.4f (omega: %.3f)\n", SB_TAU, SB_OMEGA);
    printf("  Target steps/sec: %.0f (GTX 1050 performance)\n", TARGET_STEPS_PER_SEC);
    printf("  Cognitive period: %.2f seconds\n", SB_COGNITIVE_PERIOD);
    printf("  Metabolic period: %.0f seconds\n", SB_METABOLIC_PERIOD);
    printf("\n");
    
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
    printf("[NVML] Idle power: %.1f W\n", power_mW / 1000.0f);
    
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
    FILE* telemetry = fopen("weekend_reproduction_telemetry.csv", "w");
    fprintf(telemetry, "step,cognitive_cycle,power_w,steps_per_sec,n_guardians,total_mass\n");
    
    auto t0 = std::chrono::steady_clock::now();
    uint64_t total_steps = 0;
    int cur = 0;
    int cognitive_cycle = 0;
    
    // Calculate steps per cognitive cycle
    int steps_per_cognitive_cycle = (int)(SB_COGNITIVE_PERIOD * TARGET_STEPS_PER_SEC);
    
    printf("\n[EXPERIMENT] Running with GTX 1050 timing...\n");
    printf("  Steps   | Cycle | Power | Steps/sec | Guardians | Total Mass\n");
    printf("  --------|-------|-------|-----------|-----------|------------\n");
    
    // Run for 12 cognitive cycles (1 metabolic cycle)
    for (int cycle = 0; cycle < 12; cycle++) {
        cognitive_cycle = cycle + 1; // C1, C2, ..., C12
        
        auto cycle_start = std::chrono::steady_clock::now();
        
        // Run one cognitive cycle
        for (int step = 0; step < steps_per_cognitive_cycle; step += 100) {
            auto batch_start = std::chrono::steady_clock::now();
            
            // Run 100 LBM steps
            for (int s = 0; s < 100; s++) {
                lbm_collide_stream<<<GBLK(SB_N), BLOCK>>>(
                    (cur == 0) ? f0 : f1,
                    (cur == 0) ? f1 : f0,
                    rho, ux, uy, SB_OMEGA, SB_NX, SB_NY);
                cudaDeviceSynchronize();
                cur = 1 - cur;
            }
            total_steps += 100;
            
            // Sleep to match target performance
            auto batch_end = std::chrono::steady_clock::now();
            float batch_time = std::chrono::duration<float>(batch_end - batch_start).count();
            float target_time = 100.0f / TARGET_STEPS_PER_SEC;
            
            if (batch_time < target_time) {
                std::this_thread::sleep_for(
                    std::chrono::microseconds((int)((target_time - batch_time) * 1000000)));
            }
            
            // Detect guardians every 10k steps
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
        
        // Report at end of cognitive cycle
        nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
        float power_W = power_mW / 1000.0f;
        
        auto t_now = std::chrono::steady_clock::now();
        double elapsed = std::chrono::duration<double>(t_now - t0).count();
        float steps_per_sec = total_steps / elapsed;
        
        // Calculate total mass
        float total_mass = 0.0f;
        for (const auto& g : guardians) {
            total_mass += g.mass;
        }
        
        fprintf(telemetry, "%llu,%d,%.1f,%.0f,%zu,%.3f\n",
                total_steps, cognitive_cycle, power_W, steps_per_sec, 
                guardians.size(), total_mass);
        
        printf("  %7llu | C%-4d | %5.0f | %8.0f | %9zu | %10.0f\n",
               total_steps, cognitive_cycle, power_W, steps_per_sec, 
               guardians.size(), total_mass);
        
        // Save census every 3 cycles (C3, C6, C9, C12)
        if (cognitive_cycle % 3 == 0) {
            char filename[64];
            snprintf(filename, sizeof(filename), "guardian_census_C%d.json", cognitive_cycle);
            save_guardian_census(filename);
        }
        
        // Check if we should stop early for testing
        if (elapsed > 60.0) { // 60 seconds for test
            printf("\n[TIME] 60 seconds reached (test complete)\n");
            break;
        }
    }
    
    auto t_end = std::chrono::steady_clock::now();
    double runtime = std::chrono::duration<double>(t_end - t0).count();
    
    // Final results
    printf("\n=======================================================================\n");
    printf("  WEEKEND REPRODUCTION - RESULTS\n");
    printf("=======================================================================\n");
    
    printf("\nEXPERIMENT SUMMARY:\n");
    printf("  Total steps:    %llu\n", total_steps);
    printf("  Runtime:        %.1f seconds\n", runtime);
    printf("  Steps/sec:      %.0f (target: %.0f)\n", total_steps / runtime, TARGET_STEPS_PER_SEC);
    printf("  Cognitive cycles: %d\n", cognitive_cycle);
    
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("  Final power:    %.1f W\n", power_mW / 1000.0f);
    
    printf("\nGUARDIAN DETECTION:\n");
    printf("  Total guardians: %zu\n", guardians.size());
    printf("  Target (weekend): 194 guardians\n");
    
    if (!guardians.empty()) {
        float avg_mass = 0.0f;
        for (const auto& g : guardians) {
            avg_mass += g.mass;
        }
        avg_mass /= guardians.size();
        
        printf("  Average mass:    %.3f (weekend: ~3000)\n", avg_mass);
        printf("  Born at cycles:  ");
        for (size_t g = 0; g < guardians.size() && g < 5; g++) {
            printf("%s ", guardians[g].born);
        }
        if (guardians.size() > 5) printf("...");
        printf("\n");
    }
    
    // Save final census
    save_guardian_census("guardian_census_final.json");
    
    printf("\nCOMPARISON TO WEEKEND EXPERIMENTS:\n");
    printf("  Grid:            %dx%d ✓ (matches weekend)\n", SB_NX, SB_NY);
    printf("  Tau:             %.4f ✓ (matches weekend: 0.7273)\n", SB_TAU);
    printf("  Omega:           %.3f ✓ (matches weekend: 1.375)\n", SB_OMEGA);
    printf("  Timing:          %.0f steps/sec (target: 5500)\n", total_steps / runtime);
    printf("  Guardians:       %zu (target: 194)\n", guardians.size());
    
    printf("\nOutput files:\n");
    printf("  weekend_reproduction_telemetry.csv - Telemetry data\n");
    printf("  guardian_census_final.json         - Guardian census\n");
    
    // Cleanup
    fclose(telemetry);
    cudaFree(f0); cudaFree(f1);
    cudaFree(rho); cudaFree(ux); cudaFree(uy); cudaFree(vorticity);
    free(h_ux); free(h_uy); free(h_vorticity); free(h_rho);
    
    nvmlShutdown();
    
    return 0;
}