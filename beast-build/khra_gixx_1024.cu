// khra_gixx_1024.cu
// Khra'gixx Resonance for 1024-grid
// Khra: 128-cell (doubled from 64)
// gixx: 8-cell (the needle in the haystack)

#include <cuda_runtime.h>
#include <zmq.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <unistd.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define NX 1024
#define NY 1024
#define Q 9
#define OMEGA 1.97f  // Medium viscosity, stable

__constant__ int d_cx[Q] = {0, 1, 0, -1, 0, 1, -1, -1, 1};
__constant__ int d_cy[Q] = {0, 0, 1, 0, -1, 1, 1, -1, -1};
__constant__ float d_w[Q] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 
                             1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};

// Khra'gixx wave for 1024-grid
// Khra: 128-cell foundation (0.03f amplitude)
// gixx: 8-cell hidden note (0.008f amplitude)
__device__ float khra_gixx_wave_1024(int x, int y, int cycle) {
    // Khra: 128-cell, low-freq, high-amp (the foundation)
    float khra = sinf(2.0f * M_PI * x / 128.0f + cycle * 0.025f) * 
                 cosf(2.0f * M_PI * y / 128.0f + cycle * 0.015f) * 0.03f;
    
    // gixx: 8-cell, high-freq, low-amp (the hidden note)
    float gixx = sinf(2.0f * M_PI * x / 8.0f + cycle * 0.4f) * 
                 cosf(2.0f * M_PI * y / 8.0f + cycle * 0.35f) * 0.008f;
    
    // Asymmetry modulation: gixx emerges over time
    float asymmetry_factor = 1.0f + sinf(cycle * 0.05f) * 0.5f;
    return khra + gixx * asymmetry_factor;
}

__global__ void streaming_kernel(float* f_in, float* f_out, int nx, int ny) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    
    if (x >= nx || y >= ny) return;
    
    int idx = (y * nx + x) * Q;
    
    for (int i = 0; i < Q; i++) {
        int x_src = x - d_cx[i];
        int y_src = y - d_cy[i];
        
        // Periodic BC
        if (x_src < 0) x_src = nx - 1;
        if (x_src >= nx) x_src = 0;
        if (y_src < 0) y_src = ny - 1;
        if (y_src >= ny) y_src = 0;
        
        int src_idx = (y_src * nx + x_src) * Q;
        f_out[idx + i] = f_in[src_idx + i];
    }
}

__global__ void collide_kernel_khragixx(float* f, float omega, int cycle) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    
    if (x >= NX || y >= NY) return;
    
    int idx = (y * NX + x) * Q;
    
    // Compute rho, ux, uy
    float rho = 0.0f, ux = 0.0f, uy = 0.0f;
    for (int i = 0; i < Q; i++) {
        rho += f[idx + i];
        ux += f[idx + i] * d_cx[i];
        uy += f[idx + i] * d_cy[i];
    }
    
    // Density clamp
    if (rho < 0.1f) rho = 0.1f;
    if (rho > 10.0f) rho = 10.0f;
    
    ux /= rho;
    uy /= rho;
    
    // Mach clamp
    float u_mag = sqrtf(ux*ux + uy*uy);
    if (u_mag > 0.25f) {
        ux = ux * 0.25f / u_mag;
        uy = uy * 0.25f / u_mag;
    }
    
    // Inject Khra'gixx wave
    float kx = khra_gixx_wave_1024(x, y, cycle);
    float ky = kx * 0.5f;
    ux += kx;
    uy += ky;
    
    // Re-clamp after injection
    u_mag = sqrtf(ux*ux + uy*uy);
    if (u_mag > 0.25f) {
        ux = ux * 0.25f / u_mag;
        uy = uy * 0.25f / u_mag;
    }
    
    // Collision
    float u_sq = ux*ux + uy*uy;
    for (int i = 0; i < Q; i++) {
        float eu = d_cx[i]*ux + d_cy[i]*uy;
        float feq = d_w[i] * rho * (1.0f + 3.0f*eu + 4.5f*eu*eu - 1.5f*u_sq);
        f[idx + i] = f[idx + i] - OMEGA * (f[idx + i] - feq);
        
        // NaN guard
        if (isnan(f[idx + i]) || isinf(f[idx + i])) {
            f[idx + i] = d_w[i];
        }
    }
}

