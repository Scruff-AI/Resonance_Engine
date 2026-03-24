/* ============================================================================
 * CRAW LBM v2 — Beast Efficiency Lessons Applied
 * Target: GTX 1050 (sm_61, 4GB VRAM, 640 CUDA cores)
 *
 * Upgrades from interaction_coupled.cu:
 *   P0: Safety clamps — density [0.1,10.0], velocity Mach 0.25, NaN guard
 *   P2: Khra'gixx structured wave forcing (replaces random jitter)
 *   P3: omega=1.97 default (Beast proven production value, runtime-adjustable)
 *   P4: CRC32 checkpoint save/load (KHRG header format)
 *   P5: ZMQ PUB telemetry + SUB command channel
 *
 * Retained from interaction_coupled.cu:
 *   - SoA memory layout (better GPU coalescing than Beast's AoS)
 *   - Fused stream+collide kernel (double-buffered, correct LBM physics)
 *   - cuFFT spectral analysis (entropy, slope) — Beast doesn't have this
 *   - NVML thermal monitoring
 *
 * Compile (no ZMQ):  nvcc -O3 -arch=sm_61 craw_lbm_v2.cu -o craw_lbm_v2 -lnvidia-ml -lcufft
 * Compile (with ZMQ): nvcc -O3 -arch=sm_61 -DHAS_ZMQ craw_lbm_v2.cu -o craw_lbm_v2 -lzmq -lnvidia-ml -lcufft
 * ============================================================================ */

#include <cuda_runtime.h>
#include <cufft.h>
#include <nvml.h>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <cstring>
#include <unistd.h>
#include <time.h>
#include <stdint.h>
#ifdef HAS_ZMQ
#include <zmq.h>
#endif

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define NX    512
#define NY    512
#define NN    (NX * NY)
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

#define CUDA_CHECK(call) do { \
    cudaError_t err = call; \
    if (err != cudaSuccess) { \
        fprintf(stderr, "CUDA error at %s:%d — %s\n", \
                __FILE__, __LINE__, cudaGetErrorString(err)); \
        fflush(stderr); exit(1); \
    } \
} while(0)

/* ── D2Q9 LATTICE CONSTANTS ─────────────────────────────────────────────── */

__constant__ int d_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
__constant__ int d_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
__constant__ float d_w[Q] = { 4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9,
                               1.f/36, 1.f/36, 1.f/36, 1.f/36 };

/* ── DEVICE-SIDE WAVE AMPLITUDES (runtime-adjustable via ZMQ) ────────── */

__device__ float d_khra_amp = 0.030f;
__device__ float d_gixx_amp = 0.008f;

/* ── KHRA'GIXX WAVE FORCING (adapted for 512x512) ───────────────────── */
// Khra: 64-cell wavelength (large scale), slow temporal drift
// Gixx: 8-cell wavelength (fine scale), fast temporal drift
// Asymmetry factor oscillates gixx amplitude ±50%

__device__ float khra_gixx_wave(int x, int y, int step) {
    float khra = sinf(2.0f * M_PI * x / 64.0f + step * 0.05f) *
                 cosf(2.0f * M_PI * y / 64.0f + step * 0.03f) * d_khra_amp;
    float gixx = sinf(2.0f * M_PI * x / 8.0f + step * 0.4f) *
                 cosf(2.0f * M_PI * y / 8.0f + step * 0.35f) * d_gixx_amp;
    float asymmetry = 1.0f + sinf(step * 0.05f) * 0.5f;
    return khra + gixx * asymmetry;
}

/* ── FUSED STREAM+COLLIDE KERNEL WITH SAFETY CLAMPS ────────────────── */
// SoA layout: f[direction * NN + cell_index]
// Reads from f_src (neighbors), writes to f_dst
// Safety: density [0.1,10.0], Mach 0.25 (twice), NaN guard

