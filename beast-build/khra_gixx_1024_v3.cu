// khra_gixx_1024_v3.cu
// v3: Added save_state/load_state commands + periodic autosave
// Bidirectional daemon: PUB telemetry + SUB commands
// NVML hardware metadata in every frame
// Dynamic omega, khra_amp, gixx_amp via command channel
// Checkpoint format: 64-byte header (KHRG magic + metadata + CRC32) + raw f_data

#include <cuda_runtime.h>
#include <nvml.h>
#include <zmq.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#include <time.h>
#include <stdint.h>

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

// === CRC32 (zlib-compatible, for checkpoint integrity) ===
static uint32_t crc32_table[256];
static int crc32_table_ready = 0;

static void crc32_init(void) {
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int j = 0; j < 8; j++)
            c = (c >> 1) ^ ((c & 1) ? 0xEDB88320u : 0);
        crc32_table[i] = c;
    }
    crc32_table_ready = 1;
}

static uint32_t crc32_compute(const void* data, size_t len) {
    if (!crc32_table_ready) crc32_init();
    const unsigned char* p = (const unsigned char*)data;
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < len; i++)
        crc = crc32_table[(crc ^ p[i]) & 0xFF] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFF;
}

// === CHECKPOINT SAVE ===
// Format: 64-byte header + NX*NY*Q float32
// Header: "KHRG" | version(u32) | cycle(u32) | NX(u32) | NY(u32) | Q(u32) |
//         omega(f32) | khra_amp(f32) | gixx_amp(f32) | crc32(u32) | reserved

static int save_checkpoint(float* h_f, float* d_f_active, int cycle, const char* dir) {
    size_t f_size = (size_t)NX * NY * Q * sizeof(float);

    cudaError_t err = cudaMemcpy(h_f, d_f_active, f_size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess) {
        fprintf(stderr, "[SAVE] cudaMemcpy failed: %s\n", cudaGetErrorString(err));
        fflush(stderr);
        return -1;
    }

    char path[512], tmp_path[520];
    time_t now = time(NULL);
    struct tm* t = localtime(&now);
    snprintf(path, sizeof(path), "%s/ckpt_%04d%02d%02d_%02d%02d%02d_c%d.bin",
             dir, t->tm_year+1900, t->tm_mon+1, t->tm_mday,
             t->tm_hour, t->tm_min, t->tm_sec, cycle);
    snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", path);

    FILE* fp = fopen(tmp_path, "wb");
    if (!fp) {
        fprintf(stderr, "[SAVE] fopen failed: %s\n", tmp_path);
        fflush(stderr);
        return -2;
    }

    // Build 64-byte header
    unsigned char header[64];
    memset(header, 0, 64);
    memcpy(header, "KHRG", 4);
    uint32_t v;
    v = 1;              memcpy(header+4,  &v, 4);  // version
    v = (uint32_t)cycle; memcpy(header+8,  &v, 4);  // cycle
    v = NX;             memcpy(header+12, &v, 4);
    v = NY;             memcpy(header+16, &v, 4);
    v = Q;              memcpy(header+20, &v, 4);
    memcpy(header+24, &h_omega, 4);
    memcpy(header+28, &h_khra_amp, 4);
    memcpy(header+32, &h_gixx_amp, 4);
    uint32_t crc = crc32_compute(h_f, f_size);
    memcpy(header+36, &crc, 4);

    size_t w1 = fwrite(header, 1, 64, fp);
    size_t w2 = fwrite(h_f, 1, f_size, fp);
    fclose(fp);

    if (w1 != 64 || w2 != f_size) {
        fprintf(stderr, "[SAVE] write incomplete: header=%zu data=%zu\n", w1, w2);
        fflush(stderr);
        unlink(tmp_path);
        return -3;
    }

    if (rename(tmp_path, path) != 0) {
        fprintf(stderr, "[SAVE] rename failed\n");
        fflush(stderr);
        return -4;
    }

    printf("[SAVE] %s (cycle %d, CRC32=0x%08X, %.1f MB)\n",
           path, cycle, crc, (64.0 + f_size) / (1024.0*1024.0));
    fflush(stdout);
    return 0;
}

