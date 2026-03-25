/* ============================================================================
 * METRICS ONLY - Collect Data, No Boundaries
 * March 7 Hard-Print Compliance
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

#define NX    1024
#define NY    1024
#define NN    (NX * NY)
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

#define TOTAL_STEPS      1000000    // ~3 minutes
#define STEPS_PER_BATCH  500
#define SAMPLE_INTERVAL  50000

#define OMEGA  1.0f

/* ---- Vorticity Threshold ------------------------------------------------- */
#define VORTICITY_THRESHOLD 0.000001f
#define PERSISTENCE_STEPS   275000
#define MAX_GUARDIANS       200

/* ---- Guardian Structure ------------------------------------------------- */
typedef struct {
    int id;
    float position[2];
    float velocity[2];
    float mass;
    float latent_energy;
    uint64_t persistence_age;
    uint64_t born_step;
    int active;
} Guardian;

Guardian guardians[MAX_GUARDIANS];
int n_guardians = 0;

/* ---- Vortex Seed Tracking ----------------------------------------------- */
typedef struct {
    float x, y;
    float vorticity;
    uint64_t first_seen;
    uint64_t last_seen;
    int active;
} VortexSeed;

VortexSeed vortex_seeds[10000];
int n_seeds = 0;

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

/* ---- Finite Difference Vorticity --------------------------------------- */
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

/* ======================================================================== */
/*   H O S T   F U N C T I O N S                                            */
/* ======================================================================== */

void detect_vortex_seeds(const float* vorticity, const float* ux, const float* uy,
                         uint64_t current_step) {
    static uint64_t last_check = 0;
    if (current_step - last_check < 10000) return;
    last_check = current_step;
    
    n_seeds = 0;
    
    for (int y = 1; y < NY - 1; y++) {
        for (int x = 1; x < NX - 1; x++) {
            int idx = y * NX + x;
            float w = fabsf(vorticity[idx]);
            
            if (w > VORTICITY_THRESHOLD &&
                w > fabsf(vorticity[idx - 1]) &&
                w > fabsf(vorticity[idx + 1]) &&
                w > fabsf(vorticity[idx - NX]) &&
                w > fabsf(vorticity[idx + NX])) {
                
                int existing = -1;
                for (int s = 0; s < n_seeds; s++) {
                    if (vortex_seeds[s].active) {
                        float dx = vortex_seeds[s].x - x;
                        float dy = vortex_seeds[s].y - y;
                        if (dx*dx + dy*dy < 16.0f) {
                            existing = s;
                            break;
                        }
                    }
                }
                
                if (existing >= 0) {
                    vortex_seeds[existing].x = x;
                    vortex_seeds[existing].y = y;
                    vortex_seeds[existing].vorticity = w;
                    vortex_seeds[existing].last_seen = current_step;
                } else if (n_seeds < 10000) {
                    vortex_seeds[n_seeds].x = x;
                    vortex_seeds[n_seeds].y = y;
                    vortex_seeds[n_seeds].vorticity = w;
                    vortex_seeds[n_seeds].first_seen = current_step;
                    vortex_seeds[n_seeds].last_seen = current_step;
                    vortex_seeds[n_seeds].active = 1;
                    n_seeds++;
                }
            }
        }
    }
    
    for (int s = 0; s < n_seeds; s++) {
        if (vortex_seeds[s].active) {
            uint64_t age = current_step - vortex_seeds[s].first_seen;
            
            if (age >= PERSISTENCE_STEPS && n_guardians < MAX_GUARDIANS) {
                int idx = (int)vortex_seeds[s].y * NX + (int)vortex_seeds[s].x;
                
                guardians[n_guardians].id = n_guardians;
                guardians[n_guardians].position[0] = vortex_seeds[s].x;
                guardians[n_guardians].position[1] = vortex_seeds[s].y;
                guardians[n_guardians].velocity[0] = ux[idx];
                guardians[n_guardians].velocity[1] = uy[idx];
                guardians[n_guardians].mass = 1.0f;
                guardians[n_guardians].latent_energy = vortex_seeds[s].vorticity * age;
                guardians[n_guardians].persistence_age = age;
                guardians[n_guardians].born_step = current_step;
                guardians[n_guardians].active = 1;
                
                n_guardians++;
                vortex_seeds[s].active = 0;
            }
            
            if (current_step - vortex_seeds[s].last_seen > 10000) {
                vortex_seeds[s].active = 0;
            }
        }
    }
}