__global__ void lbm_step_v2(const float* f_src, float* f_dst,
        float* rho_out, float* ux_out, float* uy_out,
        float omega, int step) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= NN) return;
    const int x = idx % NX, y = idx / NX;

    // Stream: pull from neighbor cells
    float fl[Q];
    for (int i = 0; i < Q; i++) {
        int sx = (x - d_ex[i] + NX) % NX;
        int sy = (y - d_ey[i] + NY) % NY;
        fl[i] = f_src[i * NN + sy * NX + sx];
    }

    // Compute moments
    float rho = 0.f, ux = 0.f, uy = 0.f;
    for (int i = 0; i < Q; i++) {
        rho += fl[i];
        ux += (float)d_ex[i] * fl[i];
        uy += (float)d_ey[i] * fl[i];
    }

    // P0: Density clamp [0.1, 10.0]
    if (rho < 0.1f) rho = 0.1f;
    if (rho > 10.0f) rho = 10.0f;

    ux /= rho;
    uy /= rho;

    // P0: Velocity Mach clamp (pre-injection)
    float u_mag = sqrtf(ux * ux + uy * uy);
    if (u_mag > 0.25f) {
        float s = 0.25f / u_mag;
        ux *= s; uy *= s;
    }

    // P2: Khra'gixx wave injection
    float kx = khra_gixx_wave(x, y, step);
    ux += kx;
    uy += kx * 0.5f;

    // P0: Velocity Mach clamp (post-injection)
    u_mag = sqrtf(ux * ux + uy * uy);
    if (u_mag > 0.25f) {
        float s = 0.25f / u_mag;
        ux *= s; uy *= s;
    }

    rho_out[idx] = rho;
    ux_out[idx] = ux;
    uy_out[idx] = uy;

    // BGK collision
    const float u2 = ux * ux + uy * uy;
    for (int i = 0; i < Q; i++) {
        float eu = (float)d_ex[i] * ux + (float)d_ey[i] * uy;
        float feq = d_w[i] * rho * (1.f + 3.f * eu + 4.5f * eu * eu - 1.5f * u2);
        float f_new = fl[i] - omega * (fl[i] - feq);

        // P0: NaN guard — reset to equilibrium if corrupted
        if (isnan(f_new) || isinf(f_new)) f_new = d_w[i] * rho;

        f_dst[i * NN + idx] = f_new;
    }
}

/* ── SPECTRAL ANALYSIS (retained from interaction_coupled.cu) ────────── */

__global__ void compute_spectrum(const cufftComplex* fft_ux,
        const cufftComplex* fft_uy, double* spectrum, int nk) {
    int nx2 = NX / 2 + 1;
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= NY * nx2) return;

    int kx_idx = idx % nx2;
    int ky_idx = idx / nx2;
    int kx = kx_idx;
    int ky = (ky_idx <= NY / 2) ? ky_idx : ky_idx - NY;
    int k = (int)roundf(sqrtf((float)(kx * kx + ky * ky)));
    if (k >= nk || k == 0) return;

    float ar = fft_ux[idx].x, ai = fft_ux[idx].y;
    float br = fft_uy[idx].x, bi = fft_uy[idx].y;
    double power = (double)(ar * ar + ai * ai + br * br + bi * bi);
    if (kx_idx > 0 && kx_idx < NX / 2) power *= 2.0;
    atomicAdd(&spectrum[k], power);
}

static double calc_entropy(const double* spec, int nk) {
    double total = 0;
    for (int k = 1; k < nk; k++) total += spec[k];
    if (total <= 0) return 0;
    double H = 0;
    for (int k = 1; k < nk; k++) {
        double p = spec[k] / total;
        if (p > 0) H -= p * log2(p);
    }
    return H;
}

static double calc_slope(const double* spec, int nk) {
    double sx = 0, sy = 0, sxx = 0, sxy = 0;
    int n = 0;
    for (int k = 2; k <= 100 && k < nk; k++) {
        if (spec[k] > 0) {
            double lk = log((double)k), le = log(spec[k]);
            sx += lk; sy += le; sxx += lk * lk; sxy += lk * le; n++;
        }
    }
    return (n > 2) ? ((double)n * sxy - sx * sy) / ((double)n * sxx - sx * sx) : 0;
}

/* ── HOST-SIDE PARAMETERS ────────────────────────────────────────────── */

static float h_omega    = 1.97f;
static float h_khra_amp = 0.030f;
static float h_gixx_amp = 0.008f;

/* ── CRC32 (zlib-compatible, for checkpoint integrity) ───────────────── */

static uint32_t crc32_table[256];
static int crc32_ready = 0;

static void crc32_init(void) {
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int j = 0; j < 8; j++)
            c = (c >> 1) ^ ((c & 1) ? 0xEDB88320u : 0);
        crc32_table[i] = c;
    }
    crc32_ready = 1;
}

