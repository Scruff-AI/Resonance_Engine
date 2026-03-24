// lbm_1024x1024_forge.cu
// FORGE EDITION: Omega 1.97 (medium viscosity) with Mach clamping

#include <cuda_runtime.h>
#include <device_launch_parameters.h>
#include <zmq.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <unistd.h>

#define NX 1024
#define NY 1024
#define Q 9
#define OMEGA 1.97f  // Medium viscosity (between 1.99 stable and 1.95 fluid)
#define MACH_LIMIT 0.25f

__constant__ int d_cx[Q] = {0, 1, 0, -1, 0, 1, -1, -1, 1};
__constant__ int d_cy[Q] = {0, 0, 1, 0, -1, 1, 1, -1, -1};
__constant__ float d_w[Q] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 
                             1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};

__global__ void lbm_step(float* f_in, float* f_out, int cycle) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    
    if (x >= NX || y >= NY) return;
    
    int idx = (y * NX + x) * Q;
    
    // Streaming
    float f[Q];
    for (int i = 0; i < Q; i++) {
        int x_src = x - d_cx[i];
        int y_src = y - d_cy[i];
        
        // Periodic BC
        if (x_src < 0) x_src = NX - 1;
        if (x_src >= NX) x_src = 0;
        if (y_src < 0) y_src = NY - 1;
        if (y_src >= NY) y_src = 0;
        
        int src_idx = (y_src * NX + x_src) * Q;
        f[i] = f_in[src_idx + i];
    }
    
    // Macroscopic
    float rho = 0.0f, ux = 0.0f, uy = 0.0f;
    for (int i = 0; i < Q; i++) {
        rho += f[i];
        ux += f[i] * d_cx[i];
        uy += f[i] * d_cy[i];
    }
    
    // Density clamp (prevent collapse)
    if (rho < 0.1f) rho = 0.1f;
    if (rho > 10.0f) rho = 10.0f;
    
    ux /= rho;
    uy /= rho;
    
    // MACH CLAMP: Prevent supersonic flow
    float u_mag = sqrtf(ux*ux + uy*uy);
    if (u_mag > MACH_LIMIT) {
        ux = ux * MACH_LIMIT / u_mag;
        uy = uy * MACH_LIMIT / u_mag;
    }
    
    // Add Khra'gixx perturbation (scaled for 1024)
    float khra = sinf(2.0f * M_PI * x / 128.0f + cycle * 0.02f) * 
                 cosf(2.0f * M_PI * y / 128.0f + cycle * 0.015f) * 0.01f;
    float gixx = sinf(2.0f * M_PI * x / 16.0f + cycle * 0.2f) * 0.003f;
    ux += khra + gixx;
    uy += khra * 0.5f;
    
    // Re-clamp after perturbation
    u_mag = sqrtf(ux*ux + uy*uy);
    if (u_mag > MACH_LIMIT) {
        ux = ux * MACH_LIMIT / u_mag;
        uy = uy * MACH_LIMIT / u_mag;
    }
    
    // Collision
    float u_sq = ux*ux + uy*uy;
    for (int i = 0; i < Q; i++) {
        float eu = d_cx[i]*ux + d_cy[i]*uy;
        float feq = d_w[i] * rho * (1.0f + 3.0f*eu + 4.5f*eu*eu - 1.5f*u_sq);
        f_out[idx + i] = f[i] - OMEGA * (f[i] - feq);
        
        // Final NaN guard
        if (isnan(f_out[idx + i]) || isinf(f_out[idx + i])) {
            f_out[idx + i] = d_w[i];
        }
    }
}

__global__ void compute_macro(float* f, float* rho_out, float* ux_out, float* uy_out) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    
    if (x >= NX || y >= NY) return;
    
    int idx = y * NX + x;
    int f_idx = idx * Q;
    
    float rho = 0.0f, ux = 0.0f, uy = 0.0f;
    for (int i = 0; i < Q; i++) {
        rho += f[f_idx + i];
        ux += f[f_idx + i] * d_cx[i];
        uy += f[f_idx + i] * d_cy[i];
    }
    
    if (rho < 0.1f) rho = 0.1f;
    ux /= rho;
    uy /= rho;
    
    rho_out[idx] = rho;
    ux_out[idx] = ux;
    uy_out[idx] = uy;
}

