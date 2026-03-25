/* ============================================================================
 * PLASTICITY TRACKER - Nodal Growth Metrics
 * Fractal Brain Cheat Sheet: Nodal Growth = Plasticity
 * = Grid's ability to reshape itself to find a "cooler" path
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

#define TOTAL_STEPS      300000     // ~1 minute
#define STEPS_PER_BATCH  500
#define SAMPLE_INTERVAL  10000

#define OMEGA  1.0f

/* ---- Plasticity Parameters --------------------------------------------- */
#define PLASTICITY_RATE   0.001f    // How fast connections adapt
#define MIN_STRENGTH      0.1f      // Minimum connection strength
#define MAX_STRENGTH      5.0f      // Maximum connection strength
#define ADAPTATION_WINDOW 1000      // Steps for adaptation measurement

/* ---- Connection Structure ---------------------------------------------- */
typedef struct {
    float strength[Q];      // Connection strength for each direction
    float usage[Q];         // How much each direction is used
    float efficiency;       // Current flow efficiency (0-1)
    float last_adaptation;  // When last adapted
    float plasticity;       // Current plasticity level (0-1)
} NodeConnections;

NodeConnections* connections = nullptr;  // Will allocate on host

/* ---- Plasticity Metrics ------------------------------------------------ */
float total_plasticity = 0.0f;           // Sum of all node plasticity
float avg_adaptation_rate = 0.0f;        // Average adaptation rate
float grid_efficiency = 0.0f;            // Overall grid efficiency
float structural_change = 0.0f;          // How much grid has changed

/* ---- D2Q9 --------------------------------------------------------------- */
__constant__ int   d_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
__constant__ int   d_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
__constant__ float d_w[Q]  = { 4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9,
                               1.f/36,1.f/36,1.f/36,1.f/36 };

/* ======================================================================== */
/*   K E R N E L S                                                          */
/* ======================================================================== */

/* ---- LBM collide & stream with plasticity ----------------------------- */
__global__ void lbm_collide_stream_plastic(const float* __restrict__ f_src,
                                           float* __restrict__ f_dst,
                                           float* __restrict__ rho,
                                           float* __restrict__ ux,
                                           float* __restrict__ uy,
                                           float* __restrict__ strength,
                                           float* __restrict__ usage,
                                           float omega, int nx, int ny) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N = nx * ny;
    if (idx >= N) return;
    const int x = idx % nx, y = idx / nx;

    float fl[Q];
    float total_strength = 0.0f;
    
    // Apply connection strengths
    for (int i = 0; i < Q; i++) {
        int sx = (x - d_ex[i] + nx) % nx;
        int sy = (y - d_ey[i] + ny) % ny;
        float s = strength[i * N + sy * nx + sx];
        fl[i] = f_src[i * N + sy * nx + sx] * s;
        total_strength += s;
    }
    
    // Normalize by total strength
    if (total_strength > 0.0f) {
        float inv = 1.0f / total_strength;
        for (int i = 0; i < Q; i++) {
            fl[i] *= inv;
        }
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
        
        // Track usage (how much this direction is used)
        float usage_val = fabsf(fl[i] - feq);
        atomicAdd(&usage[i * N + idx], usage_val);
    }
}

/* ---- Update connection strengths (plasticity) ------------------------- */
__global__ void update_plasticity(float* strength, float* usage, 
                                  float plasticity_rate, int nx, int ny) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N = nx * ny;
    if (idx >= N) return;
    
    // Find most used direction
    float max_usage = 0.0f;
    int best_dir = 0;
    float total_usage = 0.0f;
    
    for (int i = 0; i < Q; i++) {
        float u = usage[i * N + idx];
        total_usage += u;
        if (u > max_usage) {
            max_usage = u;
            best_dir = i;
        }
    }
    
    // Strengthen most used direction, weaken others
    if (total_usage > 0.0f) {
        for (int i = 0; i < Q; i++) {
            float current = strength[i * N + idx];
            if (i == best_dir) {
                // Strengthen
                strength[i * N + idx] = fminf(current + plasticity_rate, MAX_STRENGTH);
            } else {
                // Weaken
                strength[i * N + idx] = fmaxf(current - plasticity_rate * 0.1f, MIN_STRENGTH);
            }
        }
    }
    
    // Reset usage for next measurement window
    for (int i = 0; i < Q; i++) {
        usage[i * N + idx] = 0.0f;
    }
}

/* ======================================================================== */
/*   P L A S T I C I T Y   M E T R I C S                                    */
/* ======================================================================== */