static uint32_t crc32_compute(const void* data, size_t len) {
    if (!crc32_ready) crc32_init();
    const unsigned char* p = (const unsigned char*)data;
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < len; i++)
        crc = crc32_table[(crc ^ p[i]) & 0xFF] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFF;
}

/* ── CHECKPOINT SAVE ─────────────────────────────────────────────────── */
// Format: 64-byte KHRG header + Q*NN float32 (SoA layout)
// Header: "KHRG" | version(u32) | step(u32) | NX(u32) | NY(u32) | Q(u32) |
//         omega(f32) | khra_amp(f32) | gixx_amp(f32) | crc32(u32) | reserved

static int save_checkpoint(float* h_f, float* d_f, int step, const char* dir) {
    size_t f_size = (size_t)Q * NN * sizeof(float);
    cudaError_t err = cudaMemcpy(h_f, d_f, f_size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess) {
        fprintf(stderr, "[SAVE] cudaMemcpy failed: %s\n", cudaGetErrorString(err));
        fflush(stderr); return -1;
    }

    char path[512], tmp[520];
    time_t now = time(NULL);
    struct tm* t = localtime(&now);
    snprintf(path, sizeof(path), "%s/ckpt_%04d%02d%02d_%02d%02d%02d_s%d.bin",
             dir, t->tm_year + 1900, t->tm_mon + 1, t->tm_mday,
             t->tm_hour, t->tm_min, t->tm_sec, step);
    snprintf(tmp, sizeof(tmp), "%s.tmp", path);

    FILE* fp = fopen(tmp, "wb");
    if (!fp) {
        fprintf(stderr, "[SAVE] fopen failed: %s\n", tmp);
        fflush(stderr); return -1;
    }

    unsigned char header[64];
    memset(header, 0, 64);
    memcpy(header, "KHRG", 4);
    uint32_t v;
    v = 2;               memcpy(header + 4,  &v, 4);  // version 2 = SoA layout
    v = (uint32_t)step;  memcpy(header + 8,  &v, 4);
    v = NX;              memcpy(header + 12, &v, 4);
    v = NY;              memcpy(header + 16, &v, 4);
    v = Q;               memcpy(header + 20, &v, 4);
    memcpy(header + 24, &h_omega, 4);
    memcpy(header + 28, &h_khra_amp, 4);
    memcpy(header + 32, &h_gixx_amp, 4);
    uint32_t crc = crc32_compute(h_f, f_size);
    memcpy(header + 36, &crc, 4);

    size_t w1 = fwrite(header, 1, 64, fp);
    size_t w2 = fwrite(h_f, 1, f_size, fp);
    fclose(fp);

    if (w1 != 64 || w2 != f_size) {
        fprintf(stderr, "[SAVE] incomplete write\n");
        fflush(stderr); unlink(tmp); return -1;
    }

    rename(tmp, path);
    printf("[SAVE] %s (step %d, CRC32=0x%08X, %.1f MB)\n",
           path, step, crc, (64.0 + f_size) / (1024.0 * 1024.0));
    fflush(stdout);
    return 0;
}

/* ── CHECKPOINT LOAD ─────────────────────────────────────────────────── */
// Supports: KHRG v2 (64-byte header + SoA data)
//           Raw (exactly f_size bytes, no header)
//           Legacy dual-buffer (20-byte header + 2× SoA data)

