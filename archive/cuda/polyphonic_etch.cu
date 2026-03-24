/**
 * polyphonic_etch.cu
 * 
 * The Polyphonic Layering
 * 64-cell ghost + 32-cell second fold
 * Test for multi-harmonic coexistence
 */

#include <cuda_runtime.h>
#include <nvml.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define NX 512
#define NY 512
#define Q 9

__constant__ int d_cx[Q] = {0, 1, 0, -1, 0, 1, -1, -1, 1};
__constant__ int d_cy[Q] = {0, 0, 1, 0, -1, 1, 1, -1, -1};
__constant__ float d_w[Q] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 
                             1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};

float *d_f, *d_rho, *d_ux, *d_uy;

__global__ void collide_kernel_polyphonic(float *f, float *rho, float *ux, float *uy, float omega, int cycle, int fold_64, int fold_32) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= NX || y >= NY) return;
    int idx = y * NX + x;
    
    float rho_local = 0.0f, ux_local = 0.0f, uy_local = 0.0f;
    for (int i = 0; i < Q; i++) {
        float fi = f[idx * Q + i];
        rho_local += fi;
        ux_local += d_cx[i] * fi;
        uy_local += d_cy[i] * fi;
    }
    ux_local /= rho_local;
    uy_local /= rho_local;
    
    // First fold: 64-cell ghost (persistent)
    if (fold_64) {
        float wave_x = sinf(2.0f * M_PI * x / 64.0f + cycle * 0.1f);
        float wave_y = cosf(2.0f * M_PI * y / 64.0f + cycle * 0.1f);
        float fold = wave_x * wave_y * 0.02f;
        ux_local += fold * (1.0f + sinf(cycle * 0.05f));
        uy_local += fold * (1.0f + cosf(cycle * 0.05f));
    }
    
    // Second fold: 32-cell (new harmonic)
    if (fold_32) {
        float wave_x = sinf(2.0f * M_PI * x / 32.0f + cycle * 0.2f);  // Double frequency
        float wave_y = cosf(2.0f * M_PI * y / 32.0f + cycle * 0.2f);
        float fold = wave_x * wave_y * 0.015f;  // Slightly weaker
        ux_local += fold * (1.0f + sinf(cycle * 0.1f));
        uy_local += fold * (1.0f + cosf(cycle * 0.1f));
    }
    
    rho[idx] = rho_local;
    ux[idx] = ux_local;
    uy[idx] = uy_local;
    
    float uu = ux_local * ux_local + uy_local * uy_local;
    for (int i = 0; i < Q; i++) {
        float cu = d_cx[i] * ux_local + d_cy[i] * uy_local;
        float f_eq = d_w[i] * rho_local * (1.0f + 3.0f * cu + 4.5f * cu * cu - 1.5f * uu);
        f[idx * Q + i] = f[idx * Q + i] - omega * (f[idx * Q + i] - f_eq);
    }
}

float calculate_coherence(float *h_ux, float *h_uy) {
    float coherence = 0.0f;
    for (int i = 0; i < NX * NY; i++) {
        coherence += sqrtf(h_ux[i] * h_ux[i] + h_uy[i] * h_uy[i]);
    }
    return coherence / (NX * NY);
}

float calculate_variance(float *h_ux, float *h_uy) {
    float mean_ux = 0.0f, mean_uy = 0.0f;
    for (int i = 0; i < NX * NY; i++) {
        mean_ux += h_ux[i];
        mean_uy += h_uy[i];
    }
    mean_ux /= NX * NY;
    mean_uy /= NX * NY;
    
    float var = 0.0f;
    for (int i = 0; i < NX * NY; i++) {
        var += (h_ux[i] - mean_ux) * (h_ux[i] - mean_ux);
        var += (h_uy[i] - mean_uy) * (h_uy[i] - mean_uy);
    }
    return var / (NX * NY);
}

// Simple FFT to detect multiple harmonics
void detect_harmonics(float *h_ux, float *h_uy, float *harmonic_64, float *harmonic_32) {
    // Sample along center line
    float sum_64 = 0.0f, sum_32 = 0.0f;
    int y = NY / 2;
    
    for (int x = 0; x < NX; x++) {
        int idx = y * NX + x;
        float u = h_ux[idx];
        
        // Correlate with 64-cell wave
        sum_64 += u * sinf(2.0f * M_PI * x / 64.0f);
        // Correlate with 32-cell wave
        sum_32 += u * sinf(2.0f * M_PI * x / 32.0f);
    }
    
    *harmonic_64 = fabs(sum_64) / NX;
    *harmonic_32 = fabs(sum_32) / NX;
}

void load_etch(const char* filename) {
    FILE* fp = fopen(filename, "rb");
    float *h_rho = (float*)malloc(NX * NY * sizeof(float));
    float *h_ux = (float*)malloc(NX * NY * sizeof(float));
    float *h_uy = (float*)malloc(NX * NY * sizeof(float));
    fread(h_rho, sizeof(float), NX * NY, fp);
    fread(h_ux, sizeof(float), NX * NY, fp);
    fread(h_uy, sizeof(float), NX * NY, fp);
    fclose(fp);
    
    cudaMemcpy(d_rho, h_rho, NX * NY * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_ux, h_ux, NX * NY * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_uy, h_uy, NX * NY * sizeof(float), cudaMemcpyHostToDevice);
    
    const int cx[Q] = {0, 1, 0, -1, 0, 1, -1, -1, 1};
    const int cy[Q] = {0, 0, 1, 0, -1, 1, 1, -1, -1};
    const float w[Q] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 
                        1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};
    float *h_f = (float*)malloc(NX * NY * Q * sizeof(float));
    for (int i = 0; i < NX * NY; i++) {
        float uu = h_ux[i] * h_ux[i] + h_uy[i] * h_uy[i];
        for (int j = 0; j < Q; j++) {
            float cu = cx[j] * h_ux[i] + cy[j] * h_uy[i];
            h_f[i * Q + j] = w[j] * h_rho[i] * (1.0f + 3.0f * cu + 4.5f * cu * cu - 1.5f * uu);
        }
    }
    cudaMemcpy(d_f, h_f, NX * NY * Q * sizeof(float), cudaMemcpyHostToDevice);
    free(h_rho); free(h_ux); free(h_uy); free(h_f);
}

