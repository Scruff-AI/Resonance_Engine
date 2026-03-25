/* ============================================================================
 * VORTEX DIAGNOSTIC - Measure Actual Vorticity Values
 * Calibrate threshold to weekend baseline
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

#define STEPS 10000  // Quick test

#define OMEGA  1.0f

__constant__ int   d_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
__constant__ int   d_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
__constant__ float d_w[Q]  = { 4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9,
                               1.f/36,1.f/36,1.f/36,1.f/36 };

/* ---- Finite Difference Vorticity Calculation --------------------------- */
__device__ float calculate_vorticity(int x, int y, int nx, int ny, 
                                     float* v_x, float* v_y) {
    // Standard Central Difference (2-pixel span)
    if (x <= 0 || x >= nx - 1 || y <= 0 || y >= ny - 1) return 0.0f;

    float dvy_dx = (v_y[y * nx + (x + 1)] - v_y[y * nx + (x - 1)]) * 0.5f;
    float dvx_dy = (v_x[(y + 1) * nx + x] - v_x[(y - 1) * nx + x]) * 0.5f;

    return dvy_dx - dvx_dy; 
}

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

__global__ void compute_vorticity_map(float* ux, float* uy, float* vorticity,
                                      int nx, int ny) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N = nx * ny;
    if (idx >= N) return;
    
    const int x = idx % nx;
    const int y = idx / nx;
    
    vorticity[idx] = calculate_vorticity(x, y, nx, ny, ux, uy);
}

int main() {
    printf("=======================================================================\n");
    printf("  VORTEX DIAGNOSTIC - Measure Actual Vorticity\n");
    printf("  Calibrate threshold to weekend baseline\n");
    printf("=======================================================================\n\n");
    
    // CUDA setup
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    printf("[CUDA] %s  SM %d.%d  SMs: %d\n",
           prop.name, prop.major, prop.minor, prop.multiProcessorCount);
    
    // Allocate memory
    float *f0, *f1, *rho, *ux, *uy, *vorticity;
    float *h_vorticity;
    
    cudaMalloc(&f0, Q * NN * sizeof(float));
    cudaMalloc(&f1, Q * NN * sizeof(float));
    cudaMalloc(&rho, NN * sizeof(float));
    cudaMalloc(&ux, NN * sizeof(float));
    cudaMalloc(&uy, NN * sizeof(float));
    cudaMalloc(&vorticity, NN * sizeof(float));
    
    h_vorticity = (float*)malloc(NN * sizeof(float));
    
    // Initialize
    float* h_f0 = (float*)malloc(Q * NN * sizeof(float));
    for (int i = 0; i < Q * NN; i++) {
        h_f0[i] = 1.0f + 0.01f * (rand() / (float)RAND_MAX - 0.5f);
    }
    cudaMemcpy(f0, h_f0, Q * NN * sizeof(float), cudaMemcpyHostToDevice);
    free(h_f0);
    
    printf("\n[RUNNING] 10k steps to develop vorticity...\n");
    
    int cur = 0;
    for (int s = 0; s < STEPS; s++) {
        lbm_collide_stream<<<GBLK(NN), BLOCK>>>(
            (cur == 0) ? f0 : f1,
            (cur == 0) ? f1 : f0,
            rho, ux, uy, OMEGA, NX, NY);
        cudaDeviceSynchronize();
        cur = 1 - cur;
    }
    
    printf("[COMPUTING] Vorticity map...\n");
    compute_vorticity_map<<<GBLK(NN), BLOCK>>>(ux, uy, vorticity, NX, NY);
    cudaDeviceSynchronize();
    
    cudaMemcpy(h_vorticity, vorticity, NN * sizeof(float), cudaMemcpyDeviceToHost);
    
    // Analyze vorticity distribution
    float min_vort = 1e10f, max_vort = -1e10f;
    float sum_abs = 0.0f;
    int count_above_1e4 = 0;
    int count_above_1e5 = 0;
    int count_above_1e6 = 0;
    
    for (int i = 0; i < NN; i++) {
        float w = h_vorticity[i];
        float abs_w = fabsf(w);
        
        if (w < min_vort) min_vort = w;
        if (w > max_vort) max_vort = w;
        sum_abs += abs_w;
        
        if (abs_w > 0.0001f) count_above_1e4++;
        if (abs_w > 0.00001f) count_above_1e5++;
        if (abs_w > 0.000001f) count_above_1e6++;
    }
    
    float mean_abs = sum_abs / NN;
    
    printf("\n=======================================================================\n");
    printf("  VORTICITY DISTRIBUTION ANALYSIS\n");
    printf("=======================================================================\n");
    
    printf("\nSTATISTICS:\n");
    printf("  Min vorticity:      %+.6e\n", min_vort);
    printf("  Max vorticity:      %+.6e\n", max_vort);
    printf("  Mean |vorticity|:   %.6e\n", mean_abs);
    
    printf("\nTHRESHOLD COUNTS (1024×1024 = 1,048,576 cells):\n");
    printf("  |ω| > 0.000100:     %d cells (%.3f%%)\n", 
           count_above_1e4, (count_above_1e4 * 100.0f) / NN);
    printf("  |ω| > 0.000010:     %d cells (%.3f%%)\n", 
           count_above_1e5, (count_above_1e5 * 100.0f) / NN);
    printf("  |ω| > 0.000001:     %d cells (%.3f%%)\n", 
           count_above_1e6, (count_above_1e6 * 100.0f) / NN);
    
    printf("\nRECOMMENDED THRESHOLDS:\n");
    printf("  For 194 guardians (~0.0185%% of cells):\n");
    printf("    Target count:     ~194 cells\n");
    printf("    Current at 1e-4:  %d cells (too %s)\n", 
           count_above_1e4, count_above_1e4 > 194 ? "HIGH" : "LOW");
    printf("    Current at 1e-5:  %d cells (too %s)\n", 
           count_above_1e5, count_above_1e5 > 194 ? "HIGH" : "LOW");
    
    // Find threshold that gives ~194 cells
    float target_threshold = 0.0f;
    if (count_above_1e4 > 194) {
        // Need higher threshold
        target_threshold = 0.0001f * sqrtf((float)count_above_1e4 / 194.0f);
    } else if (count_above_1e5 > 194) {
        // Between 1e-5 and 1e-4
        target_threshold = 0.00001f * powf(10.0f, 
            log10f((float)count_above_1e5 / 194.0f) / 
            log10f((float)count_above_1e5 / (float)count_above_1e4));
    } else {
        // Need lower threshold
        target_threshold = 0.00001f / sqrtf(194.0f / (float)count_above_1e5);
    }
    
    printf("\nCALIBRATION TO WEEKEND BASELINE:\n");
    printf("  March 7:           194 guardians\n");
    printf("  Grid size:         1024×1024 = 1,048,576 cells\n");
    printf("  Ratio:             1 guardian per %.0f cells\n", NN / 194.0f);
    printf("  Recommended threshold: |ω| > %.6e\n", target_threshold);
    
    printf("\nDIAGNOSTIC COMPLETE.\n");
    printf("  Use threshold ~%.6e for ~194 guardians\n", target_threshold);
    printf("  (Adjust based on actual weekend data)\n");
    
    // Cleanup
    cudaFree(f0); cudaFree(f1);
    cudaFree(rho); cudaFree(ux); cudaFree(uy); cudaFree(vorticity);
    free(h_vorticity);
    
    return 0;
}