static int load_checkpoint(const char* path, float* h_f, float* d_f) {
    size_t f_size = (size_t)Q * NN * sizeof(float);
    FILE* fp = fopen(path, "rb");
    if (!fp) {
        fprintf(stderr, "[LOAD] Cannot open: %s\n", path);
        fflush(stderr); return -1;
    }

    fseek(fp, 0, SEEK_END);
    long file_size = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    int loaded_step = 0;

    if (file_size == (long)(64 + f_size)) {
        /* KHRG format */
        unsigned char header[64];
        if (fread(header, 1, 64, fp) != 64) { fclose(fp); return -1; }
        if (memcmp(header, "KHRG", 4) != 0) {
            fprintf(stderr, "[LOAD] Bad magic\n"); fclose(fp); return -1;
        }
        uint32_t v;
        memcpy(&v, header + 8,  4); loaded_step = (int)v;
        memcpy(&v, header + 12, 4);
        if (v != NX) { fprintf(stderr, "[LOAD] NX mismatch (%u vs %d)\n", v, NX); fclose(fp); return -1; }
        memcpy(&v, header + 16, 4);
        if (v != NY) { fprintf(stderr, "[LOAD] NY mismatch (%u vs %d)\n", v, NY); fclose(fp); return -1; }
        memcpy(&v, header + 20, 4);
        if (v != Q)  { fprintf(stderr, "[LOAD] Q mismatch (%u vs %d)\n", v, Q);   fclose(fp); return -1; }

        memcpy(&h_omega,    header + 24, 4);
        memcpy(&h_khra_amp, header + 28, 4);
        memcpy(&h_gixx_amp, header + 32, 4);
        cudaMemcpyToSymbol(d_khra_amp, &h_khra_amp, sizeof(float));
        cudaMemcpyToSymbol(d_gixx_amp, &h_gixx_amp, sizeof(float));

        if (fread(h_f, 1, f_size, fp) != f_size) { fclose(fp); return -1; }

        uint32_t stored_crc, actual_crc;
        memcpy(&stored_crc, header + 36, 4);
        actual_crc = crc32_compute(h_f, f_size);
        if (stored_crc != actual_crc) {
            fprintf(stderr, "[LOAD] CRC mismatch! stored=0x%08X actual=0x%08X\n",
                    stored_crc, actual_crc);
            fflush(stderr); fclose(fp); return -1;
        }
        printf("[LOAD] KHRG v%u: step=%d omega=%.3f khra=%.4f gixx=%.4f CRC OK\n",
               *(uint32_t*)(header + 4), loaded_step, h_omega, h_khra_amp, h_gixx_amp);

    } else if (file_size == (long)(20 + 2 * f_size)) {
        /* Legacy dual-buffer format (interaction_coupled.cu saves) */
        int nx, ny, q, old_step, old_cur;
        fread(&nx, sizeof(int), 1, fp);
        fread(&ny, sizeof(int), 1, fp);
        fread(&q,  sizeof(int), 1, fp);
        fread(&old_step, sizeof(int), 1, fp);
        fread(&old_cur,  sizeof(int), 1, fp);
        if (nx != NX || ny != NY || q != Q) {
            fprintf(stderr, "[LOAD] Grid mismatch in legacy format (%dx%dx%d)\n", nx, ny, q);
            fclose(fp); return -1;
        }
        if (fread(h_f, sizeof(float), Q * NN, fp) != (size_t)(Q * NN)) { fclose(fp); return -1; }
        loaded_step = old_step;
        printf("[LOAD] Legacy dual-buffer: step=%d nx=%d ny=%d\n", loaded_step, nx, ny);

    } else if (file_size == (long)f_size) {
        /* Raw format (no header) */
        if (fread(h_f, 1, f_size, fp) != f_size) { fclose(fp); return -1; }
        printf("[LOAD] Raw checkpoint: %s (%ld bytes)\n", path, file_size);

    } else {
        fprintf(stderr, "[LOAD] Unknown format: %ld bytes (expected %zu, %zu, or %zu)\n",
                file_size, 64 + f_size, f_size, 20 + 2 * f_size);
        fclose(fp); return -1;
    }

    fclose(fp);
    cudaMemcpy(d_f, h_f, f_size, cudaMemcpyHostToDevice);
    printf("[LOAD] State loaded from %s\n", path);
    fflush(stdout);
    return loaded_step;
}

/* ── ZMQ COMMAND HANDLER ─────────────────────────────────────────────── */
// Commands: set_omega, set_khra_amp, set_gixx_amp, save_state, load_state,
//           set_autosave, reset_equilibrium
// Returns: 1=save, 2=load, 3=autosave_change, 0=handled_or_ignored