void calculate_plasticity_metrics(float* h_strength, float* initial_strength, 
                                  uint64_t current_step, int adaptation_cycles) {
    if (adaptation_cycles == 0) return;
    
    float total_change = 0.0f;
    float total_efficiency = 0.0f;
    int adaptive_nodes = 0;
    
    for (int idx = 0; idx < NN; idx++) {
        float node_change = 0.0f;
        float node_efficiency = 0.0f;
        float max_strength = 0.0f;
        float strength_sum = 0.0f;
        
        for (int i = 0; i < Q; i++) {
            float current = h_strength[i * NN + idx];
            float initial = initial_strength[i * NN + idx];
            float change = fabsf(current - initial);
            
            node_change += change;
            node_efficiency += current * d_w[i];  // Weight by lattice weight
            strength_sum += current;
            
            if (current > max_strength) max_strength = current;
        }
        
        total_change += node_change / Q;  // Average per direction
        total_efficiency += (max_strength / strength_sum);  // Directionality efficiency
        
        // Count adaptive nodes (significant change)
        if (node_change / Q > 0.1f) {
            adaptive_nodes++;
        }
    }
    
    // Update global metrics
    structural_change = total_change / NN;
    grid_efficiency = total_efficiency / NN;
    avg_adaptation_rate = structural_change / adaptation_cycles;
    total_plasticity = (float)adaptive_nodes / NN;  // Percentage of adaptive nodes
    
    // Update node connections on host
    for (int idx = 0; idx < NN; idx++) {
        connections[idx].plasticity = 0.0f;
        connections[idx].efficiency = 0.0f;
        
        for (int i = 0; i < Q; i++) {
            connections[idx].strength[i] = h_strength[i * NN + idx];
            connections[idx].efficiency += h_strength[i * NN + idx] * d_w[i];
        }
        
        // Calculate node plasticity (how much it has changed recently)
        float node_change = 0.0f;
        for (int i = 0; i < Q; i++) {
            float initial = initial_strength[i * NN + idx];
            float current = h_strength[i * NN + idx];
            node_change += fabsf(current - initial);
        }
        connections[idx].plasticity = node_change / Q;
        connections[idx].last_adaptation = node_change;
    }
}

/* ---- Save Plasticity Metrics ------------------------------------------ */
void save_plasticity_metrics(uint64_t current_step, int adaptation_cycles) {
    // Summary CSV
    FILE* csv = fopen("plasticity_summary.csv", "w");
    if (!csv) return;
    
    fprintf(csv, "step,structural_change,grid_efficiency,adaptation_rate,total_plasticity,adaptive_nodes,adaptation_cycles\n");
    fprintf(csv, "%llu,%.6f,%.6f,%.6f,%.6f,%d,%d\n",
            current_step, structural_change, grid_efficiency, 
            avg_adaptation_rate, total_plasticity, 
            (int)(total_plasticity * NN), adaptation_cycles);
    fclose(csv);
    
    // Detailed node metrics (sample every 100th node)
    FILE* detail = fopen("plasticity_nodes.csv", "w");
    if (!detail) return;
    
    fprintf(detail, "node_id,x,y,plasticity,efficiency,avg_strength,max_strength,strength_variance\n");
    
    for (int idx = 0; idx < NN; idx += 100) {  // Sample 1% of nodes
        int x = idx % NX;
        int y = idx / NX;
        
        float avg_strength = 0.0f;
        float max_strength = 0.0f;
        float variance = 0.0f;
        
        for (int i = 0; i < Q; i++) {
            float s = connections[idx].strength[i];
            avg_strength += s;
            if (s > max_strength) max_strength = s;
        }
        avg_strength /= Q;
        
        for (int i = 0; i < Q; i++) {
            float diff = connections[idx].strength[i] - avg_strength;
            variance += diff * diff;
        }
        variance /= Q;
        
        fprintf(detail, "%d,%d,%d,%.6f,%.6f,%.6f,%.6f,%.6f\n",
                idx, x, y, connections[idx].plasticity, 
                connections[idx].efficiency, avg_strength, max_strength, variance);
    }
    fclose(detail);
    
    // JSON summary
    FILE* json = fopen("plasticity_metrics.json", "w");
    if (!json) return;
    
    fprintf(json, "{\n");
    fprintf(json, "  \"current_step\": %llu,\n", current_step);
    fprintf(json, "  \"structural_change\": %.6f,\n", structural_change);
    fprintf(json, "  \"grid_efficiency\": %.6f,\n", grid_efficiency);
    fprintf(json, "  \"adaptation_rate\": %.6f,\n", avg_adaptation_rate);
    fprintf(json, "  \"total_plasticity\": %.6f,\n", total_plasticity);
    fprintf(json, "  \"adaptive_nodes\": %d,\n", (int)(total_plasticity * NN));
    fprintf(json, "  \"adaptation_cycles\": %d,\n", adaptation_cycles);
    fprintf(json, "  \"plasticity_rate\": %.6f\n", PLASTICITY_RATE);
    fprintf(json, "}\n");
    fclose(json);
}

