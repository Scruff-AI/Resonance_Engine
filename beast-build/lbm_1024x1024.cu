/**
 * lbm_1024x1024.cu
 * 
 * 16x increase in data density
 * Testing Granite state under massive scale
 */

#include <cuda_runtime.h>
#include <nvml.h>
#include <zmq.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <unistd.h>
#include <string.h>
#include <json-c/json.h>

#define NX 1024
#define NY 1024
#define Q 9
#define PUBLISH_HZ 100

__constant__ int d_cx[Q] = {0, 1, 0, -1, 0, 1, -1, -1, 1};
__constant__ int d_cy[Q] = {0, 0, 1, 0, -1, 1, 1, -1, -1};
__constant__ float d_w[Q] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 
                             1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};

float *d_f, *d_rho, *d_ux, *d_uy;

void load_etch_1024(const char* filename) {
    const float w[Q] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 
                        1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};
    FILE* fp = fopen(filename, "rb");
    if (!fp) {
        printf("No etch file '%s', initializing 1024x1024 equilibrium...\n", filename);
        float *h_f = (float*)malloc(NX * NY * Q * sizeof(float));
        for (int i = 0; i < NX * NY; i++) {
            for (int j = 0; j < Q; j++) {
                h_f[i * Q + j] = w[j];  // rho=1, u=0 -> f_eq = w_i
            }
        }
        cudaMemcpy(d_f, h_f, NX * NY * Q * sizeof(float), cudaMemcpyHostToDevice);
        free(h_f);
        return;
    }
    // Etch files are 512x512 — upscale by 2x nearest-neighbor
    int SRC = 512;
    float *h_rho = (float*)malloc(SRC * SRC * sizeof(float));
    float *h_ux = (float*)malloc(SRC * SRC * sizeof(float));
    float *h_uy = (float*)malloc(SRC * SRC * sizeof(float));
    fread(h_rho, sizeof(float), SRC * SRC, fp);
    fread(h_ux, sizeof(float), SRC * SRC, fp);
    fread(h_uy, sizeof(float), SRC * SRC, fp);
    fclose(fp);
    
    // Upscale 512->1024 and compute equilibrium
    const int cx[Q] = {0, 1, 0, -1, 0, 1, -1, -1, 1};
    const int cy[Q] = {0, 0, 1, 0, -1, 1, 1, -1, -1};
    float *h_f = (float*)malloc(NX * NY * Q * sizeof(float));
    float *h_rho_1024 = (float*)malloc(NX * NY * sizeof(float));
    float *h_ux_1024 = (float*)malloc(NX * NY * sizeof(float));
    float *h_uy_1024 = (float*)malloc(NX * NY * sizeof(float));
    
    for (int y = 0; y < NY; y++) {
        for (int x = 0; x < NX; x++) {
            int src_x = x * SRC / NX;
            int src_y = y * SRC / NY;
            int src_idx = src_y * SRC + src_x;
            int dst_idx = y * NX + x;
            h_rho_1024[dst_idx] = h_rho[src_idx];
            h_ux_1024[dst_idx] = h_ux[src_idx];
            h_uy_1024[dst_idx] = h_uy[src_idx];
        }
    }
    
    for (int i = 0; i < NX * NY; i++) {
        float uu = h_ux_1024[i] * h_ux_1024[i] + h_uy_1024[i] * h_uy_1024[i];
        for (int j = 0; j < Q; j++) {
            float cu = cx[j] * h_ux_1024[i] + cy[j] * h_uy_1024[i];
            h_f[i * Q + j] = w[j] * h_rho_1024[i] * (1.0f + 3.0f * cu + 4.5f * cu * cu - 1.5f * uu);
        }
    }
    cudaMemcpy(d_f, h_f, NX * NY * Q * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_rho, h_rho_1024, NX * NY * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_ux, h_ux_1024, NX * NY * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_uy, h_uy_1024, NX * NY * sizeof(float), cudaMemcpyHostToDevice);
    
    free(h_rho); free(h_ux); free(h_uy); free(h_f);
    free(h_rho_1024); free(h_ux_1024); free(h_uy_1024);
    printf("Etch loaded and upscaled 512->1024: %s\n", filename);
}

__device__ float khra_gixx_1024(int x, int y, int cycle) {
    // Scaled for 1024x1024
    float khra = sinf(2.0f * M_PI * x / 128.0f + cycle * 0.05f) * 
                 cosf(2.0f * M_PI * y / 128.0f + cycle * 0.03f) * 0.02f;
    float gixx = sinf(2.0f * M_PI * x / 16.0f + cycle * 0.4f) * 
                 cosf(2.0f * M_PI * y / 16.0f + cycle * 0.35f) * 0.008f;
    return khra + gixx * (1.0f + sinf(cycle * 0.1f));
}