void save_guardian_census(uint64_t current_step) {
    FILE* json = fopen("guardian_census_metrics.json", "w");
    if (!json) return;
    
    fprintf(json, "{\n");
    fprintf(json, "  \"total_guardians\": %d,\n", n_guardians);
    fprintf(json, "  \"current_step\": %llu,\n", current_step);
    fprintf(json, "  \"guardians\": [\n");
    
    for (int g = 0; g < n_guardians; g++) {
        if (guardians[g].active) {
            if (g > 0) fprintf(json, ",\n");
            
            fprintf(json, "    {\n");
            fprintf(json, "      \"id\": %d,\n", guardians[g].id);
            fprintf(json, "      \"position\": [%.1f, %.1f],\n", 
                    guardians[g].position[0], guardians[g].position[1]);
            fprintf(json, "      \"velocity\": [%.6f, %.6f],\n",
                    guardians[g].velocity[0], guardians[g].velocity[1]);
            fprintf(json, "      \"mass\": %.3f,\n", guardians[g].mass);
            fprintf(json, "      \"latent_energy\": %.6f,\n", 
                    guardians[g].latent_energy);
            fprintf(json, "      \"persistence_age\": %llu,\n",
                    guardians[g].persistence_age);
            fprintf(json, "      \"born_step\": %llu\n", guardians[g].born_step);
            fprintf(json, "    }");
        }
    }
    
    fprintf(json, "\n  ]\n");
    fprintf(json, "}\n");
    fclose(json);
}

/* ======================================================================== */
/*   M A I N   T E S T                                                      */
/* ======================================================================== */

