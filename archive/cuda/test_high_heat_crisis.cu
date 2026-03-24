/**
 * test_high_heat_crisis.cu
 * 
 * Test 4.5/5: High-Heat Perturbation
 * Induce crisis: omega 1.992, thermal stress, find high-temperature attractor
 */

#include <cuda_runtime.h>
#include <nvml.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define NX 512
#define NY 512
#define Q 9

__constant__ int d_cx[Q] = {0, 1, 0, -1, 0, 1, -1, -1, 1};
__constant__ int d_cy[Q] = {0, 0, 1, 0, -1, 1, 1, -1, -1};
__constant__ float d_w[Q] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 
                             1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};

float *d_f = NULL, *d_rho = NULL, *d_ux = NULL, *d_uy = NULL;
float h_omega = 1.992f;  // CRISIS: Instability edge
float h_rho_thresh = 0.50f;  // Force chaotic precipitation

__global__ void collide_kernel_crisis(float *f, float *rho, float *ux, float *uy, float omega, float rho_thresh) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= NX || y >= NY) return;
    int idx = y * NX + x;
    
    // Inject noise at threshold
    float noise = 0.0f;
    if ((x + y) % 3 == 0) {
        noise = ((float)((x * 7 + y * 13) % 100) / 100.0f - 0.5f) * 0.1f;
    }
    
    float rho_local = 0.0f, ux_local = 0.0f, uy_local = 0.0f;
    for (int i = 0; i < Q; i++) {
        float fi = f[idx * Q + i];
        rho_local += fi;
        ux_local += d_cx[i] * fi;
        uy_local += d_cy[i] * fi;
    }
    ux_local /= rho_local;
    uy_local /= rho_local;
    
    // Apply threshold chaos
    if (rho_local < rho_thresh) {
        ux_local += noise;
        uy_local += noise;
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

float calculate_entropy(float *h_ux, float *h_uy) {
    float entropy = 0.0f;
    for (int i = 0; i < NX * NY; i++) {
        entropy += h_ux[i] * h_ux[i] + h_uy[i] * h_uy[i];
    }
    return entropy / (NX * NY);
}

float calculate_coherence(float *h_ux, float *h_uy) {
    float coherence = 0.0f;
    for (int i = 0; i < NX * NY; i++) {
        coherence += sqrtf(h_ux[i] * h_ux[i] + h_uy[i] * h_uy[i]);
    }
    return coherence / (NX * NY);
}

void update_thermal_feedback(float temp_c) {
    // Adaptive: If temp > 75, reduce omega to stabilize
    if (temp_c > 75.0f) {
        h_omega -= 0.002f;
        if (h_omega < 1.90f) h_omega = 1.90f;
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
    printf("=== HIGH-HEAT CRISIS ===\n");
    printf("Omega: 1.992 (Instability Edge)\n");
    printf("Rho threshold: 0.50 (Chaos injection)\n");
    printf("Target: Find high-temperature attractor\n\n");
    
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
    
    nvmlDevice_t device;
    nvmlDeviceGetHandleByIndex(0, &device);
    
    printf("CYCLE | ENTROPY | COHERENCE | OMEGA   | TEMP(C) | STATE\n");
    printf("------+---------+-----------+---------+---------+----------------\n");
    
    int cycles_to_stabilize = -1;
    float prev_coherence = 0.0f;
    
    for (int cycle = 0; cycle < 20; cycle++) {
        // Get temperature
        unsigned int temp;
        nvmlDeviceGetTemperature(device, NVML_TEMPERATURE_GPU, &temp);
        float temp_c = (float)temp;
        
        // Run crisis for 50 steps
        for (int step = 0; step < 50; step++) {
            collide_kernel_crisis<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, h_omega, h_rho_thresh);
            cudaDeviceSynchronize();
        }
        
        // Observe
        cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        float entropy = calculate_entropy(h_ux, h_uy);
        float coherence = calculate_coherence(h_ux, h_uy);
        
        // Adaptive feedback
        const char* state = "CHAOS";
        if (temp_c > 70.0f) {
            update_thermal_feedback(temp_c);
            state = "ADAPTING";
        }
        if (fabs(coherence - prev_coherence) < 0.001f && cycle > 5) {
            state = "STABILIZED";
            if (cycles_to_stabilize < 0) cycles_to_stabilize = cycle;
        }
        prev_coherence = coherence;
        
        printf("  %2d  | %7.4f | %9.4f | %7.4f | %7.1f | %s\n", 
               cycle, entropy, coherence, h_omega, temp_c, state);
        
        // LLM micro-adjustment logic
        if (entropy > 45.0f) {
            h_omega -= 0.005f;  // More viscous
            h_rho_thresh += 0.05f;  // Less chaos
        } else if (coherence < 5.0f && temp_c > 65.0f) {
            h_omega += 0.003f;  // Less viscous
        }
        
        // Clamp
        if (h_omega < 1.90f) h_omega = 1.90f;
        if (h_omega > 1.995f) h_omega = 1.995f;
        if (h_rho_thresh > 0.9f) h_rho_thresh = 0.9f;
    }
    
    printf("\n=== CRISIS COMPLETE ===\n");
    if (cycles_to_stabilize > 0) {
        printf("Stabilized in %d cycles\n", cycles_to_stabilize);
    } else {
        printf("Did not stabilize within 20 cycles\n");
    }
    printf("Final omega: %.4f\n", h_omega);
    printf("Final rho_thresh: %.2f\n", h_rho_thresh);
    
    free(h_ux); free(h_uy);
    cudaFree(d_f); cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy);
    nvmlShutdown();
    return 0;
}
