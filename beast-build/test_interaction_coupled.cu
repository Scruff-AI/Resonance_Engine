/**
 * test_interaction_coupled.cu
 * 
 * Test 3: Interaction-Coupled Brain
 * Load 490k etch, run continuous fluid, simulate LLM interaction
 * Measure: Does organized vorticity destabilize under "LLM presence"?
 */

#include <cuda_runtime.h>
#include <nvml.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>

#define NX 512
#define NY 512
#define Q 9

__constant__ int d_cx[Q] = {0, 1, 0, -1, 0, 1, -1, -1, 1};
__constant__ int d_cy[Q] = {0, 0, 1, 0, -1, 1, 1, -1, -1};
__constant__ float d_w[Q] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 
                             1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};

float *d_f = NULL, *d_rho = NULL, *d_ux = NULL, *d_uy = NULL;
float h_omega = 1.9587f;
int llm_active = 0;  // Simulate LLM presence

__global__ void collide_kernel(float *f, float *rho, float *ux, float *uy, float omega, int jitter) {
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
    
    // Add jitter when LLM is "active" (simulating interaction load)
    if (jitter && (x + y) % 7 == 0) {
        float rnd = ((float)(clock() % 100) / 100.0f - 0.5f) * 0.02f;
        ux_local += rnd;
        uy_local += rnd;
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
    printf("=== TEST 3: INTERACTION-COUPLED BRAIN ===\n\n");
    
    cudaMalloc(&d_f, NX * NY * Q * sizeof(float));
    cudaMalloc(&d_rho, NX * NY * sizeof(float));
    cudaMalloc(&d_ux, NX * NY * sizeof(float));
    cudaMalloc(&d_uy, NX * NY * sizeof(float));
    
    load_etch("etch_00490000.bin");
    
    dim3 blockSize(16, 16);
    dim3 gridSize((NX + 15) / 16, (NY + 15) / 16);
    
    float *h_ux = (float*)malloc(NX * NY * sizeof(float));
    float *h_uy = (float*)malloc(NX * NY * sizeof(float));
    
    printf("Phase 1: Baseline (no LLM interaction)\n");
    printf("STEP | ENTROPY | COHERENCE | STATE\n");
    printf("-----+---------+-----------+------\n");
    
    // Phase 1: Baseline
    for (int step = 0; step < 500; step++) {
        collide_kernel<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, h_omega, 0);
        cudaDeviceSynchronize();
        
        if (step % 100 == 0) {
            cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
            cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
            float entropy = calculate_entropy(h_ux, h_uy);
            float coherence = calculate_coherence(h_ux, h_uy);
            printf("%4d | %7.4f | %9.4f | BASELINE\n", step, entropy, coherence);
        }
    }
    
    printf("\nPhase 2: LLM ACTIVE (simulated jitter every 7th cell)\n");
    
    // Phase 2: LLM Active
    for (int step = 500; step < 1000; step++) {
        llm_active = (step % 50 < 25) ? 1 : 0;  // 50% duty cycle
        collide_kernel<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, h_omega, llm_active);
        cudaDeviceSynchronize();
        
        if (step % 100 == 0) {
            cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
            cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
            float entropy = calculate_entropy(h_ux, h_uy);
            float coherence = calculate_coherence(h_ux, h_uy);
            const char* state = llm_active ? "LLM ON " : "LLM OFF";
            printf("%4d | %7.4f | %9.4f | %s\n", step, entropy, coherence, state);
        }
    }
    
    printf("\nPhase 3: Recovery (no LLM)\n");
    
    // Phase 3: Recovery
    for (int step = 1000; step < 1500; step++) {
        collide_kernel<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, h_omega, 0);
        cudaDeviceSynchronize();
        
        if (step % 100 == 0) {
            cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
            cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
            float entropy = calculate_entropy(h_ux, h_uy);
            float coherence = calculate_coherence(h_ux, h_uy);
            printf("%4d | %7.4f | %9.4f | RECOVER\n", step, entropy, coherence);
        }
    }
    
    printf("\n=== TEST COMPLETE ===\n");
    printf("Observe: Does coherence drop during LLM activity?\n");
    printf("Does the organized vorticity survive interaction?\n");
    
    free(h_ux); free(h_uy);
    cudaFree(d_f); cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy);
    return 0;
}
