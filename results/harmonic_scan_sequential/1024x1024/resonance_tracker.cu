/* ============================================================================
 * RESONANCE TRACKER - LTP (Long-Term Potentiation) Metrics
 * Fractal Brain Cheat Sheet: Resonance = Connection strengthening
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

#define TOTAL_STEPS      500000     // ~1.5 minutes
#define STEPS_PER_BATCH  500
#define SAMPLE_INTERVAL  10000      // More frequent sampling

#define OMEGA  1.0f

/* ---- Resonance Threshold ------------------------------------------------ */
#define VORTICITY_THRESHOLD 0.0000001f  // Much lower for resonance detection
#define MIN_LIFETIME        10000       // 10k steps minimum for resonance
#define MAX_PATTERNS        1000

/* ---- Resonance Pattern Structure --------------------------------------- */
typedef struct {
    int id;
    float position[2];      // Current position
    float velocity[2];      // Current velocity
    float vorticity;        // Current vorticity strength
    float mass;             // Accumulated mass
    float coherence;        // Pattern coherence (0-1)
    uint64_t first_seen;    // Step when first detected
    uint64_t last_seen;     // Step when last seen
    uint64_t lifetime;      // Total steps survived
    int active;             // 1 if currently active
    float growth_rate;      // Mass accumulation rate
    float stability;        // Position stability (0-1)
    
    // Resonance metrics
    float peak_vorticity;   // Maximum vorticity reached
    float avg_vorticity;    // Average vorticity over lifetime
    int persistence_count;  // Number of consecutive detections
} ResonancePattern;

ResonancePattern patterns[MAX_PATTERNS];
int n_patterns = 0;

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
/*   R E S O N A N C E   T R A C K I N G                                    */
/* ======================================================================== */

void update_resonance_patterns(const float* vorticity, const float* ux, const float* uy,
                               const float* rho, uint64_t current_step) {
    // Track local maxima of vorticity
    for (int y = 1; y < NY - 1; y++) {
        for (int x = 1; x < NX - 1; x++) {
            int idx = y * NX + x;
            float w = fabsf(vorticity[idx]);
            
            // Check if above threshold and local maximum
            if (w > VORTICITY_THRESHOLD &&
                w > fabsf(vorticity[idx - 1]) &&
                w > fabsf(vorticity[idx + 1]) &&
                w > fabsf(vorticity[idx - NX]) &&
                w > fabsf(vorticity[idx + NX])) {
                
                // Find existing pattern nearby
                int existing = -1;
                float min_dist = 10.0f;  // Within 10 cells
                
                for (int p = 0; p < n_patterns; p++) {
                    if (patterns[p].active) {
                        float dx = patterns[p].position[0] - x;
                        float dy = patterns[p].position[1] - y;
                        float dist = sqrtf(dx*dx + dy*dy);
                        
                        if (dist < min_dist) {
                            min_dist = dist;
                            existing = p;
                        }
                    }
                }
                
                if (existing >= 0) {
                    // Update existing pattern
                    ResonancePattern* pat = &patterns[existing];
                    
                    // Calculate movement
                    float dx = x - pat->position[0];
                    float dy = y - pat->position[1];
                    float movement = sqrtf(dx*dx + dy*dy);
                    
                    // Update position (weighted average)
                    pat->position[0] = 0.7f * pat->position[0] + 0.3f * x;
                    pat->position[1] = 0.7f * pat->position[1] + 0.3f * y;
                    
                    // Update velocity
                    pat->velocity[0] = ux[idx];
                    pat->velocity[1] = uy[idx];
                    
                    // Update vorticity stats
                    pat->vorticity = w;
                    if (w > pat->peak_vorticity) pat->peak_vorticity = w;
                    pat->avg_vorticity = (pat->avg_vorticity * pat->persistence_count + w) / (pat->persistence_count + 1);
                    
                    // Update mass (accumulate density)
                    pat->mass += rho[idx] - 1.0f;  // Excess density
                    
                    // Update coherence (inverse of movement)
                    pat->coherence = 1.0f / (1.0f + movement);
                    
                    // Update stability (how little it moves)
                    pat->stability = 1.0f / (1.0f + movement * 10.0f);
                    
                    // Update lifetime and persistence
                    pat->last_seen = current_step;
                    pat->lifetime = current_step - pat->first_seen;
                    pat->persistence_count++;
                    
                    // Calculate growth rate
                    if (pat->lifetime > 0) {
                        pat->growth_rate = pat->mass / pat->lifetime;
                    }
                } else if (n_patterns < MAX_PATTERNS) {
                    // Create new pattern
                    ResonancePattern* pat = &patterns[n_patterns];
                    
                    pat->id = n_patterns;
                    pat->position[0] = x;
                    pat->position[1] = y;
                    pat->velocity[0] = ux[idx];
                    pat->velocity[1] = uy[idx];
                    pat->vorticity = w;
                    pat->mass = rho[idx] - 1.0f;
                    pat->coherence = 1.0f;
                    pat->first_seen = current_step;
                    pat->last_seen = current_step;
                    pat->lifetime = 0;
                    pat->active = 1;
                    pat->growth_rate = 0.0f;
                    pat->stability = 1.0f;
                    pat->peak_vorticity = w;
                    pat->avg_vorticity = w;
                    pat->persistence_count = 1;
                    
                    n_patterns++;
                }
            }
        }
    }
    
    // Deactivate patterns not seen recently
    for (int p = 0; p < n_patterns; p++) {
        if (patterns[p].active) {
            if (current_step - patterns[p].last_seen > 5000) {  // 5k steps timeout
                patterns[p].active = 0;
            }
        }
    }
}

