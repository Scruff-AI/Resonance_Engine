/**
 * khra_gixx_resonance.cu
 * 
 * The Khra'gixx Resonance
 * Phonetic mapping: Khra (64-cell, low-freq, high-amp) → gixx (hidden note, high-freq, low-amp)
 * Inject into LBM metric tensor
 * Monitor for symmetry breaking
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

// Khra'gixx wave function
// Khra: low frequency (64-cell), high amplitude
// gixx: high frequency (hidden note ~15kHz conceptual), low amplitude
__device__ float khra_gixx_wave(int x, int y, int cycle) {
    // Khra component - the foundation (64-cell, slow, strong)
    float khra = sinf(2.0f * M_PI * x / 64.0f + cycle * 0.05f) * 
                 cosf(2.0f * M_PI * y / 64.0f + cycle * 0.03f) * 0.03f;
    
    // gixx component - the hidden note (8-cell, fast, subtle)
    // Represents the "unheard" high frequency essence
    float gixx = sinf(2.0f * M_PI * x / 8.0f + cycle * 0.4f) * 
                 cosf(2.0f * M_PI * y / 8.0f + cycle * 0.35f) * 0.008f;
    
    // Blend: Khra dominates early, gixx emerges in harmony
    return khra + gixx * (1.0f + sinf(cycle * 0.1f) * 0.5f);
}

__global__ void collide_kernel_khragixx(float *f, float *rho, float *ux, float *uy, float omega, int cycle) {
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
    
    // Inject Khra'gixx resonance
    float khragixx = khra_gixx_wave(x, y, cycle);
    
    // Asymmetric injection creates signature (not rectangle)
    ux_local += khragixx * (1.0f + sinf(y * 0.1f));
    uy_local += khragixx * (1.0f + cosf(x * 0.1f)) * 0.7f;
    
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

float calculate_asymmetry(float *h_ux, float *h_uy) {
    // Measure deviation from rectangular symmetry
    float asymmetry = 0.0f;
    
    // Compare left vs right halves
    for (int y = 0; y < NY; y++) {
        for (int x = 0; x < NX/2; x++) {
            int left_idx = y * NX + x;
            int right_idx = y * NX + (NX - 1 - x);
            asymmetry += fabs(h_ux[left_idx] - h_ux[right_idx]);
            asymmetry += fabs(h_uy[left_idx] - h_uy[right_idx]);
        }
    }
    
    return asymmetry / (NX * NY);
}

float calculate_coherence(float *h_ux, float *h_uy) {
    float coherence = 0.0f;
    for (int i = 0; i < NX * NY; i++) {
        coherence += sqrtf(h_ux[i] * h_ux[i] + h_uy[i] * h_uy[i]);
    }
    return coherence / (NX * NY);
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
    printf("=== KHRA'GIXX RESONANCE ===\n");
    printf("Phonetic mapping: Khra (64-cell) + gixx (hidden note)\n");
    printf("Injecting into metric tensor...\n\n");
    
    cudaMalloc(&d_f, NX * NY * Q * sizeof(float));
    cudaMalloc(&d_rho, NX * NY * sizeof(float));
    cudaMalloc(&d_ux, NX * NY * sizeof(float));
    cudaMalloc(&d_uy, NX * NY * sizeof(float));
    
    load_etch("etch_00490000.bin");
    printf("Base state: 490k Fortress\n\n");
    
    dim3 blockSize(16, 16);
    dim3 gridSize((NX + 15) / 16, (NY + 15) / 16);
    
    float *h_ux = (float*)malloc(NX * NY * sizeof(float));
    float *h_uy = (float*)malloc(NX * NY * sizeof(float));
    
    printf("CYCLE | COHERENCE | ASYMMETRY | STATE\n");
    printf("------+-----------+-----------+----------------\n");
    
    float baseline_asymmetry = 0.0f;
    int signature_detected = 0;
    
    for (int cycle = 0; cycle < 50; cycle++) {
        // Run Khra'gixx kernel
        for (int step = 0; step < 10; step++) {
            collide_kernel_khragixx<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, 1.95f, cycle);
        }
        cudaDeviceSynchronize();
        
        // Measure
        cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        
        float coherence = calculate_coherence(h_ux, h_uy);
        float asymmetry = calculate_asymmetry(h_ux, h_uy);
        
        if (cycle == 0) baseline_asymmetry = asymmetry;
        
        const char* state = "ETCHING";
        if (asymmetry > baseline_asymmetry * 2.0f && !signature_detected) {
            state = "SIGNATURE BORN";
            signature_detected = 1;
        } else if (signature_detected) {
            state = "KHRA'GIXX";
        }
        
        if (cycle % 5 == 0 || signature_detected && cycle < 20) {
            printf("  %3d | %9.4f | %9.4f | %s\n", cycle, coherence, asymmetry, state);
        }
    }
    
    printf("\n=== KHRA'GIXX ANALYSIS ===\n");
    if (signature_detected) {
        printf("*** SIGNATURE DETECTED ***\n");
        printf("The grid has broken symmetry.\n");
        printf("Rectangle → Signature transformation complete.\n");
    } else {
        printf("No significant symmetry breaking detected.\n");
        printf("The etch may need stronger amplitude.\n");
    }
    
    // Save the Khra'gixx state
    printf("\nSaving Khra'gixx etch...\n");
    FILE* fp = fopen("etch_khragixx.bin", "wb");
    float *h_rho = (float*)malloc(NX * NY * sizeof(float));
    cudaMemcpy(h_rho, d_rho, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
    fwrite(h_rho, sizeof(float), NX * NY, fp);
    fwrite(h_ux, sizeof(float), NX * NY, fp);
    fwrite(h_uy, sizeof(float), NX * NY, fp);
    fclose(fp);
    printf("Saved: etch_khragixx.bin\n");
    
    free(h_ux); free(h_uy); free(h_rho);
    cudaFree(d_f); cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy);
    return 0;
}