int main() {
    printf("=======================================================================\n");
    printf("  METRICS ONLY - Collect Data, No Boundaries\n");
    printf("  March 7 Hard-Print Compliance\n");
    printf("=======================================================================\n\n");
    
    printf("PHILOSOPHY:\n");
    printf("  1. NO POWER BOUNDARIES - Let data speak\n");
    printf("  2. NO EARLY STOPPING - Run full experiment\n");
    printf("  3. NO JUDGMENTS - Collect all metrics\n");
    printf("  4. MARCH 7 FORMAT - Standardized output\n\n");
    
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
    float *f0, *f1, *rho, *ux, *uy, *vorticity;
    float *h_ux, *h_uy, *h_vorticity;
    
    cudaMalloc(&f0, Q * NN * sizeof(float));
    cudaMalloc(&f1, Q * NN * sizeof(float));
    cudaMalloc(&rho, NN * sizeof(float));
    cudaMalloc(&ux, NN * sizeof(float));
    cudaMalloc(&uy, NN * sizeof(float));
    cudaMalloc(&vorticity, NN * sizeof(float));
    
    h_ux = (float*)malloc(NN * sizeof(float));
    h_uy = (float*)malloc(NN * sizeof(float));
    h_vorticity = (float*)malloc(NN * sizeof(float));
    
    // Initialize
    float* h_f0 = (float*)malloc(Q * NN * sizeof(float));
    for (int i = 0; i < Q * NN; i++) {
        h_f0[i] = 1.0f + 0.01f * (rand() / (float)RAND_MAX - 0.5f);
    }
    cudaMemcpy(f0, h_f0, Q * NN * sizeof(float), cudaMemcpyHostToDevice);
    free(h_f0);
    
    // Prepare output
    FILE* csv = fopen("metrics_telemetry.csv", "w");
    fprintf(csv, "step,power_w,n_seeds,n_guardians,steps_per_sec\n");
    
    auto t0 = std::chrono::steady_clock::now();
    uint64_t total_steps = 0;
    int cur = 0;
    
    printf("\n[EXPERIMENT] Starting metrics collection...\n");
    printf("  Steps   | Power | Seeds | Guardians | Steps/sec\n");
    printf("  --------|-------|-------|-----------|-----------\n");
    
    int batches = TOTAL_STEPS / STEPS_PER_BATCH;
    
    for (int batch = 0; batch < batches; batch++) {
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
        
        // Compute vorticity map every 10k steps
        if (total_steps % 10000 == 0) {
            compute_vorticity_map<<<GBLK(NN), BLOCK>>>(ux, uy, vorticity, NX, NY);
            cudaDeviceSynchronize();
            
            // Copy to host for detection
            cudaMemcpy(h_ux, ux, NN * sizeof(float), cudaMemcpyDeviceToHost);
            cudaMemcpy(h_uy, uy, NN * sizeof(float), cudaMemcpyDeviceToHost);
            cudaMemcpy(h_vorticity, vorticity, NN * sizeof(float), cudaMemcpyDeviceToHost);
            
            detect_vortex_seeds(h_vorticity, h_ux, h_uy, total_steps);
        }
        
        // Report every 50k steps
        if (total_steps % SAMPLE_INTERVAL == 0) {
            nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
            float power_W = power_mW / 1000.0f;
            
            auto t_now = std::chrono::steady_clock::now();
            double elapsed = std::chrono::duration<double>(t_now - t0).count();
            float steps_per_sec = total_steps / elapsed;
            
            fprintf(csv, "%llu,%.1f,%d,%d,%.0f\n", 
                    total_steps, power_W, n_seeds, n_guardians, steps_per_sec);
            
            printf("  %7llu | %5.0f | %5d | %9d | %8.0f\n",
                   total_steps, power_W, n_seeds, n_guardians, steps_per_sec);
            
            // NO POWER BOUNDARY CHECK - Let data speak
            
            // Save census periodically
            if (n_guardians > 0 && total_steps % 100000 == 0) {
                save_guardian_census(total_steps);
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
    
    // Final results - DATA ONLY, NO JUDGMENTS
    printf("\n=======================================================================\n");
    printf("  METRICS ONLY - EXPERIMENT DATA\n");
    printf("=======================================================================\n");
    
    printf("\nRAW METRICS:\n");
    printf("  Total steps:    %llu\n", total_steps);
    printf("  Runtime:        %.1f seconds (%.2f minutes)\n", runtime, runtime / 60.0);
    printf("  Steps/sec:      %.0f\n", total_steps / runtime);
    
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("  Final power:    %.1f W\n", power_mW / 1000.0f);
    
    printf("\nGUARDIAN DETECTION:\n");
    int active_guardians = 0;
    for (int g = 0; g < n_guardians; g++) {
        if (guardians[g].active) active_guardians++;
    }
    printf("  Vortex seeds:   %d\n", n_seeds);
    printf("  Guardians born: %d\n", active_guardians);
    printf("  Threshold:      |ω| > %.6f\n", VORTICITY_THRESHOLD);
    printf("  Persistence:    %llu steps required\n", PERSISTENCE_STEPS);
    
    // Save final census
    save_guardian_census(total_steps);
    
    printf("\nDATA FILES:\n");
    printf("  metrics_telemetry.csv        - Telemetry data\n");
    printf("  guardian_census_metrics.json - Guardian census (March 7 format)\n");
    
    printf("\nANALYSIS NOTES:\n");
    printf("  - No power boundaries applied\n");
    printf("  - No early stopping\n");
    printf("  - Raw data collection only\n");
    printf("  - March 7 format compliance\n");
    
    // Cleanup
    fclose(csv);
    cudaFree(f0); cudaFree(f1);
    cudaFree(rho); cudaFree(ux); cudaFree(uy); cudaFree(vorticity);
    free(h_ux); free(h_uy); free(h_vorticity);
    nvmlShutdown();
    
    return 0;  // Always success - data is what matters
}