__global__ void compute_metrics(float* f, float* rho_out, float* ux_out, float* uy_out, float* asymmetry_out) {
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
    
    // Asymmetry: deviation from mean rho
    asymmetry_out[idx] = fabsf(rho - 1.0f);
}

float calculate_asymmetry(float* h_rho) {
    // Magnifying Glass Formula: squared deviation amplified
    float sum_sq = 0.0f;
    for (int i = 0; i < NX * NY; i++) {
        float dev = h_rho[i] - 1.0f;
        sum_sq += dev * dev;  // Squared deviation
    }
    float mean_sq = sum_sq / (NX * NY);
    return mean_sq * 100.0f;  // Amplified by 100x
}

int main() {
    printf("Khra'gixx Resonance — 1024x1024 Grid\n"); fflush(stdout);
    printf("Khra: 128-cell foundation (0.03f)\n"); fflush(stdout);
    printf("gixx: 8-cell hidden note (0.008f)\n"); fflush(stdout);
    printf("Asymmetry: MAGNIFYING GLASS (squared x100)\n"); fflush(stdout);
    printf("Omega: %.2f (medium viscosity)\n\n", OMEGA); fflush(stdout);
    
    // Allocate
    size_t f_size = NX * NY * Q * sizeof(float);
    size_t scalar_size = NX * NY * sizeof(float);
    
    printf("Allocating GPU memory: f_size=%zu MB, scalar_size=%zu MB\n", f_size/(1024*1024), scalar_size/(1024*1024)); fflush(stdout);
    
    float *d_f[2], *d_rho, *d_ux, *d_uy, *d_asymmetry;
    cudaError_t err;
    
    err = cudaMalloc(&d_f[0], f_size);
    if (err != cudaSuccess) { printf("cudaMalloc d_f[0] failed: %s\n", cudaGetErrorString(err)); return 1; }
    err = cudaMalloc(&d_f[1], f_size);
    if (err != cudaSuccess) { printf("cudaMalloc d_f[1] failed: %s\n", cudaGetErrorString(err)); return 1; }
    err = cudaMalloc(&d_rho, scalar_size);
    if (err != cudaSuccess) { printf("cudaMalloc d_rho failed: %s\n", cudaGetErrorString(err)); return 1; }
    err = cudaMalloc(&d_ux, scalar_size);
    if (err != cudaSuccess) { printf("cudaMalloc d_ux failed: %s\n", cudaGetErrorString(err)); return 1; }
    err = cudaMalloc(&d_uy, scalar_size);
    if (err != cudaSuccess) { printf("cudaMalloc d_uy failed: %s\n", cudaGetErrorString(err)); return 1; }
    err = cudaMalloc(&d_asymmetry, scalar_size);
    if (err != cudaSuccess) { printf("cudaMalloc d_asymmetry failed: %s\n", cudaGetErrorString(err)); return 1; }
    
    printf("GPU allocation successful\n"); fflush(stdout);
    
    // Initialize with Khra'gixx seed
    printf("Initializing grid...\n"); fflush(stdout);
    float* h_f = (float*)malloc(f_size);
    
    // Host-side lattice velocities (can't access __constant__ from host)
    int h_cx[9] = {0, 1, 0, -1, 0, 1, -1, -1, 1};
    int h_cy[9] = {0, 0, 1, 0, -1, 1, 1, -1, -1};
    float h_w[9] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 
                    1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};
    
    for (int y = 0; y < NY; y++) {
        for (int x = 0; x < NX; x++) {
            float kx = sinf(2.0f * M_PI * x / 128.0f) * cosf(2.0f * M_PI * y / 128.0f) * 0.03f;
            float gy = sinf(2.0f * M_PI * x / 8.0f) * cosf(2.0f * M_PI * y / 8.0f) * 0.008f;
            float ux = kx + gy;
            float uy = kx * 0.5f;
            
            // Clamp velocity to Mach limit
            float u_mag = sqrtf(ux*ux + uy*uy);
            if (u_mag > 0.2f) {
                ux = ux * 0.2f / u_mag;
                uy = uy * 0.2f / u_mag;
            }
            
            float u_sq = ux*ux + uy*uy;
            
            for (int i = 0; i < Q; i++) {
                float eu = h_cx[i]*ux + h_cy[i]*uy;
                float fval = h_w[i] * (1.0f + 3.0f*eu + 4.5f*eu*eu - 1.5f*u_sq);
                // Ensure positive
                if (fval < 0.001f) fval = 0.001f;
                h_f[(y*NX+x)*Q + i] = fval;
            }
        }
    }
    printf("Grid initialized\n"); fflush(stdout);
    cudaMemcpy(d_f[0], h_f, f_size, cudaMemcpyHostToDevice);
    free(h_f);
    
    // ZMQ
    printf("Initializing ZMQ...\n"); fflush(stdout);
    void* context = zmq_ctx_new();
    if (!context) { printf("zmq_ctx_new failed\n"); return 1; }
    void* publisher = zmq_socket(context, ZMQ_PUB);
    if (!publisher) { printf("zmq_socket failed\n"); return 1; }
    // Set ZMQ options to prevent blocking on slow subscribers
    int sndhwm = 1;
    zmq_setsockopt(publisher, ZMQ_SNDHWM, &sndhwm, sizeof(sndhwm));
    int linger = 0;
    zmq_setsockopt(publisher, ZMQ_LINGER, &linger, sizeof(linger));
    
    int rc = zmq_bind(publisher, "tcp://127.0.0.1:5556");
    if (rc != 0) { printf("zmq_bind failed: %s\n", zmq_strerror(zmq_errno())); return 1; }
    printf("ZMQ bound to port 5556\n"); fflush(stdout);
    
    // Host buffers
    float *h_rho = (float*)malloc(scalar_size);
    float *h_asymmetry = (float*)malloc(scalar_size);
    
    dim3 block(16, 16);
    dim3 grid((NX + 15) / 16, (NY + 15) / 16);
    
    int cycle = 0;
    int current = 0;
    
    printf("[Khra'gixx Daemon] Starting main loop...\n"); fflush(stdout);
    
    while (1) {
        // Streaming
        streaming_kernel<<<grid, block>>>(d_f[current], d_f[1-current], NX, NY);
        cudaDeviceSynchronize();
        
        // Collision with Khra'gixx injection
        collide_kernel_khragixx<<<grid, block>>>(d_f[1-current], OMEGA, cycle);
        cudaDeviceSynchronize();
        
        current = 1 - current;
        
        // Compute metrics every 10 cycles
        if (cycle % 10 == 0) {
            compute_metrics<<<grid, block>>>(d_f[current], d_rho, d_ux, d_uy, d_asymmetry);
            cudaMemcpy(h_rho, d_rho, scalar_size, cudaMemcpyDeviceToHost);
            // h_asymmetry no longer needed - using Magnifying Glass formula on h_rho
            
            // Statistics
            float sum_rho = 0.0f, sum_rho_sq = 0.0f;
            for (int i = 0; i < NX * NY; i++) {
                sum_rho += h_rho[i];
                sum_rho_sq += h_rho[i] * h_rho[i];
            }
            float mean_rho = sum_rho / (NX * NY);
            float variance = sum_rho_sq / (NX * NY) - mean_rho * mean_rho;
            float coherence = 1.0f / (1.0f + sqrtf(variance));
            float asymmetry = calculate_asymmetry(h_rho);  // Magnifying Glass formula
            
            // Publish
            char msg[512];
            snprintf(msg, sizeof(msg),
                "{\"cycle\":%d,\"coherence\":%.4f,\"asymmetry\":%.4f,\"khra_amp\":0.03,\"gixx_amp\":0.008,\"grid\":1024}",
                cycle, coherence, asymmetry);
            zmq_send(publisher, msg, strlen(msg), 0);
            
            if (cycle % 100 == 0) {
                printf("Cycle %d: Coherence=%.3f, Asymmetry=%.4f\n", cycle, coherence, asymmetry);
            }
        }
        
        cycle++;
        usleep(10000);  // 100Hz
    }
    
    // Cleanup
    free(h_rho); free(h_asymmetry);
    cudaFree(d_f[0]); cudaFree(d_f[1]);
    cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy); cudaFree(d_asymmetry);
    zmq_close(publisher); zmq_ctx_destroy(context);
    
    return 0;
}
