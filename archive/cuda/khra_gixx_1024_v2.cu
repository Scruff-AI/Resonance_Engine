// khra_gixx_1024_v2.cu
// Bidirectional daemon: PUB telemetry + SUB commands
// NVML hardware metadata in every frame
// Dynamic omega, khra_amp, gixx_amp via command channel
// Based on khra_gixx_1024_stable.cu (magnifying glass asymmetry)

#include <cuda_runtime.h>
#include <nvml.h>
#include <zmq.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <unistd.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define NX 1024
#define NY 1024
#define Q 9

#define CUDA_CHECK(call) do { \
    cudaError_t err = call; \
    if (err != cudaSuccess) { \
        fprintf(stderr, "CUDA error at %s:%d — %s\n", __FILE__, __LINE__, cudaGetErrorString(err)); \
        fflush(stderr); \
        exit(1); \
    } \
} while(0)

__constant__ int d_cx[Q] = {0, 1, 0, -1, 0, 1, -1, -1, 1};
__constant__ int d_cy[Q] = {0, 0, 1, 0, -1, 1, 1, -1, -1};
__constant__ float d_w[Q] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 
                             1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};

// Device-side parameters for wave function — updated via command channel
__device__ float d_khra_amp = 0.03f;
__device__ float d_gixx_amp = 0.008f;

__device__ float khra_gixx_wave_1024(int x, int y, int cycle) {
    float khra = sinf(2.0f * M_PI * x / 128.0f + cycle * 0.025f) * 
                 cosf(2.0f * M_PI * y / 128.0f + cycle * 0.015f) * d_khra_amp;
    float gixx = sinf(2.0f * M_PI * x / 8.0f + cycle * 0.4f) * 
                 cosf(2.0f * M_PI * y / 8.0f + cycle * 0.35f) * d_gixx_amp;
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
    float rho = 0.0f, ux = 0.0f, uy = 0.0f;
    for (int i = 0; i < Q; i++) {
        rho += f[idx + i];
        ux += f[idx + i] * d_cx[i];
        uy += f[idx + i] * d_cy[i];
    }
    if (rho < 0.1f) rho = 0.1f;
    if (rho > 10.0f) rho = 10.0f;
    ux /= rho;
    uy /= rho;
    float u_mag = sqrtf(ux*ux + uy*uy);
    if (u_mag > 0.25f) {
        ux = ux * 0.25f / u_mag;
        uy = uy * 0.25f / u_mag;
    }
    float kx = khra_gixx_wave_1024(x, y, cycle);
    float ky = kx * 0.5f;
    ux += kx;
    uy += ky;
    u_mag = sqrtf(ux*ux + uy*uy);
    if (u_mag > 0.25f) {
        ux = ux * 0.25f / u_mag;
        uy = uy * 0.25f / u_mag;
    }
    float u_sq = ux*ux + uy*uy;
    for (int i = 0; i < Q; i++) {
        float eu = d_cx[i]*ux + d_cy[i]*uy;
        float feq = d_w[i] * rho * (1.0f + 3.0f*eu + 4.5f*eu*eu - 1.5f*u_sq);
        f[idx + i] = f[idx + i] - omega * (f[idx + i] - feq);
        if (isnan(f[idx + i]) || isinf(f[idx + i])) f[idx + i] = d_w[i];
    }
}

__global__ void compute_rho(float* f, float* rho_out) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= NX || y >= NY) return;
    int idx = y * NX + x;
    int f_idx = idx * Q;
    float rho = 0.0f;
    for (int i = 0; i < Q; i++) rho += f[f_idx + i];
    if (rho < 0.1f) rho = 0.1f;
    rho_out[idx] = rho;
}

float calculate_asymmetry_magnifying(float* h_rho) {
    float sum_sq = 0.0f;
    for (int i = 0; i < NX * NY; i++) {
        float dev = h_rho[i] - 1.0f;
        sum_sq += dev * dev;
    }
    return (sum_sq / (NX * NY)) * 100.0f;
}

