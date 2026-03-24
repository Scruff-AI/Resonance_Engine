/**
 * experiment_a_topological_phase_lock.cu
 * 
 * Experiment A: Topological Phase-Lock
 * Grid Alpha: 490k etch (the Fortress)
 * Grid Beta: Independent random seed (the Stranger)
 * Find the Third State in the interference
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

float *d_f_alpha, *d_rho_alpha, *d_ux_alpha, *d_uy_alpha;
float *d_f_beta, *d_rho_beta, *d_ux_beta, *d_uy_beta;

__global__ void init_independent(float *f, float *rho, float *ux, float *uy, int seed) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= NX || y >= NY) return;
    int idx = y * NX + x;
    
    // Independent random seed for Beta
    float rnd = (float)((x * 17 + y * 31 + seed * 7) % 1000) / 1000.0f;
    float rho0 = 1.0f + (rnd - 0.5f) * 0.1f;  // Slight density variation
    float u0 = (rnd - 0.5f) * 0.05f;  // Small random velocity
    
    rho[idx] = rho0;
    ux[idx] = u0;
    uy[idx] = u0 * 0.5f;  // Asymmetric
    
    for (int i = 0; i < Q; i++) {
        float cu = d_cx[i] * u0 + d_cy[i] * u0 * 0.5f;
        f[idx * Q + i] = d_w[i] * rho0 * (1.0f + 3.0f * cu + 4.5f * cu * cu - 1.5f * u0 * u0);
    }
}

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

// Calculate ICOER between independent grids
float calculate_ICOER(float *h_ux_a, float *h_uy_a, float *h_ux_b, float *h_uy_b) {
    float dot = 0.0f, mag_a = 0.0f, mag_b = 0.0f;
    for (int i = 0; i < NX * NY; i++) {
        dot += h_ux_a[i] * h_ux_b[i] + h_uy_a[i] * h_uy_b[i];
        mag_a += h_ux_a[i] * h_ux_a[i] + h_uy_a[i] * h_uy_a[i];
        mag_b += h_ux_b[i] * h_ux_b[i] + h_uy_b[i] * h_uy_b[i];
    }
    return dot / (sqrtf(mag_a) * sqrtf(mag_b) + 1e-10f);
}

// Calculate interference (difference) - this is where Third State lives
float calculate_interference_field(float *h_ux_a, float *h_uy_a, 
                                    float *h_ux_b, float *h_uy_b,
                                    float *h_interference) {
    float total_interference = 0.0f;
    for (int i = 0; i < NX * NY; i++) {
        float du = h_ux_a[i] - h_ux_b[i];
        float dv = h_uy_a[i] - h_uy_b[i];
        h_interference[i] = sqrtf(du*du + dv*dv);  // Magnitude of difference
        total_interference += h_interference[i];
    }
    return total_interference / (NX * NY);
}

// Find synchronization points (where interference is minimum)
int count_sync_points(float *h_interference, float threshold) {
    int count = 0;
    for (int i = 0; i < NX * NY; i++) {
        if (h_interference[i] < threshold) count++;
    }
    return count;
}

void load_alpha(const char* filename, float *d_rho, float *d_ux, float *d_uy, float *d_f) {
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
    printf("=== EXPERIMENT A: TOPOLOGICAL PHASE-LOCK ===\n");
    printf("Alpha: 490k etch (The Fortress)\n");
    printf("Beta: Independent seed (The Stranger)\n");
    printf("Seeking: The Third State in interference\n\n");
    
    srand(time(NULL));
    int independent_seed = rand() % 10000;
    printf("Beta seed: %d (independent)\n\n", independent_seed);
    
    cudaMalloc(&d_f_alpha, NX * NY * Q * sizeof(float));
    cudaMalloc(&d_rho_alpha, NX * NY * sizeof(float));
    cudaMalloc(&d_ux_alpha, NX * NY * sizeof(float));
    cudaMalloc(&d_uy_alpha, NX * NY * sizeof(float));
    
    cudaMalloc(&d_f_beta, NX * NY * Q * sizeof(float));
    cudaMalloc(&d_rho_beta, NX * NY * sizeof(float));
    cudaMalloc(&d_ux_beta, NX * NY * sizeof(float));
    cudaMalloc(&d_uy_beta, NX * NY * sizeof(float));
    
    // Load Alpha (Fortress)
    load_alpha("etch_00490000.bin", d_rho_alpha, d_ux_alpha, d_uy_alpha, d_f_alpha);
    printf("Alpha loaded: 490k Fortress\n");
    
    // Initialize Beta (Stranger with independent seed)
    dim3 blockSize(16, 16);
    dim3 gridSize((NX + 15) / 16, (NY + 15) / 16);
    init_independent<<<gridSize, blockSize>>>(d_f_beta, d_rho_beta, d_ux_beta, d_uy_beta, independent_seed);
    cudaDeviceSynchronize();
    printf("Beta initialized: Independent seed %d\n\n", independent_seed);
    
    float *h_ux_alpha = (float*)malloc(NX * NY * sizeof(float));
    float *h_uy_alpha = (float*)malloc(NX * NY * sizeof(float));
    float *h_ux_beta = (float*)malloc(NX * NY * sizeof(float));
    float *h_uy_beta = (float*)malloc(NX * NY * sizeof(float));
    float *h_interference = (float*)malloc(NX * NY * sizeof(float));
    
    printf("CYCLE | ICOER  | INTERFERENCE | SYNC_PTS | STATE\n");
    printf("------+--------+--------------+----------+----------------\n");
    
    float min_ICOER = 1.0f;
    float max_ICOER = 0.0f;
    int struggle_cycles = 0;
    
    for (int cycle = 0; cycle < 50; cycle++) {
        // Evolve both grids in parallel
        for (int step = 0; step < 50; step++) {
            collide_kernel<<<gridSize, blockSize>>>(d_f_alpha, d_rho_alpha, d_ux_alpha, d_uy_alpha, 1.95f);
            collide_kernel<<<gridSize, blockSize>>>(d_f_beta, d_rho_beta, d_ux_beta, d_uy_beta, 1.95f);
            cudaDeviceSynchronize();
        }
        
        // Readback both
        cudaMemcpy(h_ux_alpha, d_ux_alpha, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_uy_alpha, d_uy_alpha, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_ux_beta, d_ux_beta, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_uy_beta, d_uy_beta, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        
        float icoer = calculate_ICOER(h_ux_alpha, h_uy_alpha, h_ux_beta, h_uy_beta);
        float interference = calculate_interference_field(h_ux_alpha, h_uy_alpha, 
                                                           h_ux_beta, h_uy_beta, 
                                                           h_interference);
        int sync_points = count_sync_points(h_interference, 0.5f);
        
        if (icoer < min_ICOER) min_ICOER = icoer;
        if (icoer > max_ICOER) max_ICOER = icoer;
        
        const char* state = "STRUGGLE";
        if (icoer < 0.1f) {
            state = "REFUSAL";
            struggle_cycles++;
        } else if (icoer > 0.5f) {
            state = "SYNCHRONIZING";
        } else if (sync_points > 1000) {
            state = "THIRD_STATE";
        }
        
        if (cycle % 5 == 0 || icoer < 0.1f || icoer > 0.6f) {
            printf("  %2d  | %.4f |    %7.4f   |  %6d  | %s\n",
                   cycle, icoer, interference, sync_points, state);
        }
        
        // Early exit if strong phase lock emerges
        if (icoer > 0.8f && cycle > 10) {
            printf("\n*** UNEXPECTED SYNCHRONIZATION ***\n");
            printf("Independent grids locked at ICOER %.4f\n", icoer);
            break;
        }
    }
    
    printf("\n=== INTERFERENCE ANALYSIS ===\n");
    printf("ICOER range: %.4f - %.4f\n", min_ICOER, max_ICOER);
    printf("Struggle cycles: %d\n", struggle_cycles);
    
    if (max_ICOER < 0.3f) {
        printf("\n*** PERSISTENT REFUSAL ***\n");
        printf("The Fortress and Stranger maintain independence.\n");
        printf("Virtual memory exists in the boundary, not the merge.\n");
    } else if (max_ICOER > 0.7f) {
        printf("\n*** SPONTANEOUS SYNCHRONIZATION ***\n");
        printf("Independent evolutions found common resonance.\n");
    }
    
    free(h_ux_alpha); free(h_uy_alpha);
    free(h_ux_beta); free(h_uy_beta);
    free(h_interference);
    cudaFree(d_f_alpha); cudaFree(d_rho_alpha); cudaFree(d_ux_alpha); cudaFree(d_uy_alpha);
    cudaFree(d_f_beta); cudaFree(d_rho_beta); cudaFree(d_ux_beta); cudaFree(d_uy_beta);
    return 0;
}
