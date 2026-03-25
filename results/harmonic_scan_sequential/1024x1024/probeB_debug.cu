/* ============================================================================
 * PROBE B DEBUG - Minimal test to identify runtime issues
 * ============================================================================ */

#include <cuda_runtime.h>
#include <nvml.h>
#include <cstdio>
#include <cstdlib>
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

#define OMEGA 1.0f
#define STEPS 100000  // Quick test

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

int main() {
    printf("=======================================================================\n");
    printf("  PROBE B DEBUG - Runtime Check\n");
    printf("=======================================================================\n\n");
    
    // Test 1: CUDA initialization
    printf("[TEST 1] CUDA initialization... ");
    cudaDeviceProp prop;
    cudaError_t cuda_err = cudaGetDeviceProperties(&prop, 0);
    if (cuda_err != cudaSuccess) {
        printf("FAILED: %s\n", cudaGetErrorString(cuda_err));
        return 1;
    }
    printf("OK (%s, SM %d.%d)\n", prop.name, prop.major, prop.minor);
    
    // Test 2: NVML initialization
    printf("[TEST 2] NVML initialization... ");
    nvmlReturn_t nvml_err = nvmlInit();
    if (nvml_err != NVML_SUCCESS) {
        printf("FAILED: %d\n", nvml_err);
    } else {
        printf("OK\n");
        nvmlDevice_t nvml_dev;
        nvml_err = nvmlDeviceGetHandleByIndex(0, &nvml_dev);
        if (nvml_err == NVML_SUCCESS) {
            unsigned int power_mW;
            nvml_err = nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
            if (nvml_err == NVML_SUCCESS) {
                printf("       Idle power: %.1f W\n", power_mW / 1000.0f);
            }
        }
        nvmlShutdown();
    }
    
    // Test 3: Memory allocation
    printf("[TEST 3] Memory allocation... ");
    float *f0, *f1;
    cuda_err = cudaMallocManaged(&f0, Q * NN * sizeof(float));
    if (cuda_err != cudaSuccess) {
        printf("FAILED (f0): %s\n", cudaGetErrorString(cuda_err));
        return 1;
    }
    cuda_err = cudaMallocManaged(&f1, Q * NN * sizeof(float));
    if (cuda_err != cudaSuccess) {
        printf("FAILED (f1): %s\n", cudaGetErrorString(cuda_err));
        cudaFree(f0);
        return 1;
    }
    printf("OK (%.1f MB allocated)\n", (Q * NN * sizeof(float) * 2) / (1024.0 * 1024.0));
    
    // Test 4: Kernel execution
    printf("[TEST 4] Kernel execution... ");
    
    // Initialize
    for (int i = 0; i < Q * NN; i++) {
        f0[i] = 1.0f + 0.01f * (rand() / (float)RAND_MAX - 0.5f);
    }
    
    // Run a few steps
    auto t0 = std::chrono::steady_clock::now();
    int cur = 0;
    int steps_to_run = 1000;
    
    for (int s = 0; s < steps_to_run; s++) {
        lbm_collide_stream_simple<<<GBLK(NN), BLOCK>>>(
            (cur == 0) ? f0 : f1,
            (cur == 0) ? f1 : f0,
            OMEGA, NX, NY);
        cuda_err = cudaDeviceSynchronize();
        if (cuda_err != cudaSuccess) {
            printf("FAILED at step %d: %s\n", s, cudaGetErrorString(cuda_err));
            cudaFree(f0); cudaFree(f1);
            return 1;
        }
        cur = 1 - cur;
    }
    
    auto t1 = std::chrono::steady_clock::now();
    double elapsed = std::chrono::duration<double>(t1 - t0).count();
    float steps_per_sec = steps_to_run / elapsed;
    
    printf("OK (%.0f steps/sec)\n", steps_per_sec);
    
    // Test 5: Performance check
    printf("[TEST 5] Performance reality check... ");
    if (steps_per_sec > 4000 && steps_per_sec < 7000) {
        printf("OK (%.0f steps/sec, matches ~5.5k baseline)\n", steps_per_sec);
    } else {
        printf("SUSPECT (%.0f steps/sec, expected ~5.5k)\n", steps_per_sec);
    }
    
    // Cleanup
    cudaFree(f0);
    cudaFree(f1);
    
    printf("\n=======================================================================\n");
    printf("  DEBUG COMPLETE\n");
    printf("=======================================================================\n");
    
    if (steps_per_sec > 10000) {
        printf("\n🚨 WARNING: Step rate too high (%.0f > 10k)\n", steps_per_sec);
        printf("   FFT/LBM may be bypassed in full test.\n");
        return 1;
    }
    
    printf("\n✅ All basic tests passed.\n");
    printf("   The issue may be with FFT initialization in the full test.\n");
    
    return 0;
}