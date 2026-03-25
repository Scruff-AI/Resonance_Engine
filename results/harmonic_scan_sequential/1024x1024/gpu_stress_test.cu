/* ============================================================================
 * GPU STRESS TEST - Simple LBM to verify GPU utilization
 * ============================================================================ */

#include <cuda_runtime.h>
#include <cstdio>
#include <cstdlib>
#include <chrono>

#define NX 1024
#define NY 1024
#define NN (NX * NY)
#define Q 9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

__constant__ int d_ex[9] = {0, 1, 0, -1, 0, 1, -1, -1, 1};
__constant__ int d_ey[9] = {0, 0, 1, 0, -1, 1, 1, -1, -1};
__constant__ float d_w[9] = {4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/36, 1.f/36, 1.f/36, 1.f/36};

__global__ void lbm_kernel(float* f_src, float* f_dst, float omega) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N = NX * NY;
    if (idx >= N) return;
    
    const int x = idx % NX;
    const int y = idx / NX;
    
    float fl[9];
    for (int i = 0; i < 9; i++) {
        int sx = (x - d_ex[i] + NX) % NX;
        int sy = (y - d_ey[i] + NY) % NY;
        fl[i] = f_src[i * N + sy * NX + sx];
    }
    
    float rho = 0.f, ux = 0.f, uy = 0.f;
    for (int i = 0; i < 9; i++) {
        rho += fl[i];
        ux += (float)d_ex[i] * fl[i];
        uy += (float)d_ey[i] * fl[i];
    }
    
    float inv = 1.f / fmaxf(rho, 1e-10f);
    ux *= inv;
    uy *= inv;
    
    const float u2 = ux * ux + uy * uy;
    for (int i = 0; i < 9; i++) {
        float eu = (float)d_ex[i] * ux + (float)d_ey[i] * uy;
        float feq = d_w[i] * rho * (1.f + 3.f * eu + 4.5f * eu * eu - 1.5f * u2);
        f_dst[i * N + idx] = fl[i] - omega * (fl[i] - feq);
    }
}

int main() {
    printf("=== GPU STRESS TEST ===\n");
    printf("Grid: %dx%d (%d cells)\n", NX, NY, NN);
    printf("Testing GPU utilization...\n\n");
    
    // Allocate memory
    float *f1, *f2;
    cudaMallocManaged(&f1, Q * NN * sizeof(float));
    cudaMallocManaged(&f2, Q * NN * sizeof(float));
    
    // Initialize
    for (int i = 0; i < Q * NN; i++) {
        f1[i] = 1.0f + 0.01f * (rand() / (float)RAND_MAX - 0.5f);
    }
    
    cudaDeviceSynchronize();
    
    // Run test for 10 seconds
    auto start = std::chrono::steady_clock::now();
    auto end = start + std::chrono::seconds(10);
    
    long long steps = 0;
    int iterations = 0;
    
    printf("Running for 10 seconds...\n");
    
    while (std::chrono::steady_clock::now() < end) {
        // Run 1000 LBM steps
        for (int i = 0; i < 1000; i++) {
            lbm_kernel<<<GBLK(NN), BLOCK>>>(f1, f2, 1.85f);
            cudaDeviceSynchronize();
            std::swap(f1, f2);
            steps++;
        }
        iterations++;
        
        if (iterations % 10 == 0) {
            auto now = std::chrono::steady_clock::now();
            auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - start).count();
            float steps_per_sec = (steps * 1000.0f) / elapsed;
            printf("  Steps: %lld (%.0f steps/sec)\n", steps, steps_per_sec);
        }
    }
    
    auto total_time = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start).count();
    
    float avg_steps_per_sec = (steps * 1000.0f) / total_time;
    
    printf("\n=== RESULTS ===\n");
    printf("Total steps: %lld\n", steps);
    printf("Total time: %.1f seconds\n", total_time / 1000.0f);
    printf("Average: %.0f steps/sec\n", avg_steps_per_sec);
    printf("Theoretical max (RTX 4090): ~500,000 steps/sec\n");
    printf("\nGPU should be at >90%% utilization if working correctly.\n");
    
    cudaFree(f1);
    cudaFree(f2);
    
    return 0;
}