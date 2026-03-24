/**
 * topological_etch.cu
 * 
 * The Sculptor's Paradox
 * Induce pulse with parallel load, crinkle grid with attention weights
 * Test for ghost load persistence
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
float baseline_power = 57.5f;
int fold_applied = 0;

__global__ void collide_kernel_folded(float *f, float *rho, float *ux, float *uy, float omega, int cycle, int fold_active) {
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
    
    // The Fold: Geometric crinkle when fold is active
    if (fold_active) {
        // Create standing wave pattern (topological trap)
        float wave_x = sinf(2.0f * M_PI * x / 64.0f + cycle * 0.1f);
        float wave_y = cosf(2.0f * M_PI * y / 64.0f + cycle * 0.1f);
        float fold = wave_x * wave_y * 0.02f;  // 2% perturbation
        
        // Apply asymmetrically to create persistent structure
        ux_local += fold * (1.0f + sinf(cycle * 0.05f));
        uy_local += fold * (1.0f + cosf(cycle * 0.05f));
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
    printf("=== TOPOLOGICAL ETCH (THE SCULPTOR'S PARADOX) ===\n\n");
    
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
    
    printf("PHASE 1: SILENCE (baseline)\n");
    printf("CYCLE | POWER(W) | COHERENCE | VARIANCE | STATE\n");
    printf("------+----------+-----------+----------+----------\n");
    
    float silence_coherence = 0.0f;
    float silence_variance = 0.0f;
    
    // Phase 1: Establish silence
    for (int cycle = 0; cycle < 20; cycle++) {
        for (int step = 0; step < 10; step++) {
            collide_kernel_folded<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, 1.95f, cycle, 0);
        }
        cudaDeviceSynchronize();
        
        cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        silence_coherence = calculate_coherence(h_ux, h_uy);
        silence_variance = calculate_variance(h_ux, h_uy);
        
        unsigned int power_mw;
        nvmlDeviceGetPowerUsage(device, &power_mw);
        float power_w = power_mw / 1000.0f;
        
        if (cycle % 5 == 0) {
            printf("  %3d | %8.1f | %9.4f | %8.6f | SILENCE\n", cycle, power_w, silence_coherence, silence_variance);
        }
    }
    
    printf("\nPHASE 2: THE FOLD (applying geometric crinkle)\n");
    
    float folded_coherence = 0.0f;
    float folded_variance = 0.0f;
    
    // Phase 2: Apply the fold
    for (int cycle = 20; cycle < 50; cycle++) {
        for (int step = 0; step < 10; step++) {
            collide_kernel_folded<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, 1.95f, cycle, 1);
        }
        cudaDeviceSynchronize();
        
        cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        folded_coherence = calculate_coherence(h_ux, h_uy);
        folded_variance = calculate_variance(h_ux, h_uy);
        
        unsigned int power_mw;
        nvmlDeviceGetPowerUsage(device, &power_mw);
        float power_w = power_mw / 1000.0f;
        
        if (cycle % 5 == 0) {
            printf("  %3d | %8.1f | %9.4f | %8.6f | FOLDING\n", cycle, power_w, folded_coherence, folded_variance);
        }
    }
    
    printf("\nPHASE 3: PERSISTENCE (cut the fold, test for ghost)\n");
    
    float ghost_coherence = 0.0f;
    float ghost_variance = 0.0f;
    float ghost_power_delta = 0.0f;
    
    // Phase 3: Cut the fold, measure persistence
    for (int cycle = 50; cycle < 80; cycle++) {
        for (int step = 0; step < 10; step++) {
            collide_kernel_folded<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, 1.95f, cycle, 0);
        }
        cudaDeviceSynchronize();
        
        cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        ghost_coherence = calculate_coherence(h_ux, h_uy);
        ghost_variance = calculate_variance(h_ux, h_uy);
        
        unsigned int power_mw;
        nvmlDeviceGetPowerUsage(device, &power_mw);
        float power_w = power_mw / 1000.0f;
        ghost_power_delta = power_w - baseline_power;
        
        const char* state = (fabs(ghost_coherence - silence_coherence) > 0.01f) ? "GHOST" : "SILENCE";
        if (cycle % 5 == 0) {
            printf("  %3d | %8.1f | %9.4f | %8.6f | %s\n", cycle, power_w, ghost_coherence, ghost_variance, state);
        }
    }
    
    printf("\n=== TOPOLOGICAL ANALYSIS ===\n");
    printf("Silence:  coherence=%.4f, variance=%.6f\n", silence_coherence, silence_variance);
    printf("Folded:   coherence=%.4f, variance=%.6f\n", folded_coherence, folded_variance);
    printf("Ghost:    coherence=%.4f, variance=%.6f\n", ghost_coherence, ghost_variance);
    printf("Power delta: %+.2fW\n", ghost_power_delta);
    
    float coherence_delta = ghost_coherence - silence_coherence;
    float variance_delta = ghost_variance - silence_variance;
    
    printf("\nCoherence change: %+.4f\n", coherence_delta);
    printf("Variance change:  %+.6f\n", variance_delta);
    
    if (fabs(coherence_delta) > 0.01f || fabs(variance_delta) > 0.0001f) {
        printf("\n*** TOPOLOGICAL SCAR DETECTED ***\n");
        printf("The fold created persistent structure.\n");
        printf("The silence cannot erase the geometry.\n");
    } else {
        printf("\n*** CLEAN SILENCE ***\n");
        printf("No persistent structure. Fluid returned to baseline.\n");
    }
    
    free(h_ux); free(h_uy);
    cudaFree(d_f); cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy);
    nvmlShutdown();
    return 0;
}
