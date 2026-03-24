/**
 * lbm_cuda_daemon.cu
 * 
 * CUDA LBM daemon that publishes real-time grid state
 * to ZeroMQ for LBM-LLM bridge
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

#define NX 512
#define NY 512
#define Q 9
#define PUBLISH_HZ 100  // 100Hz = 10ms

__constant__ int d_cx[Q] = {0, 1, 0, -1, 0, 1, -1, -1, 1};
__constant__ int d_cy[Q] = {0, 0, 1, 0, -1, 1, 1, -1, -1};
__constant__ float d_w[Q] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 
                             1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};

// Device arrays
float *d_f, *d_rho, *d_ux, *d_uy;

void load_etch(const char* filename) {
    FILE* fp = fopen(filename, "rb");
    if (!fp) {
        printf("No etch file '%s' found, initializing equilibrium...\n", filename);
        // Fresh equilibrium: rho=1, ux=uy=0
        float *h_f = (float*)malloc(NX * NY * Q * sizeof(float));
        const float w[Q] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 
                            1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};
        for (int i = 0; i < NX * NY; i++) {
            for (int j = 0; j < Q; j++) {
                h_f[i * Q + j] = w[j]; // rho=1, u=0 → f_eq = w_i
            }
        }
        cudaMemcpy(d_f, h_f, NX * NY * Q * sizeof(float), cudaMemcpyHostToDevice);
        free(h_f);
        return;
    }
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
    printf("Etch loaded: %s\n", filename);
}

// Khra'gixx wave for live grid
__device__ float khra_gixx_live(int x, int y, int cycle) {
    float khra = sinf(2.0f * M_PI * x / 64.0f + cycle * 0.05f) * 
                 cosf(2.0f * M_PI * y / 64.0f + cycle * 0.03f) * 0.02f;
    float gixx = sinf(2.0f * M_PI * x / 8.0f + cycle * 0.4f) * 
                 cosf(2.0f * M_PI * y / 8.0f + cycle * 0.35f) * 0.008f;
    return khra + gixx * (1.0f + sinf(cycle * 0.1f));
}

__global__ void collide_kernel_daemon(float *f, float *rho, float *ux, float *uy, float omega, int cycle) {
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
    
    // Live Khra'gixx injection
    float khragixx = khra_gixx_live(x, y, cycle);
    ux_local += khragixx * (1.0f + sinf(y * 0.1f));
    uy_local += khragixx * (1.0f + cosf(x * 0.1f)) * 0.7f;
    
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

// Host: Compute metrics
void compute_metrics(float *h_ux, float *h_uy, float *h_rho, 
                      float *coherence, float *h64, float *h32, 
                      float *asymmetry, float *vorticity) {
    // Coherence: mean velocity magnitude
    float coh = 0.0f;
    for (int i = 0; i < NX * NY; i++) {
        coh += sqrtf(h_ux[i] * h_ux[i] + h_uy[i] * h_uy[i]);
    }
    *coherence = coh / (NX * NY);
    
    // H64: correlate with 64-cell wave
    float sum_64 = 0.0f;
    int y = NY / 2;
    for (int x = 0; x < NX; x++) {
        int idx = y * NX + x;
        sum_64 += h_ux[idx] * sinf(2.0f * M_PI * x / 64.0f);
    }
    *h64 = fabs(sum_64) / NX;
    
    // H32: correlate with 32-cell wave
    float sum_32 = 0.0f;
    for (int x = 0; x < NX; x++) {
        int idx = y * NX + x;
        sum_32 += h_ux[idx] * sinf(2.0f * M_PI * x / 32.0f);
    }
    *h32 = fabs(sum_32) / NX;
    
    // Asymmetry: left-right difference
    float asym = 0.0f;
    for (int y = 0; y < NY; y++) {
        for (int x = 0; x < NX/2; x++) {
            int left = y * NX + x;
            int right = y * NX + (NX - 1 - x);
            asym += fabs(h_ux[left] - h_ux[right]);
        }
    }
    *asymmetry = asym / (NX * NY);
    
    // Vorticity: curl of velocity field
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
    printf("=== LBM CUDA DAEMON ===\n");
    printf("Publishing real-time grid state to ZeroMQ\n\n");
    
    // CUDA setup
    cudaMalloc(&d_f, NX * NY * Q * sizeof(float));
    cudaMalloc(&d_rho, NX * NY * sizeof(float));
    cudaMalloc(&d_ux, NX * NY * sizeof(float));
    cudaMalloc(&d_uy, NX * NY * sizeof(float));
    
    // Initialize from Khra'gixx etch (or fresh equilibrium if file missing)
    load_etch("etch_khragixx.bin");
    
    // NVML setup (once, outside loop)
    nvmlInit();
    nvmlDevice_t device;
    nvmlDeviceGetHandleByIndex(0, &device);
    
    // ZeroMQ setup
    void *context = zmq_ctx_new();
    void *publisher = zmq_socket(context, ZMQ_PUB);
    zmq_bind(publisher, "tcp://*:5555");
    
    printf("Publishing on tcp://*:5555\n");
    printf("Update rate: %dHz\n\n", PUBLISH_HZ);
    
    // Host arrays
    float *h_ux = (float*)malloc(NX * NY * sizeof(float));
    float *h_uy = (float*)malloc(NX * NY * sizeof(float));
    float *h_rho = (float*)malloc(NX * NY * sizeof(float));
    
    dim3 blockSize(16, 16);
    dim3 gridSize((NX + 15) / 16, (NY + 15) / 16);
    
    int cycle = 0;
    
    printf("[Daemon running - Ctrl+C to stop]\n");
    
    while (1) {
        // Run LBM step
        collide_kernel_daemon<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, 1.95f, cycle);
        cudaDeviceSynchronize();
        
        // Copy to host
        cudaMemcpy(h_ux, d_ux, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_uy, d_uy, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_rho, d_rho, NX * NY * sizeof(float), cudaMemcpyDeviceToHost);
        
        // Compute metrics
        float coherence, h64, h32, asymmetry, vorticity;
        compute_metrics(h_ux, h_uy, h_rho, &coherence, &h64, &h32, &asymmetry, &vorticity);
        
        // Get power from NVML (initialized once above)
        unsigned int power_mw;
        nvmlDeviceGetPowerUsage(device, &power_mw);
        float power_w = power_mw / 1000.0f;
        
        // Build JSON
        struct json_object *jobj = json_object_new_object();
        json_object_object_add(jobj, "coherence", json_object_new_double(coherence));
        json_object_object_add(jobj, "h64", json_object_new_double(h64));
        json_object_object_add(jobj, "h32", json_object_new_double(h32));
        json_object_object_add(jobj, "asymmetry", json_object_new_double(asymmetry));
        json_object_object_add(jobj, "vorticity", json_object_new_double(vorticity));
        json_object_object_add(jobj, "power_w", json_object_new_double(power_w));
        json_object_object_add(jobj, "cycle", json_object_new_int(cycle));
        
        const char *json_str = json_object_to_json_string(jobj);
        
        // Publish
        zmq_send(publisher, json_str, strlen(json_str), 0);
        
        json_object_put(jobj);
        
        // Print status
        if (cycle % 100 == 0) {
            printf("Cycle %d: Coh=%.2f H64=%.2f H32=%.2f Asym=%.2f Pow=%.1fW\n",
                   cycle, coherence, h64, h32, asymmetry, power_w);
        }
        
        cycle++;
        usleep(1000000 / PUBLISH_HZ);  // 100Hz = 10ms
    }
    
    // Cleanup
    nvmlShutdown();
    free(h_ux); free(h_uy); free(h_rho);
    cudaFree(d_f); cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy);
    zmq_close(publisher);
    zmq_ctx_destroy(context);
    
    return 0;
}
