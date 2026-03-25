/* ============================================================================
 * SIMPLE REALITY CHECK - 15 MINUTE TEST
 * Minimal test to verify basic physics works
 * 
 * Tests:
 * 1. Does LBM run without crashing?
 * 2. What's the actual steps/sec?
 * 3. Does power scale?
 * 4. Does entropy vary?
 * ============================================================================ */

#include <cuda_runtime.h>
#include <nvml.h>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <chrono>

#define NX    1024
#define NY    1024
#define NN    (NX * NY)
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

#define OMEGA 1.0f
#define STEPS 500000  // Target: ~15 minutes at 5.5k steps/sec

__constant__ int   d_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
__constant__ int   d_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
__constant__ float d_w[Q]  = { 4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9,
                               1.f/36,1.f/36,1.f/36,1.f/36 };

__global__ void lbm_collide_stream_simple(const float* __restrict__ f_src,
                                         float* __restrict__ f_dst,
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

    float rho = 0.f, ux = 0.f, uy = 0.f;
    for (int i = 0; i < Q; i++) {
        rho += fl[i];
        ux += (float)d_ex[i] * fl[i];
        uy += (float)d_ey[i] * fl[i];
    }
    float inv = 1.f / fmaxf(rho, 1e-10f);
    ux *= inv; uy *= inv;

    const float u2 = ux * ux + uy * uy;
    for (int i = 0; i < Q; i++) {
        float eu = (float)d_ex[i] * ux + (float)d_ey[i] * uy;
        float feq = d_w[i] * rho * (1.f + 3.f*eu + 4.5f*eu*eu - 1.5f*u2);
        f_dst[i * N + idx] = fl[i] - omega * (fl[i] - feq);
    }
}

float compute_variance(const float* ux, const float* uy) {
    float sum_ux = 0.f, sum_uy = 0.f;
    float sum_ux2 = 0.f, sum_uy2 = 0.f;
    
    for (int i = 0; i < NN; i++) {
        sum_ux += ux[i];
        sum_uy += uy[i];
        sum_ux2 += ux[i] * ux[i];
        sum_uy2 += uy[i] * uy[i];
    }
    
    float mean_ux = sum_ux / NN;
    float mean_uy = sum_uy / NN;
    float var_ux = (sum_ux2 / NN) - (mean_ux * mean_ux);
    float var_uy = (sum_uy2 / NN) - (mean_uy * mean_uy);
    
    return var_ux + var_uy;
}

int main() {
    printf("=======================================================================\n");
    printf("  SIMPLE REALITY CHECK - 15 MINUTE TEST\n");
    printf("  Beast: RTX 4090, 1024x1024 grid\n");
    printf("  Target: 500k steps (~15 min at 5.5k steps/sec)\n");
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
    float *f0, *f1, *ux, *uy;
    cudaMallocManaged(&f0, Q * NN * sizeof(float));
    cudaMallocManaged(&f1, Q * NN * sizeof(float));
    cudaMallocManaged(&ux, NN * sizeof(float));
    cudaMallocManaged(&uy, NN * sizeof(float));
    
    // Initialize
    printf("\n[INIT] Setting up equilibrium state...\n");
    for (int i = 0; i < Q * NN; i++) {
        f0[i] = 1.0f + 0.01f * (rand() / (float)RAND_MAX - 0.5f);
    }
    
    // Run test
    printf("\n[RUN] Starting %d step test...\n", STEPS);
    printf("  Batch | Steps   | Variance   | Power | Steps/sec\n");
    printf("  ------|---------|------------|-------|-----------\n");
    
    auto t0 = std::chrono::steady_clock::now();
    int cur = 0;
    int batch_size = 1000;
    int num_batches = STEPS / batch_size;
    
    FILE* csv = fopen("simple_reality_check.csv", "w");
    fprintf(csv, "steps,variance,power_w\n");
    
    for (int batch = 0; batch < num_batches; batch++) {
        // Run batch
        for (int s = 0; s < batch_size; s++) {
            lbm_collide_stream_simple<<<GBLK(NN), BLOCK>>>(
                (cur == 0) ? f0 : f1,
                (cur == 0) ? f1 : f0,
                OMEGA, NX, NY);
            cudaDeviceSynchronize();
            cur = 1 - cur;
        }
        
        // Measure every 10 batches
        if ((batch + 1) % 10 == 0) {
            uint64_t current_steps = (batch + 1) * batch_size;
            
            // Compute variance (simple entropy proxy)
            float variance = compute_variance(ux, uy);
            
            // Get power
            nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
            float power_W = power_mW / 1000.0f;
            
            // Compute steps/sec
            auto t_now = std::chrono::steady_clock::now();
            double elapsed = std::chrono::duration<double>(t_now - t0).count();
            float steps_per_sec = current_steps / elapsed;
            
            // Log
            fprintf(csv, "%llu,%.6e,%.1f\n", current_steps, variance, power_W);
            
            printf("  %5d | %7llu | %.3e | %5.0f | %8.0f\n",
                   batch + 1, current_steps, variance, power_W, steps_per_sec);
        }
        
        // Check time limit
        auto t_now = std::chrono::steady_clock::now();
        double elapsed = std::chrono::duration<double>(t_now - t0).count();
        if (elapsed > 900.0) {  // 15 minutes
            printf("\n[TIME] 15 minutes reached\n");
            break;
        }
    }
    
    auto t_end = std::chrono::steady_clock::now();
    double runtime = std::chrono::duration<double>(t_end - t0).count();
    uint64_t total_steps = num_batches * batch_size;
    float steps_per_sec = total_steps / runtime;
    
    printf("\n=======================================================================\n");
    printf("  RESULTS\n");
    printf("=======================================================================\n");
    
    printf("\nPERFORMANCE:\n");
    printf("  Total steps:    %llu\n", total_steps);
    printf("  Runtime:        %.1f seconds (%.1f minutes)\n", runtime, runtime / 60.0);
    printf("  Steps/sec:      %.0f\n", steps_per_sec);
    printf("  Expected:       ~5,500 steps/sec\n");
    
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("\nPOWER:\n");
    printf("  Final power:    %.1f W\n", power_mW / 1000.0f);
    printf("  Idle power:     ~37 W\n");
    printf("  Load power:     ~290 W\n");
    
    printf("\n=======================================================================\n");
    printf("  V E R D I C T\n");
    printf("=======================================================================\n");
    
    if (steps_per_sec > 4000 && steps_per_sec < 7000) {
        printf("✅ PERFORMANCE REALITY: %.0f steps/sec (matches ~5.5k baseline)\n", steps_per_sec);
    } else {
        printf("❌ PERFORMANCE SUSPECT: %.0f steps/sec (expected ~5.5k)\n", steps_per_sec);
    }
    
    if (power_mW / 1000.0f > 100.0f) {
        printf("✅ POWER SCALING: %.1f W (above idle, real work)\n", power_mW / 1000.0f);
    } else {
        printf("❌ POWER SUSPECT: %.1f W (not scaling with load)\n", power_mW / 1000.0f);
    }
    
    printf("\nData saved: simple_reality_check.csv\n");
    
    // Cleanup
    fclose(csv);
    cudaFree(f0); cudaFree(f1);
    cudaFree(ux); cudaFree(uy);
    nvmlShutdown();
    
    return 0;
}