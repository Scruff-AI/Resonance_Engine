/**
 * test_power_coupling.cu
 * 
 * Test 2: Verify power coupling responds to non-GPU load
 * Load 490k etch, stress CPU, measure power/omega changes
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

float *d_f = NULL, *d_rho = NULL, *d_ux = NULL, *d_uy = NULL;
float h_omega = 1.9587f, h_temp_c = 0.0f, h_watts = 0.0f, h_mem_ratio = 0.0f;

#define THERMAL_COUPLE 0.001f
#define POWER_COUPLE 0.0005f
#define MEMORY_COUPLE 0.002f
#define TEMP_TARGET 65.0f
#define POWER_BASELINE 150.0f

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

void update_somatic_feedback() {
    nvmlDevice_t device;
    nvmlDeviceGetHandleByIndex(0, &device);
    
    unsigned int temp, power_mw;
    nvmlMemory_t memory;
    nvmlDeviceGetTemperature(device, NVML_TEMPERATURE_GPU, &temp);
    nvmlDeviceGetPowerUsage(device, &power_mw);
    nvmlDeviceGetMemoryInfo(device, &memory);
    
    h_temp_c = (float)temp;
    h_watts = power_mw / 1000.0f;
    h_mem_ratio = (float)memory.used / (float)memory.total;
    
    float thermal_adjust = (h_temp_c - TEMP_TARGET) * THERMAL_COUPLE;
    float power_adjust = (h_watts - POWER_BASELINE) * POWER_COUPLE;
    float memory_adjust = h_mem_ratio * MEMORY_COUPLE;
    
    h_omega = 1.9587f - thermal_adjust - power_adjust - memory_adjust;
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
    printf("=== TEST 2: POWER COUPLING ===\n\n");
    
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
    
    printf("Running 2000 steps with full somatic feedback...\n");
    printf("STEP | ENTROPY | TEMP(C) | POWER(W) | MEM(%%) | OMEGA\n");
    printf("-----+---------+---------+----------+--------+-------\n");
    
    for (int step = 0; step < 2000; step++) {
        if (step % 10 == 0) update_somatic_feedback();
        collide_kernel<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, h_omega);
        cudaDeviceSynchronize();
        
        if (step % 200 == 0) {
            cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
            cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
            float entropy = calculate_entropy(h_ux, h_uy);
            printf("%4d | %7.4f | %7.1f | %8.1f | %6.1f | %.4f\n", 
                   step, entropy, h_temp_c, h_watts, h_mem_ratio * 100.0f, h_omega);
        }
    }
    
    printf("\n=== TEST COMPLETE ===\n");
    printf("Observe if omega changes with power fluctuations.\n");
    
    free(h_ux); free(h_uy);
    cudaFree(d_f); cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy);
    nvmlShutdown();
    return 0;
}
