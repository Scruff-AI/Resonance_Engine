/* ============================================================================
 * SEED BRAIN SIMPLE - Fixed Timing
 * Matches GTX 1050 performance (~5500 steps/sec)
 * ============================================================================ */

#include <cuda_runtime.h>
#include <nvml.h>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cmath>
#include <chrono>
#include <thread>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define SB_NX 512
#define SB_NY 512
#define SB_N  (SB_NX * SB_NY)
#define SB_Q  9
#define SB_TAU 0.7273f
#define SB_OMEGA (1.0f / SB_TAU)

#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

__constant__ int d_ex[SB_Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
__constant__ int d_ey[SB_Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
__constant__ float d_w[SB_Q] = { 4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/36,1.f/36,1.f/36,1.f/36 };

__global__ void lbm_step(const float* f_src, float* f_dst, float* rho, float* ux, float* uy, float omega, int nx, int ny) {
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

int main() {
    printf("Seed Brain Simple - Fixed Timing\n");
    printf("Target: ~5500 steps/sec (GTX 1050 speed)\n\n");
    
    // Allocate
    float *f0, *f1, *rho, *ux, *uy;
    cudaMalloc(&f0, SB_Q * SB_N * sizeof(float));
    cudaMalloc(&f1, SB_Q * SB_N * sizeof(float));
    cudaMalloc(&rho, SB_N * sizeof(float));
    cudaMalloc(&ux, SB_N * sizeof(float));
    cudaMalloc(&uy, SB_N * sizeof(float));
    
    // Initialize
    float* h_f = (float*)malloc(SB_Q * SB_N * sizeof(float));
    for (int i = 0; i < SB_Q * SB_N; i++) h_f[i] = 1.0f + 0.01f * (rand() / (float)RAND_MAX - 0.5f);
    cudaMemcpy(f0, h_f, SB_Q * SB_N * sizeof(float), cudaMemcpyHostToDevice);
    free(h_f);
    
    // Run with timing control
    auto t_start = std::chrono::steady_clock::now();
    uint64_t steps = 0;
    int cur = 0;
    
    // Target: 5500 steps/sec
    const float target_steps_per_sec = 5500.0f;
    const int batch_size = 100;
    
    printf("Running... (Ctrl+C to stop)\n");
    printf("Steps      | Steps/sec | Target\n");
    
    while (true) {
        auto batch_start = std::chrono::steady_clock::now();
        
        // Run batch
        for (int i = 0; i < batch_size; i++) {
            lbm_step<<<GBLK(SB_N), BLOCK>>>((cur == 0) ? f0 : f1, (cur == 0) ? f1 : f0, rho, ux, uy, SB_OMEGA, SB_NX, SB_NY);
            cudaDeviceSynchronize();
            cur = 1 - cur;
        }
        steps += batch_size;
        
        // Calculate timing
        auto batch_end = std::chrono::steady_clock::now();
        float batch_time = std::chrono::duration<float>(batch_end - batch_start).count();
        float current_rate = batch_size / batch_time;
        
        // Sleep to match target rate
        float target_time = batch_size / target_steps_per_sec;
        if (batch_time < target_time) {
            std::this_thread::sleep_for(std::chrono::microseconds((int)((target_time - batch_time) * 1000000)));
        }
        
        // Report every 10k steps
        if (steps % 10000 == 0) {
            printf("%10llu | %9.0f | %6.0f\n", steps, current_rate, target_steps_per_sec);
        }
        
        // Stop after 100k steps for test
        if (steps >= 100000) break;
    }
    
    auto t_end = std::chrono::steady_clock::now();
    float runtime = std::chrono::duration<float>(t_end - t_start).count();
    
    printf("\nCompleted: %llu steps in %.1f seconds\n", steps, runtime);
    printf("Actual rate: %.0f steps/sec\n", steps / runtime);
    printf("Target rate: %.0f steps/sec\n", target_steps_per_sec);
    
    cudaFree(f0); cudaFree(f1); cudaFree(rho); cudaFree(ux); cudaFree(uy);
    return 0;
}