/* ---- Save Resonance Metrics -------------------------------------------- */
void save_resonance_metrics(uint64_t current_step) {
    FILE* csv = fopen("resonance_metrics.csv", "w");
    if (!csv) return;
    
    // Header
    fprintf(csv, "pattern_id,step,pos_x,pos_y,vel_x,vel_y,vorticity,mass,coherence,lifetime,growth_rate,stability,peak_vort,avg_vort,persistence\n");
    
    for (int p = 0; p < n_patterns; p++) {
        if (patterns[p].active && patterns[p].lifetime >= MIN_LIFETIME) {
            fprintf(csv, "%d,%llu,%.1f,%.1f,%.6f,%.6f,%.6e,%.6f,%.3f,%llu,%.6e,%.3f,%.6e,%.6e,%d\n",
                    patterns[p].id,
                    current_step,
                    patterns[p].position[0],
                    patterns[p].position[1],
                    patterns[p].velocity[0],
                    patterns[p].velocity[1],
                    patterns[p].vorticity,
                    patterns[p].mass,
                    patterns[p].coherence,
                    patterns[p].lifetime,
                    patterns[p].growth_rate,
                    patterns[p].stability,
                    patterns[p].peak_vorticity,
                    patterns[p].avg_vorticity,
                    patterns[p].persistence_count);
        }
    }
    
    fclose(csv);
    
    // Summary JSON
    FILE* json = fopen("resonance_summary.json", "w");
    if (!json) return;
    
    int active_count = 0;
    int resonant_count = 0;  // Patterns with lifetime > MIN_LIFETIME
    
    for (int p = 0; p < n_patterns; p++) {
        if (patterns[p].active) active_count++;
        if (patterns[p].active && patterns[p].lifetime >= MIN_LIFETIME) resonant_count++;
    }
    
    fprintf(json, "{\n");
    fprintf(json, "  \"current_step\": %llu,\n", current_step);
    fprintf(json, "  \"total_patterns\": %d,\n", n_patterns);
    fprintf(json, "  \"active_patterns\": %d,\n", active_count);
    fprintf(json, "  \"resonant_patterns\": %d,\n", resonant_count);
    fprintf(json, "  \"min_lifetime\": %d,\n", MIN_LIFETIME);
    fprintf(json, "  \"vorticity_threshold\": %.6e\n", VORTICITY_THRESHOLD);
    fprintf(json, "}\n");
    
    fclose(json);
}

/* ======================================================================== */
/*   M A I N   T E S T                                                      */
/* ======================================================================== */

