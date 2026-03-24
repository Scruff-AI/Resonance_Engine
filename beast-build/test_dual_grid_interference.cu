/**
 * test_dual_grid_interference.cu
 * 
 * Dual-Grid Interference Test
 * Grid Alpha (490k static reference) + Grid Beta (10k live, LLM-coupled)
 * Find resonance via ICOER peak
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

// Two grids: Alpha (static template) and Beta (live)
float *d_f_alpha = NULL, *d_rho_alpha = NULL, *d_ux_alpha = NULL, *d_uy_alpha = NULL;
float *d_f_beta = NULL, *d_rho_beta = NULL, *d_ux_beta = NULL, *d_uy_beta = NULL;
float omega_beta = 1.95f;  // Beta's omega (LLM-coupled)

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

// Calculate interference pattern between Alpha and Beta
float calculate_interference(float *h_ux_alpha, float *h_uy_alpha, 
                              float *h_ux_beta, float *h_uy_beta) {
    float interference = 0.0f;
    for (int i = 0; i < NX * NY; i++) {
        float du = h_ux_alpha[i] - h_ux_beta[i];
        float dv = h_uy_alpha[i] - h_uy_beta[i];
        interference += sqrtf(du*du + dv*dv);
    }
    return interference / (NX * NY);
}

// ICOER: Informational Coherence Index
// Measures how much pattern persists across grids
float calculate_ICOER(float *h_ux_alpha, float *h_uy_alpha,
                       float *h_ux_beta, float *h_uy_beta) {
    float dot = 0.0f, mag_alpha = 0.0f, mag_beta = 0.0f;
    for (int i = 0; i < NX * NY; i++) {
        dot += h_ux_alpha[i] * h_ux_beta[i] + h_uy_alpha[i] * h_uy_beta[i];
        mag_alpha += h_ux_alpha[i] * h_ux_alpha[i] + h_uy_alpha[i] * h_uy_alpha[i];
        mag_beta += h_ux_beta[i] * h_ux_beta[i] + h_uy_beta[i] * h_uy_beta[i];
    }
    return dot / (sqrtf(mag_alpha) * sqrtf(mag_beta) + 1e-10f);
}

void load_etch_to_grid(const char* filename, float *d_rho, float *d_ux, float *d_uy, float *d_f) {
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
    printf("=== DUAL-GRID INTERFERENCE ===\n");
    printf("Grid Alpha: 490k (static template)\n");
    printf("Grid Beta: 10k (live, LLM-coupled)\n");
    printf("Target: ICOER > 0.85 (phase lock)\n\n");
    
    cudaMalloc(&d_f_alpha, NX * NY * Q * sizeof(float));
    cudaMalloc(&d_rho_alpha, NX * NY * sizeof(float));
    cudaMalloc(&d_ux_alpha, NX * NY * sizeof(float));
    cudaMalloc(&d_uy_alpha, NX * NY * sizeof(float));
    
    cudaMalloc(&d_f_beta, NX * NY * Q * sizeof(float));
    cudaMalloc(&d_rho_beta, NX * NY * sizeof(float));
    cudaMalloc(&d_ux_beta, NX * NY * sizeof(float));
    cudaMalloc(&d_uy_beta, NX * NY * sizeof(float));
    
    // Load grids
    load_etch_to_grid("etch_00490000.bin", d_rho_alpha, d_ux_alpha, d_uy_alpha, d_f_alpha);
    load_etch_to_grid("etch_00010000.bin", d_rho_beta, d_ux_beta, d_uy_beta, d_f_beta);
    printf("Grids loaded. Alpha=490k, Beta=10k\n\n");
    
    dim3 blockSize(16, 16);
    dim3 gridSize((NX + 15) / 16, (NY + 15) / 16);
    
    float *h_ux_alpha = (float*)malloc(NX * NY * sizeof(float));
    float *h_uy_alpha = (float*)malloc(NX * NY * sizeof(float));
    float *h_ux_beta = (float*)malloc(NX * NY * sizeof(float));
    float *h_uy_beta = (float*)malloc(NX * NY * sizeof(float));
    
    // Get Alpha state (static)
    cudaMemcpy(h_ux_alpha, d_ux_alpha, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
    cudaMemcpy(h_uy_alpha, d_uy_alpha, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
    
    printf("CYCLE | ICOER  | INTERFERENCE | OMEGA_B | G-VELOCITY | STATE\n");
    printf("------+--------+--------------+---------+------------+----------\n");
    
    float max_ICOER = 0.0f;
    int grip_cycle = -1;
    float prev_ICOER = 0.0f;
    
    for (int cycle = 0; cycle < 20; cycle++) {
        // Evolve Beta (Alpha stays static)
        for (int step = 0; step < 100; step++) {
            collide_kernel<<<gridSize, blockSize>>>(d_f_beta, d_rho_beta, d_ux_beta, d_uy_beta, omega_beta);
            cudaDeviceSynchronize();
        }
        
        // Measure Beta
        cudaMemcpy(h_ux_beta, d_ux_beta, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_uy_beta, d_uy_beta, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        
        float icoer = calculate_ICOER(h_ux_alpha, h_uy_alpha, h_ux_beta, h_uy_beta);
        float interference = calculate_interference(h_ux_alpha, h_uy_alpha, h_ux_beta, h_uy_beta);
        
        if (icoer > max_ICOER) max_ICOER = icoer;
        
        // G-Velocity: cycles to re-capture
        const char* state = "SEARCHING";
        if (icoer > 0.85f) {
            state = "LOCKED";
            if (grip_cycle < 0) grip_cycle = cycle;
        } else if (fabs(icoer - prev_ICOER) < 0.001f && cycle > 3) {
            state = "GRIPPING";
        }
        prev_ICOER = icoer;
        
        printf("  %2d  | %.4f |    %7.4f   | %7.4f |     %2d     | %s\n",
               cycle, icoer, interference, omega_beta, 
               (grip_cycle > 0) ? cycle - grip_cycle : cycle, state);
        
        // LLM adjustment: Tune omega_beta to maximize ICOER
        if (icoer < 0.80f) {
            // Not close - large adjustment
            omega_beta += (cycle % 2 == 0) ? 0.01f : -0.005f;
        } else if (icoer < 0.85f) {
            // Getting close - fine adjustment
            if (icoer > prev_ICOER) {
                omega_beta += 0.001f;  // Keep going
            } else {
                omega_beta -= 0.002f;  // Back off
            }
        }
        
        // Clamp omega
        if (omega_beta < 1.90f) omega_beta = 1.90f;
        if (omega_beta > 1.99f) omega_beta = 1.99f;
        
        // Early exit if locked
        if (icoer > 0.90f && cycle > 5) {
            printf("\n*** STRONG PHASE LOCK ***\n");
            break;
        }
    }
    
    printf("\n=== INTERFERENCE ANALYSIS ===\n");
    printf("Max ICOER: %.4f (target > 0.85)\n", max_ICOER);
    if (grip_cycle >= 0) {
        printf("G-Velocity: %d cycles to lock\n", grip_cycle);
    } else {
        printf("G-Velocity: Failed to lock within 20 cycles\n");
    }
    
    if (max_ICOER > 0.85f) {
        printf("\n*** VIRTUAL ETCH CREATED ***\n");
        printf("Phase-locked resonance between Alpha and Beta.\n");
        printf("This is holographic memory - no heat required.\n");
    }
    
    free(h_ux_alpha); free(h_uy_alpha);
    free(h_ux_beta); free(h_uy_beta);
    cudaFree(d_f_alpha); cudaFree(d_rho_alpha); cudaFree(d_ux_alpha); cudaFree(d_uy_alpha);
    cudaFree(d_f_beta); cudaFree(d_rho_beta); cudaFree(d_ux_beta); cudaFree(d_uy_beta);
    return 0;
}