static int handle_command(const char* msg, float* h_f, float* d_f_current,
                          char* out_path, int out_path_size) {
    const char* cmd = strstr(msg, "\"cmd\":\"");
    if (!cmd) {
        cmd = strstr(msg, "\"cmd\": \"");
        if (!cmd) return 0;
        cmd += 8;
    } else {
        cmd += 7;
    }

    if (strncmp(cmd, "set_omega", 9) == 0) {
        const char* val = strstr(msg, "\"value\":");
        if (val) {
            float v = strtof(val + 8, NULL);
            if (v >= 0.5f && v <= 1.99f) {
                h_omega = v;
                printf("[CMD] omega → %.3f\n", h_omega); fflush(stdout);
            }
        }
    } else if (strncmp(cmd, "set_khra_amp", 12) == 0) {
        const char* val = strstr(msg, "\"value\":");
        if (val) {
            float v = strtof(val + 8, NULL);
            if (v >= 0.0f && v <= 0.2f) {
                h_khra_amp = v;
                cudaMemcpyToSymbol(d_khra_amp, &h_khra_amp, sizeof(float));
                printf("[CMD] khra_amp → %.4f\n", h_khra_amp); fflush(stdout);
            }
        }
    } else if (strncmp(cmd, "set_gixx_amp", 12) == 0) {
        const char* val = strstr(msg, "\"value\":");
        if (val) {
            float v = strtof(val + 8, NULL);
            if (v >= 0.0f && v <= 0.1f) {
                h_gixx_amp = v;
                cudaMemcpyToSymbol(d_gixx_amp, &h_gixx_amp, sizeof(float));
                printf("[CMD] gixx_amp → %.4f\n", h_gixx_amp); fflush(stdout);
            }
        }
    } else if (strncmp(cmd, "reset_equilibrium", 17) == 0) {
        size_t f_sz = (size_t)Q * NN * sizeof(float);
        const float hw[Q] = {4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9,
                             1.f/36, 1.f/36, 1.f/36, 1.f/36};
        for (int idx = 0; idx < NN; idx++)
            for (int i = 0; i < Q; i++)
                h_f[i * NN + idx] = hw[i];
        cudaMemcpy(d_f_current, h_f, f_sz, cudaMemcpyHostToDevice);
        printf("[CMD] Grid reset to equilibrium\n"); fflush(stdout);
    } else if (strncmp(cmd, "save_state", 10) == 0) {
        const char* p = strstr(msg, "\"path\":\"");
        if (p) {
            p += 8;
            const char* end = strchr(p, '"');
            if (end && (end - p) < out_path_size) {
                memcpy(out_path, p, end - p);
                out_path[end - p] = '\0';
            } else { strncpy(out_path, ".", out_path_size - 1); }
        } else { strncpy(out_path, ".", out_path_size - 1); }
        return 1;
    } else if (strncmp(cmd, "load_state", 10) == 0) {
        const char* p = strstr(msg, "\"path\":\"");
        if (p) {
            p += 8;
            const char* end = strchr(p, '"');
            if (end && (end - p) < out_path_size) {
                memcpy(out_path, p, end - p);
                out_path[end - p] = '\0';
                return 2;
            }
        }
        fprintf(stderr, "[CMD] load_state requires \"path\"\n"); fflush(stderr);
    } else if (strncmp(cmd, "set_autosave", 12) == 0) {
        const char* val = strstr(msg, "\"interval\":");
        if (val) {
            int v = atoi(val + 11);
            if (v >= 0 && v <= 10000000) {
                snprintf(out_path, out_path_size, "%d", v);
                return 3;
            }
        }
    }
    return 0;
}

/* ── MAIN ────────────────────────────────────────────────────────────── */