// === CHECKPOINT LOAD ===
// Returns loaded cycle number, or -1 on error
// Supports: v3 format (64-byte header + f_data) and raw format (exactly f_size bytes, no header)
static int load_checkpoint(const char* path, float* h_f, float* d_f_target) {
    size_t f_size = (size_t)NX * NY * Q * sizeof(float);

    FILE* fp = fopen(path, "rb");
    if (!fp) {
        fprintf(stderr, "[LOAD] Cannot open: %s\n", path);
        fflush(stderr);
        return -1;
    }

    fseek(fp, 0, SEEK_END);
    long file_size = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    int loaded_cycle = 0;

    if (file_size == (long)(64 + f_size)) {
        // v3 format with header
        unsigned char header[64];
        if (fread(header, 1, 64, fp) != 64) { fclose(fp); return -1; }
        if (memcmp(header, "KHRG", 4) != 0) {
            fprintf(stderr, "[LOAD] Bad magic in %s\n", path);
            fclose(fp);
            return -1;
        }
        uint32_t v;
        memcpy(&v, header+8, 4);  loaded_cycle = (int)v;
        memcpy(&v, header+12, 4); if (v != NX) { fprintf(stderr, "[LOAD] NX mismatch\n"); fclose(fp); return -1; }
        memcpy(&v, header+16, 4); if (v != NY) { fprintf(stderr, "[LOAD] NY mismatch\n"); fclose(fp); return -1; }
        memcpy(&v, header+20, 4); if (v != Q)  { fprintf(stderr, "[LOAD] Q mismatch\n");  fclose(fp); return -1; }
        // Restore parameters
        memcpy(&h_omega, header+24, 4);
        memcpy(&h_khra_amp, header+28, 4);
        memcpy(&h_gixx_amp, header+32, 4);
        cudaMemcpyToSymbol(d_khra_amp, &h_khra_amp, sizeof(float));
        cudaMemcpyToSymbol(d_gixx_amp, &h_gixx_amp, sizeof(float));

        if (fread(h_f, 1, f_size, fp) != f_size) { fclose(fp); return -1; }

        // Verify CRC
        uint32_t stored_crc;
        memcpy(&stored_crc, header+36, 4);
        uint32_t actual_crc = crc32_compute(h_f, f_size);
        if (stored_crc != actual_crc) {
            fprintf(stderr, "[LOAD] CRC mismatch! stored=0x%08X actual=0x%08X\n", stored_crc, actual_crc);
            fflush(stderr);
            fclose(fp);
            return -1;
        }
        printf("[LOAD] v3 checkpoint: cycle=%d omega=%.3f khra=%.4f gixx=%.4f CRC OK\n",
               loaded_cycle, h_omega, h_khra_amp, h_gixx_amp);
    } else if (file_size == (long)f_size) {
        // Raw format (emergency extract or legacy) — no header
        if (fread(h_f, 1, f_size, fp) != f_size) { fclose(fp); return -1; }
        printf("[LOAD] Raw checkpoint (no header): %s (%ld bytes)\n", path, file_size);
    } else {
        fprintf(stderr, "[LOAD] Unknown format: %s (%ld bytes, expected %zu or %zu)\n",
                path, file_size, 64 + f_size, f_size);
        fclose(fp);
        return -1;
    }

    fclose(fp);

    cudaError_t err = cudaMemcpy(d_f_target, h_f, f_size, cudaMemcpyHostToDevice);
    if (err != cudaSuccess) {
        fprintf(stderr, "[LOAD] cudaMemcpy failed: %s\n", cudaGetErrorString(err));
        fflush(stderr);
        return -1;
    }

    printf("[LOAD] State loaded from %s\n", path);
    fflush(stdout);
    return loaded_cycle;
}

