/**
 * test_thermal_coupling.cu
 * 
 * Test 1: Verify thermal coupling with LLM load
 * Load 490k etch, run fluid, measure entropy during LLM inference
 */

#include <cuda_runtime.h>
#include <nvml.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include <windows.h>

#define NX 512
#define NY 512
#define Q 9

__constant__ int d_cx[Q] = {0, 1, 0, -1, 0, 1, -1, -1, 1};
__constant__ int d_cy[Q] = {0, 0, 1, 0, -1, 1, 1, -1, -1};
__constant__ float d_w[Q] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 
                             1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};

// Device pointers
float *d_f = NULL;
float *d_rho = NULL;
float *d_ux = NULL;
float *d_uy = NULL;

// Host somatic state
float h_omega = 1.9587f;  // From 490k run
float h_temp_c = 0.0f;
float h_watts = 0.0f;

#define THERMAL_COUPLE 0.001f
#define TEMP_TARGET 65.0f

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

void update_thermal_feedback() {
    nvmlDevice_t device;
    nvmlDeviceGetHandleByIndex(0, &device);
    unsigned int temp, power_mw;
    nvmlDeviceGetTemperature(device, NVML_TEMPERATURE_GPU, &temp);
    nvmlDeviceGetPowerUsage(device, &power_mw);
    h_temp_c = (float)temp;
    h_watts = power_mw / 1000.0f;
    float thermal_adjust = (h_temp_c - TEMP_TARGET) * THERMAL_COUPLE;
    h_omega = 1.9587f - thermal_adjust;
    if (h_omega < 0.01f) h_omega = 0.01f;
    if (h_omega > 1.99f) h_omega = 1.99f;
}

float calculate_entropy(float *h_ux, float *h_uy) {
    float entropy = 0.0f;
    for (int i = 0; i < NX * NY; i++) {
        entropy += h_ux[i] * h_ux[i] + h_uy[i] * h_uy[i];
    }
    return entropy / (NX * NY);
}

void load_etch(const char* filename) {
    FILE* fp = fopen(filename, "rb");
    if (!fp) { printf("Failed to load etch\n"); exit(1); }
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
    // Reconstruct f using host-side lattice constants
    const int cx[Q] = {0, 1, 0, -1, 0, 1, -1, -1, 1};
    const int cy[Q] = {0, 0, 1, 0, -1, 1, 1, -1, -1};
    const float w[Q] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 
                        1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};
    float *h_f = (float*)malloc(NX * NY * Q * sizeof(float));
    for (int y = 0; y < NY; y++) {
        for (int x = 0; x < NX; x++) {
            int idx = y * NX + x;
            float uu = h_ux[idx] * h_ux[idx] + h_uy[idx] * h_uy[idx];
            for (int i = 0; i < Q; i++) {
                float cu = cx[i] * h_ux[idx] + cy[i] * h_uy[idx];
                h_f[idx * Q + i] = w[i] * h_rho[idx] * (1.0f + 3.0f * cu + 4.5f * cu * cu - 1.5f * uu);
            }
        }
    }
    cudaMemcpy(d_f, h_f, NX * NY * Q * sizeof(float), cudaMemcpyHostToDevice);
    free(h_rho); free(h_ux); free(h_uy); free(h_f);
    printf("ETCH LOADED: %s\n", filename);
}

int main(int argc, char** argv) {
    printf("=== TEST 1: THERMAL COUPLING ===\n\n");
    
    nvmlInit();
    cudaMalloc(&d_f, NX * NY * Q * sizeof(float));
    cudaMalloc(&d_rho, NX * NY * sizeof(float));
    cudaMalloc(&d_ux, NX * NY * sizeof(float));
    cudaMalloc(&d_uy, NX * NY * sizeof(float));
    
    load_etch("etch_00490000.bin");
    
    dim3 blockSize(16, 16);
    dim3 gridSize((NX + 15) / 16, (NY + 15) / 16);
    
    float *h_ux = (float*)malloc(NX * NY * sizeof(float));
    float *h_uy = (float*)malloc(NX * NY * sizeof(float));
    
    printf("\nRunning 1000 steps with thermal monitoring...\n");
    printf("STEP | ENTROPY | TEMP(C) | POWER(W) | OMEGA\n");
    printf("-----+---------+---------+----------+-------\n");
    
    for (int step = 0; step < 1000; step++) {
        if (step % 10 == 0) update_thermal_feedback();
        collide_kernel<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, h_omega);
        cudaDeviceSynchronize();
        
        if (step % 100 == 0) {
            cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
            cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
            float entropy = calculate_entropy(h_ux, h_uy);
            printf("%4d | %7.4f | %7.1f | %8.1f | %.4f\n", step, entropy, h_temp_c, h_watts, h_omega);
        }
    }
    
    printf("\n=== BASELINE ESTABLISHED ===\n");
    printf("Now run LLM inference in parallel and observe entropy change.\n");
    printf("Expected: Entropy spike during LLM load (shared GPU resources)\n");
    
    free(h_ux); free(h_uy);
    cudaFree(d_f); cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy);
    nvmlShutdown();
    return 0;
}
