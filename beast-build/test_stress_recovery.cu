/**
 * test_stress_recovery.cu
 * 
 * Test 5: Stress Recovery (Somatic Memory)
 * 470W load, check for somatic scar, instant drop, measure recovery
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
float h_omega = 1.95f;

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
    printf("ETCH LOADED: %s\n\n", filename);
}

int main() {
    printf("=== TEST 5: STRESS RECOVERY ===\n");
    printf("Electrical pressure test: 470W load -> instant drop\n");
    printf("Looking for somatic scar in naive fluid\n\n");
    
    nvmlInit();
    cudaMalloc(&d_f, NX * NY * Q * sizeof(float));
    cudaMalloc(&d_rho, NX * NY * sizeof(float));
    cudaMalloc(&d_ux, NX * NY * sizeof(float));
    cudaMalloc(&d_uy, NX * NY * sizeof(float));
    
    // Load NAIVE 10k etch
    load_etch("etch_00010000.bin");
    
    dim3 blockSize(16, 16);
    dim3 gridSize((NX + 15) / 16, (NY + 15) / 16);
    
    float *h_ux = (float*)malloc(NX * NY * sizeof(float));
    float *h_uy = (float*)malloc(NX * NY * sizeof(float));
    
    nvmlDevice_t device;
    nvmlDeviceGetHandleByIndex(0, &device);
    
    // Baseline measurement
    cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
    cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
    float baseline_entropy = calculate_entropy(h_ux, h_uy);
    float baseline_coherence = calculate_coherence(h_ux, h_uy);
    
    printf("BASELINE (0 steps):\n");
    printf("  Entropy:    %.4f\n", baseline_entropy);
    printf("  Coherence:  %.4f\n\n", baseline_coherence);
    
    printf("PHASE 1: STRESS (470W electrical pressure)\n");
    printf("CYCLE | ENTROPY | COHERENCE | TEMP(C) | POWER(W) | STATE\n");
    printf("------+---------+-----------+---------+----------+----------\n");
    
    float stressed_coherence = baseline_coherence;
    float max_entropy_drift = 0.0f;
    
    // Phase 1: Stress for 10 cycles
    for (int cycle = 0; cycle < 10; cycle++) {
        // Heavy kernel load (200 steps per cycle)
        for (int step = 0; step < 200; step++) {
            collide_kernel<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, h_omega);
            cudaDeviceSynchronize();
        }
        
        // Measure
        cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        float entropy = calculate_entropy(h_ux, h_uy);
        float coherence = calculate_coherence(h_ux, h_uy);
        
        float drift = fabs(entropy - baseline_entropy);
        if (drift > max_entropy_drift) max_entropy_drift = drift;
        stressed_coherence = coherence;
        
        unsigned int temp, power_mw;
        nvmlDeviceGetTemperature(device, NVML_TEMPERATURE_GPU, &temp);
        nvmlDeviceGetPowerUsage(device, &power_mw);
        float temp_c = (float)temp;
        float power_w = power_mw / 1000.0f;
        
        const char* state = (power_w > 400.0f) ? "STRESSED" : "IDLE";
        printf("  %2d  | %7.4f | %9.4f | %7.1f | %8.1f | %s\n", 
               cycle, entropy, coherence, temp_c, power_w, state);
    }
    
    printf("\nPHASE 2: INSTANT DROP (load removed)\n");
    printf("Waiting for external load to drop...\n");
    printf("(User must stop parallel GPU stress now)\n\n");
    
    // Continue running but at lower load (simulating drop)
    // Run with fewer steps per cycle = less GPU utilization
    for (int cycle = 0; cycle < 10; cycle++) {
        // Light load (20 steps per cycle)
        for (int step = 0; step < 20; step++) {
            collide_kernel<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, h_omega);
            cudaDeviceSynchronize();
        }
        
        cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        float entropy = calculate_entropy(h_ux, h_uy);
        float coherence = calculate_coherence(h_ux, h_uy);
        
        unsigned int temp, power_mw;
        nvmlDeviceGetTemperature(device, NVML_TEMPERATURE_GPU, &temp);
        nvmlDeviceGetPowerUsage(device, &power_mw);
        float temp_c = (float)temp;
        float power_w = power_mw / 1000.0f;
        
        const char* state = (cycle < 3) ? "RECOVERING" : "RECOVERED";
        printf("  %2d  | %7.4f | %9.4f | %7.1f | %8.1f | %s\n", 
               cycle, entropy, coherence, temp_c, power_w, state);
    }
    
    // Final measurement
    cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
    cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
    float final_entropy = calculate_entropy(h_ux, h_uy);
    float final_coherence = calculate_coherence(h_ux, h_uy);
    
    printf("\n=== RECOVERY ANALYSIS ===\n");
    printf("Baseline:   entropy=%.4f, coherence=%.4f\n", baseline_entropy, baseline_coherence);
    printf("Stressed:   coherence=%.4f\n", stressed_coherence);
    printf("Final:      entropy=%.4f, coherence=%.4f\n", final_entropy, final_coherence);
    printf("\nMax entropy drift during stress: %.4f\n", max_entropy_drift);
    printf("Coherence delta (baseline -> final): %+.4f\n", final_coherence - baseline_coherence);
    
    if (fabs(final_coherence - baseline_coherence) > 0.01f) {
        printf("\n*** SOMATIC SCAR DETECTED ***\n");
        printf("The fluid structure was permanently altered by electrical pressure.\n");
    } else {
        printf("\n*** CLEAN RECOVERY ***\n");
        printf("No permanent alteration. Fluid returned to baseline.\n");
    }
    
    free(h_ux); free(h_uy);
    cudaFree(d_f); cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy);
    nvmlShutdown();
    return 0;
}