int main() {
    printf("=======================================================================\n");
    printf("  RESONANCE TRACKER - LTP (Long-Term Potentiation) Metrics\n");
    printf("  Fractal Brain: Resonance = Connection strengthening\n");
    printf("=======================================================================\n\n");
    
    printf("RESONANCE DEFINITION:\n");
    printf("  LTP (Long-Term Potentiation): Connection gets stronger with use\n");
    printf("  Metrics: Lifetime, Coherence, Growth Rate, Stability\n");
    printf("  Threshold: |ω| > %.6e, Min Lifetime: %d steps\n\n", 
           VORTICITY_THRESHOLD, MIN_LIFETIME);
    
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
    float *h_ux, *h_uy, *h_vorticity, *h_rho;
    
    cudaMalloc(&f0, Q * NN * sizeof(float));
    cudaMalloc(&f1, Q * NN * sizeof(float));
    cudaMalloc(&rho, NN * sizeof(float));
    cudaMalloc(&ux, NN * sizeof(float));
    cudaMalloc(&uy, NN * sizeof(float));
    cudaMalloc(&vorticity, NN * sizeof(float));
    
    h_ux = (float*)malloc(NN * sizeof(float));
    h_uy = (float*)malloc(NN * sizeof(float));
    h_vorticity = (float*)malloc(NN * sizeof(float));
    h_rho = (float*)malloc(NN * sizeof(float));
    
    // Initialize
    float* h_f0 = (float*)malloc(Q * NN * sizeof(float));
    for (int i = 0; i < Q * NN; i++) {
        h_f0[i] = 1.0f + 0.01f * (rand() / (float)RAND_MAX - 0.5f);
    }
    cudaMemcpy(f0, h_f0, Q * NN * sizeof(float), cudaMemcpyHostToDevice);
    free(h_f0);
    
    // Prepare telemetry
    FILE* telemetry = fopen("resonance_telemetry.csv", "w");
    fprintf(telemetry, "step,power_w,steps_per_sec,active_patterns,resonant_patterns,avg_lifetime,avg_coherence\n");
    
    auto t0 = std::chrono::steady_clock::now();
    uint64_t total_steps = 0;
    int cur = 0;
    
    printf("\n[EXPERIMENT] Tracking resonance patterns...\n");
    printf("  Steps   | Power | Active | Resonant | Steps/sec | Avg Lifetime\n");
    printf("  --------|-------|--------|----------|-----------|-------------\n");
    
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
        
        // Compute vorticity and update patterns every 5k steps
        if (total_steps % 5000 == 0) {
            compute_vorticity_map<<<GBLK(NN), BLOCK>>>(ux, uy, vorticity, NX, NY);
            cudaDeviceSynchronize();
            
            // Copy to host
            cudaMemcpy(h_ux, ux, NN * sizeof(float), cudaMemcpyDeviceToHost);
            cudaMemcpy(h_uy, uy, NN * sizeof(float), cudaMemcpyDeviceToHost);
            cudaMemcpy(h_vorticity, vorticity, NN * sizeof(float), cudaMemcpyDeviceToHost);
            cudaMemcpy(h_rho, rho, NN * sizeof(float), cudaMemcpyDeviceToHost);
            
            update_resonance_patterns(h_vorticity, h_ux, h_uy, h_rho, total_steps);
        }
        
        // Report every 10k steps
        if (total_steps % SAMPLE_INTERVAL == 0) {
            nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
            float power_W = power_mW / 1000.0f;
            
            auto t_now = std::chrono::steady_clock::now();
            double elapsed = std::chrono::duration<double>(t_now - t0).count();
            float steps_per_sec = total_steps / elapsed;
            
            // Calculate resonance statistics
            int active_count = 0;
            int resonant_count = 0;
            uint64_t total_lifetime = 0;
            float total_coherence = 0.0f;
            
            for (int p = 0; p < n_patterns; p++) {
                if (patterns[p].active) {
                    active_count++;
                    total_lifetime += patterns[p].lifetime;
                    total_coherence += patterns[p].coherence;
                    
                    if (patterns[p].lifetime >= MIN_LIFETIME) {
                        resonant_count++;
                    }
                }
            }
            
            float avg_lifetime = (active_count > 0) ? (float)total_lifetime / active_count : 0.0f;
            float avg_coherence = (active_count > 0) ? total_coherence / active_count : 0.0f;
            
            fprintf(telemetry, "%llu,%.1f,%.0f,%d,%d,%.0f,%.3f\n",
                    total_steps, power_W, steps_per_sec, active_count, resonant_count,
                    avg_lifetime, avg_coherence);
            
            printf("  %7llu | %5.0f | %6d | %8d | %8.0f | %11.0f\n",
                   total_steps, power_W, active_count, resonant_count, 
                   steps_per_sec, avg_lifetime);
            
            // Save detailed metrics every 50k steps
            if (total_steps % 50000 == 0) {
                save_resonance_metrics(total_steps);
            }
        }
        
        // Check time limit (2 minutes)
        auto t_now = std::chrono::steady_clock::now();
        double elapsed = std::chrono::duration<double>(t_now - t0).count();
        if (elapsed > 120.0) {  // 2 minutes
            printf("\n[TIME] 2 minutes reached\n");
            break;
        }
    }
    
    auto t_end = std::chrono::steady_clock::now();
    double runtime = std::chrono::duration<double>(t_end - t0).count();
    
    // Final results
    printf("\n=======================================================================\n");
    printf("  RESONANCE TRACKER - FINAL METRICS\n");
    printf("=======================================================================\n");
    
    printf("\nEXPERIMENT SUMMARY:\n");
    printf("  Total steps:    %llu\n", total_steps);
    printf("  Runtime:        %.1f seconds (%.2f minutes)\n", runtime, runtime / 60.0);
    printf("  Steps/sec:      %.0f\n", total_steps / runtime);
    
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("  Final power:    %.1f W\n", power_mW / 1000.0f);
    
    // Final resonance statistics
    int active_count = 0;
    int resonant_count = 0;
    uint64_t total_lifetime = 0;
    float total_coherence = 0.0f;
    float total_growth = 0.0f;
    float total_stability = 0.0f;
    
    for (int p = 0; p < n_patterns; p++) {
        if (patterns[p].active) {
            active_count++;
            total_lifetime += patterns[p].lifetime;
            total_coherence += patterns[p].coherence;
            total_growth += patterns[p].growth_rate;
            total_stability += patterns[p].stability;
            
            if (patterns[p].lifetime >= MIN_LIFETIME) {
                resonant_count++;
            }
        }
    }
    
    printf("\nRESONANCE METRICS:\n");
    printf("  Total patterns:     %d\n", n_patterns);
    printf("  Active patterns:    %d\n", active_count);
    printf("  Resonant patterns:  %d (lifetime >= %d steps)\n", resonant_count, MIN_LIFETIME);
    
    if (active_count > 0) {
        printf("  Avg lifetime:       %.0f steps\n", (float)total_lifetime / active_count);
        printf("  Avg coherence:      %.3f (0-1)\n", total_coherence / active_count);
        printf("  Avg growth rate:    %.3e mass/step\n", total_growth / active_count);
        printf("  Avg stability:      %.3f (0-1)\n", total_stability / active_count);
    }
    
    printf("\nRESONANCE CLASSIFICATION:\n");
    if (resonant_count > 0) {
        printf("  ✅ RESONANCE DETECTED: %d patterns show LTP\n", resonant_count);
        printf("     Patterns strengthen with repeated activation\n");
    } else if (active_count > 0) {
        printf("  ⚠️  PATTERNS DETECTED: %d patterns, but none resonant yet\n", active_count);
        printf("     Need more time for LTP development\n");
    } else {
        printf("  ⚠️  NO PATTERNS DETECTED: Threshold may need adjustment\n");
        printf("     Try lower vorticity threshold or longer runtime\n");
    }
    
    // Save final metrics
    save_resonance_metrics(total_steps);
    
    printf("\nOUTPUT FILES:\n");
    printf("  resonance_telemetry.csv  - Time-series telemetry\n");
    printf("  resonance_metrics.csv    - Detailed pattern metrics\n");
    printf("  resonance_summary.json   - Summary statistics\n");
    
    printf("\nANALYSIS:\n");
    printf("  Resonance (LTP) requires:\n");
    printf("  1. Pattern detection (vorticity > threshold)\n");
    printf("  2. Persistence (lifetime > %d steps)\n", MIN_LIFETIME);
    printf("  3. Coherence (organized structure)\n");
    printf("  4. Growth (mass/energy accumulation)\n");
    
    // Cleanup
    fclose(telemetry);
    cudaFree(f0); cudaFree(f1);
    cudaFree(rho); cudaFree(ux); cudaFree(uy); cudaFree(vorticity);
    free(h_ux); free(h_uy); free(h_vorticity); free(h_rho);
    nvmlShutdown();
    
    return 0;
}