int main(int argc, char** argv) {
    printf("\n=======================================================================\n");
    printf("  CRAW LBM v2 — Beast Efficiency Lessons Applied\n");
    printf("  Grid: %dx%d D2Q9 | omega: %.2f | Khra'gixx wave forcing\n", NX, NY, h_omega);
    printf("  Safety: rho[0.1,10.0] Mach<0.25 NaN-guard\n");
    printf("  ZMQ PUB:5556 SUB:5557 | KHRG checkpoints | cuFFT spectral\n");
    printf("=======================================================================\n\n");
    fflush(stdout);

    crc32_init();

    /* ── NVML ── */
    nvmlReturn_t nvml_rc = nvmlInit();
    nvmlDevice_t nvml_dev;
    int nvml_ok = 0;
    if (nvml_rc == NVML_SUCCESS &&
        nvmlDeviceGetHandleByIndex(0, &nvml_dev) == NVML_SUCCESS) {
        nvml_ok = 1;
        printf("[NVML] Hardware telemetry active\n");
    } else {
        printf("[NVML] Not available — running without hardware telemetry\n");
    }

    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    printf("[CUDA] %s (sm_%d%d)\n", prop.name, prop.major, prop.minor);
    printf("[VRAM] %.0f MB total\n\n", prop.totalGlobalMem / (1024.0 * 1024.0));
    fflush(stdout);

    /* ── GPU MEMORY ── */
    size_t fbuf = (size_t)Q * NN * sizeof(float);
    float *f0, *f1, *d_rho, *d_ux, *d_uy;
    CUDA_CHECK(cudaMalloc(&f0, fbuf));
    CUDA_CHECK(cudaMalloc(&f1, fbuf));
    CUDA_CHECK(cudaMalloc(&d_rho, NN * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&d_ux,  NN * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&d_uy,  NN * sizeof(float)));

    float* h_f   = (float*)malloc(fbuf);
    float* h_rho = (float*)malloc(NN * sizeof(float));
    if (!h_f || !h_rho) { fprintf(stderr, "malloc failed\n"); return 1; }

    printf("[MEM] GPU: 2x f[]=%.1f MB + fields=%.1f MB = %.1f MB\n",
           2.0 * fbuf / (1024 * 1024), 3.0 * NN * 4.0 / (1024 * 1024),
           (2.0 * fbuf + 3.0 * NN * 4.0) / (1024 * 1024));
    fflush(stdout);

    /* ── INIT ── */
    int step = 0;
    if (argc > 1) {
        step = load_checkpoint(argv[1], h_f, f0);
        if (step >= 0) {
            cudaMemcpy(f1, f0, fbuf, cudaMemcpyDeviceToDevice);
            printf("[INIT] Resumed from checkpoint at step %d\n", step);
        } else {
            step = 0;
            printf("[INIT] Checkpoint load failed, starting fresh\n");
        }
    }
    if (step == 0) {
        const float hw[Q] = {4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9,
                             1.f/36, 1.f/36, 1.f/36, 1.f/36};
        for (int idx = 0; idx < NN; idx++)
            for (int i = 0; i < Q; i++)
                h_f[i * NN + idx] = hw[i];
        CUDA_CHECK(cudaMemcpy(f0, h_f, fbuf, cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(f1, h_f, fbuf, cudaMemcpyHostToDevice));
        printf("[INIT] Equilibrium (rho=1.0)\n");
    }

    cudaMemcpyToSymbol(d_khra_amp, &h_khra_amp, sizeof(float));
    cudaMemcpyToSymbol(d_gixx_amp, &h_gixx_amp, sizeof(float));
    fflush(stdout);

    /* ── cuFFT for spectral analysis ── */
    cufftHandle plan;
    cufftPlan2d(&plan, NY, NX, CUFFT_R2C);
    int nx2 = NX / 2 + 1;
    cufftComplex *d_fft_ux, *d_fft_uy;
    CUDA_CHECK(cudaMalloc(&d_fft_ux, NY * nx2 * sizeof(cufftComplex)));
    CUDA_CHECK(cudaMalloc(&d_fft_uy, NY * nx2 * sizeof(cufftComplex)));
    int nk = NX / 2 + 1;
    double *d_spec;
    CUDA_CHECK(cudaMalloc(&d_spec, nk * sizeof(double)));
    double* h_spec = (double*)malloc(nk * sizeof(double));

    /* ── ZMQ: PUB telemetry on 5556 ── */
#ifdef HAS_ZMQ
    void* zmq_ctx   = zmq_ctx_new();
    void* publisher  = zmq_socket(zmq_ctx, ZMQ_PUB);
    void* subscriber = zmq_socket(zmq_ctx, ZMQ_SUB);
    int sndhwm = 1, linger = 0, rcvhwm = 10;
    zmq_setsockopt(publisher, ZMQ_SNDHWM, &sndhwm, sizeof(sndhwm));
    zmq_setsockopt(publisher, ZMQ_LINGER, &linger, sizeof(linger));
    if (zmq_bind(publisher, "tcp://127.0.0.1:5556") == 0)
        printf("[ZMQ] PUB bound on tcp://127.0.0.1:5556\n");
    else
        fprintf(stderr, "[ZMQ] PUB bind failed (port 5556)\n");

    zmq_setsockopt(subscriber, ZMQ_SUBSCRIBE, "", 0);
    zmq_setsockopt(subscriber, ZMQ_RCVHWM, &rcvhwm, sizeof(rcvhwm));
    zmq_setsockopt(subscriber, ZMQ_LINGER, &linger, sizeof(linger));
    if (zmq_bind(subscriber, "tcp://127.0.0.1:5557") == 0)
        printf("[ZMQ] SUB bound on tcp://127.0.0.1:5557\n");
    else
        fprintf(stderr, "[ZMQ] SUB bind failed (port 5557)\n");
#else
    printf("[ZMQ] Disabled (compile with -DHAS_ZMQ -lzmq to enable)\n");
#endif

    /* ── CSV LOG ── */
    FILE* csv = fopen("craw_telemetry.csv", "w");
    if (!csv) { fprintf(stderr, "Cannot create craw_telemetry.csv\n"); return 1; }
    fprintf(csv, "step,entropy,slope,coherence,asymmetry,omega,khra_amp,gixx_amp,"
                 "temp_c,power_w,mem_pct\n");

    printf("\n[RUNNING] Craw LBM v2 active — omega=%.2f khra=%.3f gixx=%.3f\n",
           h_omega, h_khra_amp, h_gixx_amp);
    printf("Step     | Entropy | Slope  | Coh   | Asym    | omega | T°C | Watts\n");
    printf("---------|---------|--------|-------|---------|-------|-----|------\n");
    fflush(stdout);

    int cur = 0;
    int autosave_interval = 50000;
    int last_autosave = step;
    int next_spectral = step + 2000;

    while (1) {
        /* ── Check ZMQ commands (non-blocking) ── */
#ifdef HAS_ZMQ
        char cmd_buf[256], cmd_path[512];
        int cmd_len = zmq_recv(subscriber, cmd_buf, sizeof(cmd_buf) - 1, ZMQ_DONTWAIT);
        if (cmd_len > 0) {
            cmd_buf[cmd_len] = '\0';
            cmd_path[0] = '\0';
            float* d_cur = (cur == 0) ? f0 : f1;
            int r = handle_command(cmd_buf, h_f, d_cur, cmd_path, sizeof(cmd_path));
            if (r == 1) {
                save_checkpoint(h_f, d_cur, step, cmd_path);
            } else if (r == 2) {
                int ls = load_checkpoint(cmd_path, h_f, d_cur);
                if (ls >= 0) {
                    step = ls;
                    next_spectral = step + 2000;
                    printf("[CMD] Resumed at step %d\n", step); fflush(stdout);
                }
            } else if (r == 3) {
                autosave_interval = atoi(cmd_path);
                last_autosave = step;
                printf("[CMD] Autosave → %d steps%s\n",
                       autosave_interval, autosave_interval == 0 ? " (off)" : "");
                fflush(stdout);
            }
        }
#endif

        /* ── LBM STEP ── */
        float *src = (cur == 0) ? f0 : f1;
        float *dst = (cur == 0) ? f1 : f0;
        lbm_step_v2<<<GBLK(NN), BLOCK>>>(src, dst, d_rho, d_ux, d_uy, h_omega, step);
        cur = 1 - cur;
        step++;

        /* ── LIGHT TELEMETRY every 100 steps (ZMQ PUB, rho-only) ── */
        if (step % 100 == 0) {
            cudaDeviceSynchronize();
            cudaMemcpy(h_rho, d_rho, NN * sizeof(float), cudaMemcpyDeviceToHost);

            float sum_sq = 0;
            for (int i = 0; i < NN; i++) {
                float dev = h_rho[i] - 1.0f;
                sum_sq += dev * dev;
            }
            float variance  = sum_sq / NN;
            float coherence = 1.0f / (1.0f + sqrtf(variance));
            float asymmetry = variance * 100.0f;

            unsigned int gpu_temp = 0, gpu_power_mw = 0;
            float gpu_mem_pct = 0;
            if (nvml_ok) {
                nvmlDeviceGetTemperature(nvml_dev, NVML_TEMPERATURE_GPU, &gpu_temp);
                nvmlDeviceGetPowerUsage(nvml_dev, &gpu_power_mw);
                nvmlMemory_t mem;
                if (nvmlDeviceGetMemoryInfo(nvml_dev, &mem) == NVML_SUCCESS)
                    gpu_mem_pct = (float)mem.used / (float)mem.total * 100.0f;
            }

#ifdef HAS_ZMQ
            char msg[512];
            snprintf(msg, sizeof(msg),
                "{\"step\":%d,\"coherence\":%.4f,\"asymmetry\":%.4f,"
                "\"omega\":%.3f,\"khra_amp\":%.4f,\"gixx_amp\":%.4f,\"grid\":512,"
                "\"gpu_temp_c\":%u,\"gpu_power_w\":%.1f,\"gpu_mem_pct\":%.1f}",
                step, coherence, asymmetry,
                h_omega, h_khra_amp, h_gixx_amp,
                gpu_temp, gpu_power_mw / 1000.0f, gpu_mem_pct);
            zmq_send(publisher, msg, strlen(msg), 0);
#endif
        }

        /* ── HEAVY SPECTRAL ANALYSIS every 2000 steps ── */
        if (step >= next_spectral) {
            cudaDeviceSynchronize();

            cufftExecR2C(plan, d_ux, d_fft_ux);
            cufftExecR2C(plan, d_uy, d_fft_uy);
            cudaDeviceSynchronize();

            cudaMemset(d_spec, 0, nk * sizeof(double));
            compute_spectrum<<<GBLK(NY * nx2), BLOCK>>>(d_fft_ux, d_fft_uy, d_spec, nk);
            cudaDeviceSynchronize();
            cudaMemcpy(h_spec, d_spec, nk * sizeof(double), cudaMemcpyDeviceToHost);

            double norm = 1.0 / ((double)NN * (double)NN);
            for (int k = 0; k < nk; k++) h_spec[k] *= norm;

            double entropy = calc_entropy(h_spec, nk);
            double slope   = calc_slope(h_spec, nk);

            /* Rho stats for display */
            cudaMemcpy(h_rho, d_rho, NN * sizeof(float), cudaMemcpyDeviceToHost);
            float sum_sq = 0;
            for (int i = 0; i < NN; i++) {
                float dev = h_rho[i] - 1.0f;
                sum_sq += dev * dev;
            }
            float coherence = 1.0f / (1.0f + sqrtf(sum_sq / NN));
            float asymmetry = (sum_sq / NN) * 100.0f;

            unsigned int gpu_temp = 0, gpu_power_mw = 0;
            float gpu_mem_pct = 0;
            if (nvml_ok) {
                nvmlDeviceGetTemperature(nvml_dev, NVML_TEMPERATURE_GPU, &gpu_temp);
                nvmlDeviceGetPowerUsage(nvml_dev, &gpu_power_mw);
                nvmlMemory_t mem;
                if (nvmlDeviceGetMemoryInfo(nvml_dev, &mem) == NVML_SUCCESS)
                    gpu_mem_pct = (float)mem.used / (float)mem.total * 100.0f;
            }

            printf("%8d | %7.3f | %+.2f | %.3f | %7.4f | %.2f | %2u°C | %.0fW\n",
                   step, entropy, slope, coherence, asymmetry,
                   h_omega, gpu_temp, gpu_power_mw / 1000.0f);
            fflush(stdout);

            fprintf(csv, "%d,%.6f,%.4f,%.4f,%.4f,%.3f,%.4f,%.4f,%u,%.1f,%.1f\n",
                    step, entropy, slope, coherence, asymmetry,
                    h_omega, h_khra_amp, h_gixx_amp,
                    gpu_temp, gpu_power_mw / 1000.0f, gpu_mem_pct);
            fflush(csv);

#ifdef HAS_ZMQ
            /* Publish spectral frame */
            char smsg[512];
            snprintf(smsg, sizeof(smsg),
                "{\"step\":%d,\"entropy\":%.6f,\"slope\":%.4f,"
                "\"coherence\":%.4f,\"asymmetry\":%.4f}",
                step, entropy, slope, coherence, asymmetry);
            zmq_send(publisher, smsg, strlen(smsg), 0);
#endif

            next_spectral += 2000;
        }

        /* ── AUTOSAVE ── */
        if (autosave_interval > 0 && (step - last_autosave) >= autosave_interval) {
            save_checkpoint(h_f, (cur == 0) ? f0 : f1, step, ".");
            last_autosave = step;
        }
    }

    /* Cleanup (unreachable in production) */
    fclose(csv);
    cudaFree(f0); cudaFree(f1);
    cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy);
    cudaFree(d_fft_ux); cudaFree(d_fft_uy); cudaFree(d_spec);
    free(h_f); free(h_rho); free(h_spec);
    cufftDestroy(plan);
#ifdef HAS_ZMQ
    zmq_close(publisher); zmq_close(subscriber); zmq_ctx_destroy(zmq_ctx);
#endif
    if (nvml_ok) nvmlShutdown();
    return 0;
}