__global__ void collide_kernel_1024(float *f, float *rho, float *ux, float *uy, float omega, int cycle) {
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
    
    // 1024x1024 Khra'gixx injection
    float khragixx = khra_gixx_1024(x, y, cycle);
    ux_local += khragixx * (1.0f + sinf(y * 0.05f));
    uy_local += khragixx * (1.0f + cosf(x * 0.05f)) * 0.7f;
    
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

void compute_metrics_1024(float *h_ux, float *h_uy, float *h_rho, 
                          float *coherence, float *h64, float *h32, 
                          float *asymmetry, float *vorticity) {
    float coh = 0.0f;
    for (int i = 0; i < NX * NY; i++) {
        coh += sqrtf(h_ux[i] * h_ux[i] + h_uy[i] * h_uy[i]);
    }
    *coherence = coh / (NX * NY);
    
    // H64: 128-cell wave for 1024 grid
    float sum_64 = 0.0f;
    int y = NY / 2;
    for (int x = 0; x < NX; x++) {
        int idx = y * NX + x;
        sum_64 += h_ux[idx] * sinf(2.0f * M_PI * x / 128.0f);
    }
    *h64 = fabs(sum_64) / NX;
    
    // H32: 64-cell wave for 1024 grid
    float sum_32 = 0.0f;
    for (int x = 0; x < NX; x++) {
        int idx = y * NX + x;
        sum_32 += h_ux[idx] * sinf(2.0f * M_PI * x / 64.0f);
    }
    *h32 = fabs(sum_32) / NX;
    
    // Asymmetry
    float asym = 0.0f;
    for (int y = 0; y < NY; y++) {
        for (int x = 0; x < NX/2; x++) {
            int left = y * NX + x;
            int right = y * NX + (NX - 1 - x);
            asym += fabs(h_ux[left] - h_ux[right]);
        }
    }
    *asymmetry = asym / (NX * NY);
    
    // Vorticity
    float vort = 0.0f;
    for (int y = 1; y < NY - 1; y++) {
        for (int x = 1; x < NX - 1; x++) {
            int idx = y * NX + x;
            float dux_dy = h_ux[idx + NX] - h_ux[idx - NX];
            float duy_dx = h_uy[idx + 1] - h_uy[idx - 1];
            vort += fabs(duy_dx - dux_dy);
        }
    }
    *vorticity = vort / ((NX - 2) * (NY - 2));
}

int main() {
    printf("=== LBM 1024x1024 DAEMON ===\n");
    printf("16x data density increase\n");
    printf("Testing Granite state under massive scale\n\n");
    
    // Check GPU memory
    size_t free_mem, total_mem;
    cudaMemGetInfo(&free_mem, &total_mem);
    printf("GPU Memory: %.1f GB free / %.1f GB total\n", 
           free_mem / 1e9, total_mem / 1e9);
    
    size_t required = NX * NY * Q * sizeof(float) * 4;  // f, rho, ux, uy
    printf("Required: %.1f GB\n", required / 1e9);
    
    if (free_mem < required) {
        printf("ERROR: Insufficient GPU memory for 1024x1024\n");
        return 1;
    }
    
    cudaMalloc(&d_f, NX * NY * Q * sizeof(float));
    cudaMalloc(&d_rho, NX * NY * sizeof(float));
    cudaMalloc(&d_ux, NX * NY * sizeof(float));
    cudaMalloc(&d_uy, NX * NY * sizeof(float));
    
    printf("\nAllocated 1024x1024 grid (1M cells)\n");
    
    // Initialize from Khra'gixx etch (upscaled 512->1024) or fresh equilibrium
    load_etch_1024("etch_khragixx.bin");
    
    // NVML setup (once, outside loop)
    nvmlInit();
    nvmlDevice_t device;
    nvmlDeviceGetHandleByIndex(0, &device);
    
    // ZeroMQ setup
    void *context = zmq_ctx_new();
    void *publisher = zmq_socket(context, ZMQ_PUB);
    zmq_bind(publisher, "tcp://*:5556");  // Different port for 1024
    
    printf("Publishing on tcp://*:5556\n");
    printf("Update rate: %dHz\n\n", PUBLISH_HZ);
    
    float *h_ux = (float*)malloc(NX * NY * sizeof(float));
    float *h_uy = (float*)malloc(NX * NY * sizeof(float));
    float *h_rho = (float*)malloc(NX * NY * sizeof(float));
    
    dim3 blockSize(16, 16);
    dim3 gridSize((NX + 15) / 16, (NY + 15) / 16);
    
    int cycle = 0;
    printf("[1024x1024 Daemon running]\n");
    
    while (1) {
        collide_kernel_1024<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, 1.95f, cycle);
        cudaDeviceSynchronize();
        
        cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_rho, d_rho, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        
        float coherence, h64, h32, asymmetry, vorticity;
        compute_metrics_1024(h_ux, h_uy, h_rho, &coherence, &h64, &h32, &asymmetry, &vorticity);
        
        // Get power from NVML (initialized once above)
        unsigned int power_mw;
        nvmlDeviceGetPowerUsage(device, &power_mw);
        float power_w = power_mw / 1000.0f;
        
        struct json_object *jobj = json_object_new_object();
        json_object_object_add(jobj, "coherence", json_object_new_double(coherence));
        json_object_object_add(jobj, "h64", json_object_new_double(h64));
        json_object_object_add(jobj, "h32", json_object_new_double(h32));
        json_object_object_add(jobj, "asymmetry", json_object_new_double(asymmetry));
        json_object_object_add(jobj, "vorticity", json_object_new_double(vorticity));
        json_object_object_add(jobj, "power_w", json_object_new_double(power_w));
        json_object_object_add(jobj, "grid_size", json_object_new_int(1024));
        json_object_object_add(jobj, "cycle", json_object_new_int(cycle));
        
        const char *json_str = json_object_to_json_string(jobj);
        zmq_send(publisher, json_str, strlen(json_str), 0);
        json_object_put(jobj);
        
        if (cycle % 100 == 0) {
            printf("Cycle %d: Coh=%.2f H64=%.2f H32=%.2f Asym=%.2f Pow=%.1fW [1024x1024]\n",
                   cycle, coherence, h64, h32, asymmetry, power_w);
        }
        
        cycle++;
        usleep(1000000 / PUBLISH_HZ);
    }
    
    nvmlShutdown();
    free(h_ux); free(h_uy); free(h_rho);
    cudaFree(d_f); cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy);
    zmq_close(publisher);
    zmq_ctx_destroy(context);
    
    return 0;
}