// Host-side omega and wave amplitudes — modifiable via command channel
static float h_omega = 1.97f;
static float h_khra_amp = 0.03f;
static float h_gixx_amp = 0.008f;

// Parse and apply a command received on the SUB socket
// Commands: {"cmd":"set_omega","value":1.85}
//           {"cmd":"set_khra_amp","value":0.05}
//           {"cmd":"set_gixx_amp","value":0.01}
//           {"cmd":"reset_equilibrium"}
static void handle_command(const char* msg, float* h_f, float* d_f_current) {
    // Minimal JSON parsing — no library dependency
    const char* cmd_start = strstr(msg, "\"cmd\":\"");
    if (!cmd_start) return;
    cmd_start += 7;

    if (strncmp(cmd_start, "set_omega", 9) == 0) {
        const char* val = strstr(msg, "\"value\":");
        if (val) {
            float v = strtof(val + 8, NULL);
            if (v >= 0.5f && v <= 1.99f) {
                h_omega = v;
                printf("[CMD] omega → %.3f\n", h_omega);
                fflush(stdout);
            }
        }
    } else if (strncmp(cmd_start, "set_khra_amp", 12) == 0) {
        const char* val = strstr(msg, "\"value\":");
        if (val) {
            float v = strtof(val + 8, NULL);
            if (v >= 0.0f && v <= 0.2f) {
                h_khra_amp = v;
                cudaMemcpyToSymbol(d_khra_amp, &h_khra_amp, sizeof(float));
                printf("[CMD] khra_amp → %.4f\n", h_khra_amp);
                fflush(stdout);
            }
        }
    } else if (strncmp(cmd_start, "set_gixx_amp", 12) == 0) {
        const char* val = strstr(msg, "\"value\":");
        if (val) {
            float v = strtof(val + 8, NULL);
            if (v >= 0.0f && v <= 0.1f) {
                h_gixx_amp = v;
                cudaMemcpyToSymbol(d_gixx_amp, &h_gixx_amp, sizeof(float));
                printf("[CMD] gixx_amp → %.4f\n", h_gixx_amp);
                fflush(stdout);
            }
        }
    } else if (strncmp(cmd_start, "reset_equilibrium", 17) == 0) {
        // Reset grid to uniform density
        const float h_w[Q] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f,
                              1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};
        size_t f_size = NX * NY * Q * sizeof(float);
        for (int y = 0; y < NY; y++)
            for (int x = 0; x < NX; x++)
                for (int i = 0; i < Q; i++)
                    h_f[(y*NX+x)*Q + i] = h_w[i];
        cudaMemcpy(d_f_current, h_f, f_size, cudaMemcpyHostToDevice);
        printf("[CMD] Grid reset to equilibrium\n");
        fflush(stdout);
    }
}