// === COMMAND HANDLER ===
// Commands: {"cmd":"set_omega","value":1.85}
//           {"cmd":"set_khra_amp","value":0.05}
//           {"cmd":"set_gixx_amp","value":0.01}
//           {"cmd":"reset_equilibrium"}
//           {"cmd":"save_state"}
//           {"cmd":"save_state","path":"/custom/dir"}
//           {"cmd":"load_state","path":"/path/to/file.bin"}
//           {"cmd":"set_autosave","interval":100000}
// Returns: 1 if save requested, 2 if load requested (with path in out_path), 0 otherwise
static int handle_command(const char* msg, float* h_f, float* d_f_current,
                          char* out_path, int out_path_size) {
    // Minimal JSON parsing — no library dependency
    // Try compact format first: "cmd":"value", then spaced format: "cmd": "value"
    const char* cmd_start = strstr(msg, "\"cmd\":\"");
    if (!cmd_start) {
        cmd_start = strstr(msg, "\"cmd\": \"");
        if (!cmd_start) return 0;
        cmd_start += 8;  // skip past "cmd": "
    } else {
        cmd_start += 7;  // skip past "cmd":"
    }

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
    } else if (strncmp(cmd_start, "save_state", 10) == 0) {
        // Extract optional path
        const char* p = strstr(msg, "\"path\":\"");
        if (p) {
            p += 8;
            const char* end = strchr(p, '"');
            if (end && (end - p) < out_path_size) {
                memcpy(out_path, p, end - p);
                out_path[end - p] = '\0';
            } else {
                strncpy(out_path, ".", out_path_size - 1);
            }
        } else {
            strncpy(out_path, ".", out_path_size - 1);
        }
        return 1;  // signal: save requested
    } else if (strncmp(cmd_start, "load_state", 10) == 0) {
        const char* p = strstr(msg, "\"path\":\"");
        if (p) {
            p += 8;
            const char* end = strchr(p, '"');
            if (end && (end - p) < out_path_size) {
                memcpy(out_path, p, end - p);
                out_path[end - p] = '\0';
                return 2;  // signal: load requested
            }
        }
        fprintf(stderr, "[CMD] load_state requires \"path\" field\n");
        fflush(stderr);
    } else if (strncmp(cmd_start, "set_autosave", 12) == 0) {
        const char* val = strstr(msg, "\"interval\":");
        if (val) {
            int v = atoi(val + 11);
            if (v >= 0 && v <= 10000000) {
                // Store in out_path as string for main loop to pick up
                snprintf(out_path, out_path_size, "%d", v);
                return 3;  // signal: autosave interval change
            }
        }
    }
    return 0;
}

int main() {
    printf("Khra'gixx 1024 v3 — BIDIRECTIONAL + NVML + CHECKPOINT\n"); fflush(stdout);
    printf("PUB telemetry on 5556 | SUB commands on 5557\n"); fflush(stdout);
    printf("Khra: %.3f | gixx: %.3f | omega: %.2f\n", h_khra_amp, h_gixx_amp, h_omega); fflush(stdout);
    printf("Asymmetry = mean((rho-1)^2) * 100\n"); fflush(stdout);
    printf("Commands: save_state, load_state, set_autosave, set_omega, set_khra_amp, set_gixx_amp, reset_equilibrium\n\n"); fflush(stdout);

    // Init CRC32 table
    crc32_init();

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
    int autosave_interval = 100000;  // default: save every 100k cycles (~17 min at 10ms/step)
    int last_autosave = 0;
    printf("[v3] Autosave every %d cycles (send {\"cmd\":\"set_autosave\",\"interval\":N} to change, 0=off)\n", autosave_interval);
    fflush(stdout);
    printf("[Khra'gixx v3 Daemon] Starting main loop...\n"); fflush(stdout);
    
    while (1) {
        // === Check for commands (non-blocking) ===
        char cmd_buf[256];
        char cmd_path[512];
        int cmd_len = zmq_recv(subscriber, cmd_buf, sizeof(cmd_buf) - 1, ZMQ_DONTWAIT);
        if (cmd_len > 0) {
            cmd_buf[cmd_len] = '\0';
            cmd_path[0] = '\0';
            int cmd_result = handle_command(cmd_buf, h_f, d_f[current], cmd_path, sizeof(cmd_path));
            if (cmd_result == 1) {
                // save_state requested
                save_checkpoint(h_f, d_f[current], cycle, cmd_path);
            } else if (cmd_result == 2) {
                // load_state requested
                int loaded_cycle = load_checkpoint(cmd_path, h_f, d_f[current]);
                if (loaded_cycle >= 0) {
                    cycle = loaded_cycle;
                    printf("[CMD] Resumed at cycle %d\n", cycle);
                    fflush(stdout);
                }
            } else if (cmd_result == 3) {
                // set_autosave
                autosave_interval = atoi(cmd_path);
                last_autosave = cycle;
                printf("[CMD] Autosave interval → %d cycles%s\n",
                       autosave_interval, autosave_interval == 0 ? " (disabled)" : "");
                fflush(stdout);
            }
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

        // === Autosave check ===
        if (autosave_interval > 0 && cycle > 0 && (cycle - last_autosave) >= autosave_interval) {
            save_checkpoint(h_f, d_f[current], cycle, ".");
            last_autosave = cycle;
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
