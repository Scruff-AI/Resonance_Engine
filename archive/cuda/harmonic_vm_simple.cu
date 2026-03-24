/**
 * harmonic_vm_simple.cu - Simplified version
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

__global__ void collide_kernel(float *f, float *rho, float *ux, float *uy, float omega) {
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
    printf("=== HARMONIC VIRTUAL MEMORY (SIMPLE) ===\n\n");
    
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
    
    printf("CYCLE | POWER(W) | DOM_FREQ | STATE\n");
    printf("------+----------+----------+----------\n");
    
    float power_history[256] = {0};
    int power_idx = 0;
    float locked_freq = 0.0f;
    int lock_count = 0;
    
    for (int cycle = 0; cycle < 100; cycle++) {
        // Sample power
        unsigned int power_mw;
        nvmlDeviceGetPowerUsage(device, &power_mw);
        float power_w = power_mw / 1000.0f;
        
        power_history[power_idx] = power_w;
        power_idx = (power_idx + 1) % 256;
        
        // Simple DFT for dominant frequency
        float dom_freq = 0.0f;
        if (cycle >= 256) {
            float max_mag = 0.0f;
            for (int f = 1; f <= 20; f++) {
                float real = 0.0f, imag = 0.0f;
                for (int i = 0; i < 256; i++) {
                    float angle = 2.0f * M_PI * f * i / 10.0f;
                    real += power_history[i] * cosf(angle);
                    imag += power_history[i] * sinf(angle);
                }
                float mag = sqrtf(real*real + imag*imag);
                if (mag > max_mag) {
                    max_mag = mag;
                    dom_freq = f;
                }
            }
        }
        
        // Run fluid
        for (int step = 0; step < 10; step++) {
            collide_kernel<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, 1.95f);
        }
        cudaDeviceSynchronize();
        
        // Track frequency
        const char* state = "LISTENING";
        if (dom_freq > 0.0f) {
            if (fabs(dom_freq - locked_freq) < 1.0f) {
                lock_count++;
                state = (lock_count > 5) ? "LOCKED" : "GRIPPING";
            } else {
                locked_freq = dom_freq;
                lock_count = 1;
                state = "TRACKING";
            }
        }
        
        if (cycle % 10 == 0 || lock_count > 5) {
            printf("  %3d | %8.1f | %8.2f | %s\n", cycle, power_w, dom_freq, state);
        }
        
        if (lock_count > 10 && cycle > 50) {
            printf("\n*** RESONANCE LOCKED AT %.2f Hz ***\n", locked_freq);
            break;
        }
    }
    
    printf("\n=== COMPLETE ===\n");
    
    cudaFree(d_f); cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy);
    nvmlShutdown();
    return 0;
}