int main() {
    printf("=== POLYPHONIC ETCH (THE CHORD) ===\n\n");
    
    nvmlInit();
    nvmlDevice_t device;
    nvmlDeviceGetHandleByIndex(0, &device);
    
    cudaMalloc(&d_f, NX * NY * Q * sizeof(float));
    cudaMalloc(&d_rho, NX * NY * sizeof(float));
    cudaMalloc(&d_ux, NX * NY * sizeof(float));
    cudaMalloc(&d_uy, NX * NY * sizeof(float));
    
    load_etch("etch_00490000.bin");
    printf("490k Fortress loaded\n\n");
    
    dim3 blockSize(16, 16);
    dim3 gridSize((NX + 15) / 16, (NY + 15) / 16);
    
    float *h_ux = (float*)malloc(NX * NY * sizeof(float));
    float *h_uy = (float*)malloc(NX * NY * sizeof(float));
    
    printf("CYCLE | POWER(W) | COHERENCE | HARM-64 | HARM-32 | STATE\n");
    printf("------+----------+-----------+---------+---------+----------------\n");
    
    float h64 = 0.0f, h32 = 0.0f;
    
    // Phase 1: Establish 64-cell ghost (0-30)
    for (int cycle = 0; cycle < 30; cycle++) {
        for (int step = 0; step < 10; step++) {
            collide_kernel_polyphonic<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, 1.95f, cycle, 1, 0);
        }
        cudaDeviceSynchronize();
        
        cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        detect_harmonics(h_ux, h_uy, &h64, &h32);
        
        unsigned int power_mw;
        nvmlDeviceGetPowerUsage(device, &power_mw);
        float power_w = power_mw / 1000.0f;
        
        if (cycle % 5 == 0) {
            printf("  %3d | %8.1f | %9.4f | %7.4f | %7.4f | GHOST-64\n", 
                   cycle, power_w, calculate_coherence(h_ux, h_uy), h64, h32);
        }
    }
    
    printf("\n--- Adding 32-cell harmonic ---\n\n");
    
    // Phase 2: Add 32-cell (30-60)
    for (int cycle = 30; cycle < 60; cycle++) {
        for (int step = 0; step < 10; step++) {
            collide_kernel_polyphonic<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, 1.95f, cycle, 1, 1);
        }
        cudaDeviceSynchronize();
        
        cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        detect_harmonics(h_ux, h_uy, &h64, &h32);
        
        unsigned int power_mw;
        nvmlDeviceGetPowerUsage(device, &power_mw);
        float power_w = power_mw / 1000.0f;
        
        const char* state = (h32 > h64 * 0.5f) ? "CHORD" : "FIGHTING";
        if (cycle % 5 == 0) {
            printf("  %3d | %8.1f | %9.4f | %7.4f | %7.4f | %s\n", 
                   cycle, power_w, calculate_coherence(h_ux, h_uy), h64, h32, state);
        }
    }
    
    printf("\n--- Double cut (both folds off) ---\n\n");
    
    // Phase 3: Double cut (60-90)
    for (int cycle = 60; cycle < 90; cycle++) {
        for (int step = 0; step < 10; step++) {
            collide_kernel_polyphonic<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, 1.95f, cycle, 0, 0);
        }
        cudaDeviceSynchronize();
        
        cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        detect_harmonics(h_ux, h_uy, &h64, &h32);
        
        unsigned int power_mw;
        nvmlDeviceGetPowerUsage(device, &power_mw);
        float power_w = power_mw / 1000.0f;
        
        const char* state = (h64 > 0.01f && h32 > 0.01f) ? "POLY-GHOST" : 
                           (h64 > 0.01f) ? "MONO-GHOST" : "SILENCE";
        if (cycle % 5 == 0) {
            printf("  %3d | %8.1f | %9.4f | %7.4f | %7.4f | %s\n", 
                   cycle, power_w, calculate_coherence(h_ux, h_uy), h64, h32, state);
        }
    }
    
    printf("\n=== POLYPHONIC ANALYSIS ===\n");
    printf("Final harmonics: 64-cell=%.4f, 32-cell=%.4f\n", h64, h32);
    
    if (h64 > 0.01f && h32 > 0.01f) {
        printf("\n*** POLYPHONIC GHOST ***\n");
        printf("The Beast holds a chord.\n");
        printf("Multiple topological memories coexisting.\n");
        printf("The manifold is INFINITE.\n");
    } else if (h64 > 0.01f) {
        printf("\n*** MONO-GHOST ***\n");
        printf("Only the 64-cell persists.\n");
        printf("The 32-cell was erased.\n");
        printf("The manifold is SATURATED at one note.\n");
    } else {
        printf("\n*** CLEAN SILENCE ***\n");
        printf("No persistent structure.\n");
    }
    
    free(h_ux); free(h_uy);
    cudaFree(d_f); cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy);
    nvmlShutdown();
    return 0;
}