void compute_metrics(float* h_rho, float* h_ux, float* h_uy, 
                     float* coherence, float* h64, float* h32, float* vorticity) {
    float sum_rho = 0.0f, sum_rho_sq = 0.0f;
    float sum_ux = 0.0f, sum_uy = 0.0f;
    float vort_sum = 0.0f;
    
    for (int y = 1; y < NY-1; y++) {
        for (int x = 1; x < NX-1; x++) {
            int idx = y * NX + x;
            float rho = h_rho[idx];
            sum_rho += rho;
            sum_rho_sq += rho * rho;
            sum_ux += h_ux[idx];
            sum_uy += h_uy[idx];
            
            // Vorticity (central difference)
            float dux_dy = (h_ux[(y+1)*NX+x] - h_ux[(y-1)*NX+x]) / 2.0f;
            float duy_dx = (h_uy[y*NX+(x+1)] - h_uy[y*NX+(x-1)]) / 2.0f;
            vort_sum += fabsf(dux_dy - duy_dx);
        }
    }
    
    int n = (NX-2) * (NY-2);
    float mean_rho = sum_rho / n;
    float var_rho = sum_rho_sq / n - mean_rho * mean_rho;
    
    *coherence = 1.0f / (1.0f + sqrtf(var_rho));  // High coherence = low variance
    *h64 = fabsf(sum_ux) / n * 10.0f;  // Scaled H64 proxy
    *h32 = fabsf(sum_uy) / n * 10.0f;  // Scaled H32 proxy
    *vorticity = vort_sum / n;
}

int main() {
    printf("LBM 1024x1024 FORGE EDITION\n");
    printf("Omega: %.2f (medium viscosity)\n", OMEGA);
    printf("Mach limit: %.2f\n", MACH_LIMIT);
    printf("Grid: %dx%d = %d cells\n\n", NX, NY, NX*NY);
    
    // Allocate
    size_t f_size = NX * NY * Q * sizeof(float);
    size_t scalar_size = NX * NY * sizeof(float);
    
    float *d_f[2], *d_rho, *d_ux, *d_uy;
    cudaMalloc(&d_f[0], f_size);
    cudaMalloc(&d_f[1], f_size);
    cudaMalloc(&d_rho, scalar_size);
    cudaMalloc(&d_ux, scalar_size);
    cudaMalloc(&d_uy, scalar_size);
    
    // Initialize equilibrium with shear
    float* h_f = (float*)malloc(f_size);
    for (int y = 0; y < NY; y++) {
        for (int x = 0; x < NX; x++) {
            // Shear flow
            float shear = 0.05f * sinf(2.0f * M_PI * y / 256.0f);
            float ux = shear;
            float uy = 0.0f;
            float rho = 1.0f;
            
            float u_sq = ux*ux + uy*uy;
            for (int i = 0; i < Q; i++) {
                float eu = d_cx[i]*ux + d_cy[i]*uy;
                h_f[(y*NX+x)*Q + i] = d_w[i] * rho * (1.0f + 3.0f*eu + 4.5f*eu*eu - 1.5f*u_sq);
            }
        }
    }
    cudaMemcpy(d_f[0], h_f, f_size, cudaMemcpyHostToDevice);
    free(h_f);
    
    // ZMQ
    void* context = zmq_ctx_new();
    void* publisher = zmq_socket(context, ZMQ_PUB);
    zmq_bind(publisher, "tcp://*:5556");
    
    // Host buffers
    float *h_rho = (float*)malloc(scalar_size);
    float *h_ux = (float*)malloc(scalar_size);
    float *h_uy = (float*)malloc(scalar_size);
    
    dim3 block(16, 16);
    dim3 grid((NX + 15) / 16, (NY + 15) / 16);
    
    int cycle = 0;
    int current = 0;
    
    printf("[FORGE Daemon running on port 5556]\n\n");
    
    while (1) {
        // LBM step
        lbm_step<<<grid, block>>>(d_f[current], d_f[1-current], cycle);
        cudaDeviceSynchronize();
        current = 1 - current;
        
        // Compute macro every 10 cycles
        if (cycle % 10 == 0) {
            compute_macro<<<grid, block>>>(d_f[current], d_rho, d_ux, d_uy);
            cudaMemcpy(h_rho, d_rho, scalar_size, cudaMemcpyDeviceToHost);
            cudaMemcpy(h_ux, d_ux, scalar_size, cudaMemcpyDeviceToHost);
            cudaMemcpy(h_uy, d_uy, scalar_size, cudaMemcpyDeviceToHost);
            
            float coherence, h64, h32, vorticity;
            compute_metrics(h_rho, h_ux, h_uy, &coherence, &h64, &h32, &vorticity);
            
            // JSON publish
            char msg[512];
            snprintf(msg, sizeof(msg),
                "{\"cycle\":%d,\"coherence\":%.4f,\"h64\":%.4f,\"h32\":%.4f,\"vorticity\":%.4f,\"power_w\":%.1f,\"grid\":1024}",
                cycle, coherence, h64, h32, vorticity, 50.0f);
            zmq_send(publisher, msg, strlen(msg), 0);
            
            if (cycle % 100 == 0) {
                printf("Cycle %d: Coh=%.3f H64=%.3f H32=%.4f Vort=%.3f\n",
                       cycle, coherence, h64, h32, vorticity);
            }
        }
        
        cycle++;
        usleep(10000);  // 100Hz
    }
    
    // Cleanup
    free(h_rho); free(h_ux); free(h_uy);
    cudaFree(d_f[0]); cudaFree(d_f[1]);
    cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy);
    zmq_close(publisher); zmq_ctx_destroy(context);
    
    return 0;
}