int main() {
    printf("Khra'gixx 1024 v2 — BIDIRECTIONAL + NVML\n"); fflush(stdout);
    printf("PUB telemetry on 5556 | SUB commands on 5557\n"); fflush(stdout);
    printf("Khra: %.3f | gixx: %.3f | omega: %.2f\n", h_khra_amp, h_gixx_amp, h_omega); fflush(stdout);
    printf("Asymmetry = mean((rho-1)^2) * 100\n\n"); fflush(stdout);

    // === NVML INIT ===
    nvmlReturn_t nvml_rc = nvmlInit();
    nvmlDevice_t nvml_device;
    int nvml_ok = 0;
    if (nvml_rc == NVML_SUCCESS) {
        nvml_rc = nvmlDeviceGetHandleByIndex(0, &nvml_device);
        if (nvml_rc == NVML_SUCCESS) {
            nvml_ok = 1;
            printf("NVML initialized — GPU hardware telemetry active\n"); fflush(stdout);
        } else {
            printf("NVML: got init but no device handle: %s\n", nvmlErrorString(nvml_rc)); fflush(stdout);
        }
    } else {
        printf("NVML init failed: %s — running without hardware telemetry\n", nvmlErrorString(nvml_rc)); fflush(stdout);
    }

    // === GPU MEMORY ===
    size_t f_size = NX * NY * Q * sizeof(float);
    size_t scalar_size = NX * NY * sizeof(float);
    
    printf("Allocating GPU memory: f_size=%zu MB, scalar_size=%zu MB\n", f_size/(1024*1024), scalar_size/(1024*1024)); fflush(stdout);
    
    float *d_f[2], *d_rho;
    CUDA_CHECK(cudaMalloc(&d_f[0], f_size));
    CUDA_CHECK(cudaMalloc(&d_f[1], f_size));
    CUDA_CHECK(cudaMalloc(&d_rho, scalar_size));
    printf("GPU allocation successful\n"); fflush(stdout);
    
    // Initialize equilibrium
    printf("Initializing grid...\n"); fflush(stdout);
    const float h_w[Q] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 
                          1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};
    float* h_f = (float*)malloc(f_size);
    if (!h_f) { fprintf(stderr, "malloc h_f failed\n"); return 1; }
    for (int y = 0; y < NY; y++)
        for (int x = 0; x < NX; x++)
            for (int i = 0; i < Q; i++)
                h_f[(y*NX+x)*Q + i] = h_w[i];
    CUDA_CHECK(cudaMemcpy(d_f[0], h_f, f_size, cudaMemcpyHostToDevice));
    printf("Grid initialized (rho=1.0 equilibrium)\n"); fflush(stdout);

    // Copy initial wave amplitudes to device
    cudaMemcpyToSymbol(d_khra_amp, &h_khra_amp, sizeof(float));
    cudaMemcpyToSymbol(d_gixx_amp, &h_gixx_amp, sizeof(float));
    
    // === ZMQ: PUB telemetry on 5556 ===
    printf("Initializing ZMQ...\n"); fflush(stdout);
    void* zmq_ctx = zmq_ctx_new();
    if (!zmq_ctx) { fprintf(stderr, "zmq_ctx_new failed\n"); return 1; }

    void* publisher = zmq_socket(zmq_ctx, ZMQ_PUB);
    if (!publisher) { fprintf(stderr, "zmq_socket PUB failed\n"); return 1; }
    int sndhwm = 1, linger = 0;
    zmq_setsockopt(publisher, ZMQ_SNDHWM, &sndhwm, sizeof(sndhwm));
    zmq_setsockopt(publisher, ZMQ_LINGER, &linger, sizeof(linger));
    int rc = zmq_bind(publisher, "tcp://127.0.0.1:5556");
    if (rc != 0) {
        fprintf(stderr, "WARNING: zmq_bind PUB failed: %s (port 5556 may be in use)\n", zmq_strerror(zmq_errno()));
        fflush(stderr);
    } else {
        printf("ZMQ PUB bound to port 5556\n"); fflush(stdout);
    }

    // === ZMQ: SUB commands on 5557 ===
    void* subscriber = zmq_socket(zmq_ctx, ZMQ_SUB);
    if (!subscriber) { fprintf(stderr, "zmq_socket SUB failed\n"); return 1; }
    zmq_setsockopt(subscriber, ZMQ_SUBSCRIBE, "", 0);
    int rcvhwm = 10;
    zmq_setsockopt(subscriber, ZMQ_RCVHWM, &rcvhwm, sizeof(rcvhwm));
    zmq_setsockopt(subscriber, ZMQ_LINGER, &linger, sizeof(linger));
    rc = zmq_bind(subscriber, "tcp://127.0.0.1:5557");
    if (rc != 0) {
        fprintf(stderr, "WARNING: zmq_bind SUB failed: %s (port 5557 may be in use)\n", zmq_strerror(zmq_errno()));
        fflush(stderr);
    } else {
        printf("ZMQ SUB bound to port 5557 (command channel)\n"); fflush(stdout);
    }
    
    float *h_rho = (float*)malloc(scalar_size);
    if (!h_rho) { fprintf(stderr, "malloc h_rho failed\n"); return 1; }
    dim3 block(16, 16);
    dim3 grid((NX + 15) / 16, (NY + 15) / 16);
    
    int cycle = 0, current = 0;
    printf("[Khra'gixx v2 Daemon] Starting main loop...\n"); fflush(stdout);
    
    while (1) {
        // === Check for commands (non-blocking) ===
        char cmd_buf[256];
        int cmd_len = zmq_recv(subscriber, cmd_buf, sizeof(cmd_buf) - 1, ZMQ_DONTWAIT);
        if (cmd_len > 0) {
            cmd_buf[cmd_len] = '\0';
            handle_command(cmd_buf, h_f, d_f[current]);
        }

        // === LBM step ===
        streaming_kernel<<<grid, block>>>(d_f[current], d_f[1-current], NX, NY);
        CUDA_CHECK(cudaDeviceSynchronize());
        collide_kernel_khragixx<<<grid, block>>>(d_f[1-current], h_omega, cycle);
        CUDA_CHECK(cudaDeviceSynchronize());
        current = 1 - current;
        
        // === Telemetry every 10 cycles ===
        if (cycle % 10 == 0) {
            compute_rho<<<grid, block>>>(d_f[current], d_rho);
            CUDA_CHECK(cudaDeviceSynchronize());
            CUDA_CHECK(cudaMemcpy(h_rho, d_rho, scalar_size, cudaMemcpyDeviceToHost));
            
            float sum_rho = 0.0f, sum_rho_sq = 0.0f;
            for (int i = 0; i < NX * NY; i++) {
                sum_rho += h_rho[i];
                sum_rho_sq += h_rho[i] * h_rho[i];
            }
            float mean_rho = sum_rho / (NX * NY);
            float variance = sum_rho_sq / (NX * NY) - mean_rho * mean_rho;
            float coherence = 1.0f / (1.0f + sqrtf(variance > 0.0f ? variance : 0.0f));
            float asymmetry = calculate_asymmetry_magnifying(h_rho);

            // === NVML reads ===
            unsigned int gpu_temp = 0;
            unsigned int gpu_power_mw = 0;
            float gpu_mem_pct = 0.0f;
            if (nvml_ok) {
                nvmlDeviceGetTemperature(nvml_device, NVML_TEMPERATURE_GPU, &gpu_temp);
                nvmlDeviceGetPowerUsage(nvml_device, &gpu_power_mw);
                nvmlMemory_t mem_info;
                if (nvmlDeviceGetMemoryInfo(nvml_device, &mem_info) == NVML_SUCCESS) {
                    gpu_mem_pct = (float)mem_info.used / (float)mem_info.total * 100.0f;
                }
            }

            // === Publish expanded frame ===
            char msg[512];
            snprintf(msg, sizeof(msg),
                "{\"cycle\":%d,\"coherence\":%.4f,\"asymmetry\":%.4f,"
                "\"omega\":%.3f,\"khra_amp\":%.4f,\"gixx_amp\":%.4f,\"grid\":1024,"
                "\"gpu_temp_c\":%u,\"gpu_power_w\":%.1f,\"gpu_mem_pct\":%.1f}",
                cycle, coherence, asymmetry,
                h_omega, h_khra_amp, h_gixx_amp,
                gpu_temp, gpu_power_mw / 1000.0f, gpu_mem_pct);
            zmq_send(publisher, msg, strlen(msg), 0);
            
            if (cycle % 100 == 0) {
                printf("Cycle %d: Coh=%.3f Asym=%.4f omega=%.3f T=%uC P=%.0fW Mem=%.0f%%\n",
                       cycle, coherence, asymmetry, h_omega, gpu_temp, gpu_power_mw/1000.0f, gpu_mem_pct);
                fflush(stdout);
            }
        }
        
        cycle++;
        usleep(10000);
    }
    
    // Cleanup (unreachable in practice)
    free(h_f);
    free(h_rho);
    cudaFree(d_f[0]); cudaFree(d_f[1]); cudaFree(d_rho);
    zmq_close(publisher);
    zmq_close(subscriber);
    zmq_ctx_destroy(zmq_ctx);
    if (nvml_ok) nvmlShutdown();
    return 0;
}