/* ======================================================================== */
/*   M A I N   T E S T                                                      */
/* ======================================================================== */

int main() {
    printf("=======================================================================\n");
    printf("  PLASTICITY TRACKER - Nodal Growth Metrics\n");
    printf("  Fractal Brain: Plasticity = Grid reshaping to find cooler path\n");
    printf("=======================================================================\n\n");
    
    printf("PLASTICITY DEFINITION:\n");
    printf("  Nodal Growth = Grid's ability to reshape itself\n");
    printf("  Goal: Find \"cooler\" paths (lower resistance, more efficient)\n");
    printf("  Rate: %.6f per adaptation cycle\n\n", PLASTICITY_RATE);
    
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
    float *strength, *usage;
    float *h_strength, *initial_strength;
    
    cudaMalloc(&f0, Q * NN * sizeof(float));
    cudaMalloc(&f1, Q * NN * sizeof(float));
    cudaMalloc(&rho, NN * sizeof(float));
    cudaMalloc(&ux, NN * sizeof(float));
    cudaMalloc(&uy, NN * sizeof(float));
    cudaMalloc(&strength, Q * NN * sizeof(float));
    cudaMalloc(&usage, Q * NN * sizeof(float));
    
    h_strength = (float*)malloc(Q * NN * sizeof(float));
    initial_strength = (float*)malloc(Q * NN * sizeof(float));
    
    // Allocate host connections
    connections = (NodeConnections*)malloc(NN * sizeof(NodeConnections));
    
    // Initialize distribution
    float* h_f0 = (float*)malloc(Q * NN * sizeof(float));
    for (int i = 0; i < Q * NN; i++) {
        h_f0[i] = 1.0f + 0.01f * (rand() / (float)RAND_MAX - 0.5f);
    }
    cudaMemcpy(f0, h_f0, Q * NN * sizeof(float), cudaMemcpyHostToDevice);
    free(h_f0);
    
    // Initialize connection strengths (uniform)
    for (int i = 0; i < Q * NN; i++) {
        h_strength[i] = 1.0f;  // Start with uniform strength
        initial_strength[i] = 1.0f;
    }
    cudaMemcpy(strength, h_strength, Q * NN * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemset(usage, 0, Q * NN * sizeof(float));
    
    // Initialize node connections
    for (int idx = 0; idx < NN; idx++) {
        for (int i = 0; i < Q; i++) {
            connections[idx].strength[i] = 1.0f;
            connections[idx].usage[i] = 0.0f;
        }
        connections[idx].efficiency = 1.0f;
        connections[idx].last_adaptation = 0.0f;
        connections[idx].plasticity = 0.0f;
    }
    
    // Prepare telemetry
    FILE* telemetry = fopen("plasticity_telemetry.csv", "w");
    fprintf(telemetry, "step,power_w,steps_per_sec,structural_change,grid_efficiency,adaptation_rate,total_plasticity\n");
    
    auto t0 = std::chrono::steady_clock::now();
    uint64_t total_steps = 0;
    int cur = 0;
    int adaptation_cycles = 0;
    
    printf("\n[EXPERIMENT] Tracking plasticity (nodal growth)...\n");
    printf("  Steps   | Power | Steps/sec | Structure | Efficiency | Plasticity\n");
    printf("  --------|-------|-----------|-----------|------------|------------\n");
    
    int batches = TOTAL_STEPS / STEPS_PER_BATCH;
    
    for (int batch = 0; batch < batches; batch++) {
        // Run LBM steps with plasticity
        for (int s = 0; s < STEPS_PER_BATCH; s++) {
            lbm_collide_stream_plastic<<<GBLK(NN), BLOCK>>>(
                (cur == 0) ? f0 : f1,
                (cur == 0) ? f1 : f0,
                rho, ux, uy, strength, usage, OMEGA, NX, NY);
            cudaDeviceSynchronize();
            cur = 1 - cur;
        }
        total_steps += STEPS_PER_BATCH;
        
        // Update plasticity every ADAPTATION_WINDOW steps
        if (total_steps % ADAPTATION_WINDOW == 0) {
            update_plasticity<<<GBLK(NN), BLOCK>>>(strength, usage, PLASTICITY_RATE, NX, NY);
            cudaDeviceSynchronize();
            adaptation_cycles++;
            
            // Copy strengths back to host for metrics
            cudaMemcpy(h_strength, strength, Q * NN * sizeof(float), cudaMemcpyDeviceToHost);
            calculate_plasticity_metrics(h_strength, initial_strength, total_steps, adaptation_cycles);
        }
        
        // Report every SAMPLE_INTERVAL steps
        if (total_steps % SAMPLE_INTERVAL == 0) {
            nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
            float power_W = power_mW / 1000.0f;
            
            auto t_now = std::chrono::steady_clock::now();
            double elapsed = std::chrono::duration<double>(t_now - t0).count();
            float steps_per_sec = total_steps / elapsed;
            
            fprintf(telemetry, "%llu,%.1f,%.0f,%.6f,%.6f,%.6f,%.6f\n",
                    total_steps, power_W, steps_per_sec, structural_change,
                    grid_efficiency, avg_adaptation_rate, total_plasticity);
            
            printf("  %7llu | %5.0f | %9.0f | %9.6f | %10.6f | %10.6f\n",
                   total_steps, power_W, steps_per_sec, structural_change,
                   grid_efficiency, total_plasticity);
            
            // Save detailed metrics every 50k steps
            if (total_steps % 50000 == 0) {
                save_plasticity_metrics(total_steps, adaptation_cycles);
            }
        }
        
        // Check time limit (1 minute)
        auto t_now = std::chrono::steady_clock::now();
        double elapsed = std::chrono::duration<double>(t_now - t0).count();
        if (elapsed > 60.0) {
            printf("\n[TIME] 1 minute reached\n");
            break;
        }
    }
    
    auto t_end = std::chrono::steady_clock::now();
    double runtime = std::chrono::duration<double>(t_end - t0).count();
    
    // Final results
    printf("\n=======================================================================\n");
    printf("  PLASTICITY TRACKER - FINAL METRICS\n");
    printf("=======================================================================\n");
    
    printf("\nEXPERIMENT SUMMARY:\n");
    printf("  Total steps:    %llu\n", total_steps);
    printf("  Runtime:        %.1f seconds (%.2f minutes)\n", runtime, runtime / 60.0);
    printf("  Steps/sec:      %.0f\n", total_steps / runtime);
    printf("  Adaptation cycles: %d\n", adaptation_cycles);
    
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("  Final power:    %.1f W\n", power_mW / 1000.0f);
    
    printf("\nPLASTICITY METRICS:\n");
    printf("  Structural change:  %.6f (0-1 scale)\n", structural_change);
    printf("  Grid efficiency:    %.6f (0-1 scale)\n", grid_efficiency);
    printf("  Adaptation rate:    %.6f change/cycle\n", avg_adaptation_rate);
    printf("  Total plasticity:   %.6f (%% of adaptive nodes)\n", total_plasticity);
    printf("  Adaptive nodes:     %d / %d\n", (int)(total_plasticity * NN), NN);
    
    printf("\nPLASTICITY CLASSIFICATION:\n");
    if (structural_change > 0.5f) {
        printf("  ✅ HIGH PLASTICITY: Grid significantly reshaped\n");
        printf("     Strong nodal growth and adaptation\n");
    } else if (structural_change > 0.1f) {
        printf("  ⚠️  MODERATE PLASTICITY: Some grid adaptation\n");
        printf("     Moderate nodal growth\n");
    } else {
        printf("  ⚠️  LOW PLASTICITY: Limited grid adaptation\n");
        printf("     May need higher plasticity rate or longer runtime\n");
    }
    
    if (grid_efficiency > 0.7f) {
        printf("  ✅ HIGH EFFICIENCY: Grid found \"cooler\" paths\n");
        printf("     Effective adaptation to flow patterns\n");
    } else if (grid_efficiency > 0.4f) {
        printf("  ⚠️  MODERATE EFFICIENCY: Some path optimization\n");
    } else {
        printf("  ⚠️  LOW EFFICIENCY: Limited path optimization\n");
        printf("     Grid not effectively finding cooler paths\n");
    }
    
    // Save final metrics
    save_plasticity_metrics(total_steps, adaptation_cycles);
    
    printf("\nOUTPUT FILES:\n");
    printf("  plasticity_telemetry.csv - Time-series telemetry\n");
    printf("  plasticity_summary.csv   - Summary metrics\n");
    printf("  plasticity_nodes.csv     - Detailed node metrics (1%% sample)\n");
    printf("  plasticity_metrics.json  - JSON summary\n");
    
    printf("\nANALYSIS:\n");
    printf("  Plasticity (Nodal Growth) measures:\n");
    printf("  1. Structural change: How much grid reshapes\n");
    printf("  2. Grid efficiency: How well it finds \"cooler\" paths\n");
    printf("  3. Adaptation rate: Speed of change\n");
    printf("  4. Adaptive nodes: Percentage of nodes that change\n");
    
    // Cleanup
    fclose(telemetry);
    cudaFree(f0); cudaFree(f1);
    cudaFree(rho); cudaFree(ux); cudaFree(uy);
    cudaFree(strength); cudaFree(usage);
    free(h_strength); free(initial_strength);
    free(connections);
    nvmlShutdown();
    
    return 0;
}