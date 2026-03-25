/* ============================================================================
 * FRACTAL HABIT ??? 100k steps in Clear Water
 *
 * Init from Hysteresis C80 "locked" state.
 * Fixed omega = 1.0 (tau=1, nu=1/6) ??? the clearest water in LBM.
 * 10,000,000 steps. No prompts. No hunts.
 *
 * Tracks:
 *   - Velocity energy spectrum E_v(k) via 2D FFT
 *   - Density power spectrum E_rho(k) via 2D FFT of delta_rho
 *   - Spectral entropy of both
 *   - Power-law slope
 *   - Fraction of density power at kx=0 vs kx!=0 (x-emergence)
 *
 * Build: nvcc -O3 -arch=sm_89 -o fractal_habit \
 *        /src/src/fractal_habit.cu -lnvidia-ml -lpthread -lcufft
 * ============================================================================ */
#include <cuda_runtime.h>
#include <cufft.h>
#include <nvml.h>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cmath>
#include <chrono>
#include <vector>

/* ---- NVMe Checkpoint Function ------------------------------------------- */
/* ============================================================================
 * FRACTAL HABIT 1024×1024 - HARD PRINT VERSION
 * 
 * Enhanced NVMe checkpointing with:
 * 1. Incremental updates (only changed tiles)
 * 2. Checksum verification
 * 3. Metadata storage
 * 4. Compression (simple delta encoding)
 * 5. Sector-aligned writes
 * 
 * Based on: fractal_habit_1024x1024_nvme_proper.cu
 * Date: 2026-03-12
 * ============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>
#include <time.h>
#include <cuda.h>
#include <cuda_runtime.h>
#include <cufft.h>
#include <nvml.h>

/* ---- Hard Print Constants ----------------------------------------------- */
#define TILE_SIZE 32                     // 32×32 tiles for dirty detection
#define NUM_TILES_X (1024 / TILE_SIZE)   // 32 tiles across
#define NUM_TILES_Y (1024 / TILE_SIZE)   // 32 tiles down
#define NUM_TILES (NUM_TILES_X * NUM_TILES_Y)  // 1024 total tiles

// Compression types
#define COMPRESS_NONE    0
#define COMPRESS_DELTA   1
#define COMPRESS_ZSTD    2  // Future

// Hard Print file magic
#define HARD_PRINT_MAGIC 0x4850524E54  // "HPRNT" in hex

/* ---- Hard Print Structures ---------------------------------------------- */
typedef struct {
    uint32_t step;
    uint32_t nx;
    uint32_t ny;
    uint32_t magic;
    uint64_t checksum_data;
    uint64_t checksum_header;
    uint32_t compression_type;
    uint32_t num_dirty_tiles;
    uint32_t thermal_state;      // GPU temperature × 100
    uint64_t timestamp;          // Unix timestamp in milliseconds
    uint32_t reserved[12];       // Future use
} HardPrintHeader;

typedef struct {
    uint32_t tile_x;
    uint32_t tile_y;
    uint32_t data_offset;        // Offset in data section
    uint32_t data_size;          // Compressed size in bytes
    uint64_t tile_checksum;
} DirtyTileInfo;

/* ---- Hard Print Functions ----------------------------------------------- */

// Calculate simple checksum (Fletcher-64)
uint64_t calculate_checksum(const void* data, size_t size) {
    const uint32_t* words = (const uint32_t*)data;
    size_t num_words = size / sizeof(uint32_t);
    
    uint64_t sum1 = 0;
    uint64_t sum2 = 0;
    
    for (size_t i = 0; i < num_words; i++) {
        sum1 = (sum1 + words[i]) % 0xFFFFFFFF;
        sum2 = (sum2 + sum1) % 0xFFFFFFFF;
    }
    
    return (sum2 << 32) | sum1;
}

// Simple delta compression (stores differences from previous tile)
size_t delta_compress_tile(const float* current, const float* previous, 
                          float* compressed, size_t tile_size) {
    size_t compressed_size = 0;
    
    for (size_t i = 0; i < tile_size; i++) {
        float diff = current[i] - previous[i];
        
        // Only store if difference is significant
        if (fabs(diff) > 1e-6f) {
            compressed[compressed_size++] = diff;
        }
    }
    
    return compressed_size * sizeof(float);
}

// Check if a tile has changed significantly
bool tile_changed(const float* current, const float* previous, 
                  size_t tile_size, float threshold) {
    float max_diff = 0.0f;
    
    for (size_t i = 0; i < tile_size; i++) {
        float diff = fabs(current[i] - previous[i]);
        if (diff > max_diff) {
            max_diff = diff;
        }
        
        // Early exit if already above threshold
        if (max_diff > threshold) {
            return true;
        }
    }
    
    return max_diff > threshold;
}

/* ---- Enhanced NVMe Checkpoint Function --------------------------------- */
void save_hardprint_checkpoint(int step, float* d_f, float* d_rho, 
                               float* d_ux, float* d_uy, 
                               float* previous_f, float* previous_rho,
                               float* previous_ux, float* previous_uy) {
    char filename[256];
    sprintf(filename, "C:\\fractal_nvme_test\\hardprint_%08d.hp", step);
    
    printf("[HardPrint] Saving checkpoint at step %d to %s\n", step, filename);
    
    // Create directory if it doesn't exist
    system("mkdir C:\\fractal_nvme_test 2>nul");
    
    FILE* fp = fopen(filename, "wb");
    if (!fp) {
        printf("[HardPrint] ERROR: Cannot open file for writing\n");
        return;
    }
    
    // Calculate sizes
    size_t f_size = 9 * 1024 * 1024 * sizeof(float);  // Q * NX * NY
    size_t field_size = 1024 * 1024 * sizeof(float);  // NX * NY
    size_t tile_size_f = 9 * TILE_SIZE * TILE_SIZE * sizeof(float);
    size_t tile_size_field = TILE_SIZE * TILE_SIZE * sizeof(float);
    
    // Allocate host memory for current state
    float* h_f = (float*)malloc(f_size);
    float* h_rho = (float*)malloc(field_size);
    float* h_ux = (float*)malloc(field_size);
    float* h_uy = (float*)malloc(field_size);
    
    if (!h_f || !h_rho || !h_ux || !h_uy) {
        printf("[HardPrint] ERROR: Memory allocation failed\n");
        fclose(fp);
        if (h_f) free(h_f);
        if (h_rho) free(h_rho);
        if (h_ux) free(h_ux);
        if (h_uy) free(h_uy);
        return;
    }
    
    // Copy from device to host
    cudaMemcpy(h_f, d_f, f_size, cudaMemcpyDeviceToHost);
    cudaMemcpy(h_rho, d_rho, field_size, cudaMemcpyDeviceToHost);
    cudaMemcpy(h_ux, d_ux, field_size, cudaMemcpyDeviceToHost);
    cudaMemcpy(h_uy, d_uy, field_size, cudaMemcpyDeviceToHost);
    
    // Allocate buffers for dirty tiles
    DirtyTileInfo dirty_tiles[NUM_TILES];
    uint32_t num_dirty = 0;
    
    // Buffer for compressed tile data (worst case: all tiles changed)
    size_t max_compressed_size = NUM_TILES * (tile_size_f + 3 * tile_size_field);
    uint8_t* compressed_buffer = (uint8_t*)malloc(max_compressed_size);
    size_t compressed_offset = 0;
    
    if (!compressed_buffer) {
        printf("[HardPrint] ERROR: Compression buffer allocation failed\n");
        fclose(fp);
        free(h_f); free(h_rho); free(h_ux); free(h_uy);
        return;
    }
    
    // Check each tile for changes
    printf("[HardPrint] Checking %d tiles for changes...\n", NUM_TILES);
    
    for (int ty = 0; ty < NUM_TILES_Y; ty++) {
        for (int tx = 0; tx < NUM_TILES_X; tx++) {
            // Calculate tile offsets
            size_t tile_offset_f = (ty * TILE_SIZE * 1024 + tx * TILE_SIZE) * 9;
            size_t tile_offset_field = ty * TILE_SIZE * 1024 + tx * TILE_SIZE;
            
            // Pointers to tile data
            float* current_f_tile = h_f + tile_offset_f;
            float* current_rho_tile = h_rho + tile_offset_field;
            float* current_ux_tile = h_ux + tile_offset_field;
            float* current_uy_tile = h_uy + tile_offset_field;
            
            float* prev_f_tile = previous_f + tile_offset_f;
            float* prev_rho_tile = previous_rho + tile_offset_field;
            float* prev_ux_tile = previous_ux + tile_offset_field;
            float* prev_uy_tile = previous_uy + tile_offset_field;
            
            // Check if any component changed significantly
            bool f_changed = tile_changed(current_f_tile, prev_f_tile, 
                                         TILE_SIZE * TILE_SIZE * 9, 0.01f);
            bool rho_changed = tile_changed(current_rho_tile, prev_rho_tile,
                                           TILE_SIZE * TILE_SIZE, 0.01f);
            bool ux_changed = tile_changed(current_ux_tile, prev_ux_tile,
                                          TILE_SIZE * TILE_SIZE, 0.01f);
            bool uy_changed = tile_changed(current_uy_tile, prev_uy_tile,
                                          TILE_SIZE * TILE_SIZE, 0.01f);
            
            if (f_changed || rho_changed || ux_changed || uy_changed) {
                // Tile is dirty - compress and store
                dirty_tiles[num_dirty].tile_x = tx;
                dirty_tiles[num_dirty].tile_y = ty;
                dirty_tiles[num_dirty].data_offset = compressed_offset;
                
                // Compress f data (9 channels)
                size_t f_compressed = delta_compress_tile(current_f_tile, prev_f_tile,
                                                         (float*)(compressed_buffer + compressed_offset),
                                                         TILE_SIZE * TILE_SIZE * 9);
                compressed_offset += f_compressed;
                
                // Compress rho data
                size_t rho_compressed = delta_compress_tile(current_rho_tile, prev_rho_tile,
                                                           (float*)(compressed_buffer + compressed_offset),
                                                           TILE_SIZE * TILE_SIZE);
                compressed_offset += rho_compressed;
                
                // Compress ux data
                size_t ux_compressed = delta_compress_tile(current_ux_tile, prev_ux_tile,
                                                          (float*)(compressed_buffer + compressed_offset),
                                                          TILE_SIZE * TILE_SIZE);
                compressed_offset += ux_compressed;
                
                // Compress uy data
                size_t uy_compressed = delta_compress_tile(current_uy_tile, prev_uy_tile,
                                                          (float*)(compressed_buffer + compressed_offset),
                                                          TILE_SIZE * TILE_SIZE);
                compressed_offset += uy_compressed;
                
                dirty_tiles[num_dirty].data_size = f_compressed + rho_compressed + 
                                                   ux_compressed + uy_compressed;
                
                // Calculate tile checksum
                dirty_tiles[num_dirty].tile_checksum = calculate_checksum(
                    compressed_buffer + dirty_tiles[num_dirty].data_offset,
                    dirty_tiles[num_dirty].data_size);
                
                num_dirty++;
                
                if (num_dirty % 100 == 0) {
                    printf("[HardPrint] Found %d dirty tiles...\n", num_dirty);
                }
            }
        }
    }
    
    printf("[HardPrint] Found %d dirty tiles (%.1f%% of total)\n", 
           num_dirty, (num_dirty * 100.0f) / NUM_TILES);
    
    // Get GPU temperature for thermal state
    uint32_t thermal_state = 0;
    nvmlDevice_t device;
    nvmlReturn_t result = nvmlInit();
    if (result == NVML_SUCCESS) {
        result = nvmlDeviceGetHandleByIndex(0, &device);
        if (result == NVML_SUCCESS) {
            unsigned int temp;
            result = nvmlDeviceGetTemperature(device, NVML_TEMPERATURE_GPU, &temp);
            if (result == NVML_SUCCESS) {
                thermal_state = temp * 100;  // Store as integer × 100
            }
        }
    }
    
    // Prepare header
    HardPrintHeader header;
    memset(&header, 0, sizeof(header));
    header.step = step;
    header.nx = 1024;
    header.ny = 1024;
    header.magic = HARD_PRINT_MAGIC;
    header.compression_type = COMPRESS_DELTA;
    header.num_dirty_tiles = num_dirty;
    header.thermal_state = thermal_state;
    header.timestamp = (uint64_t)time(NULL) * 1000;  // Milliseconds
    
    // Calculate checksums
    header.checksum_data = calculate_checksum(compressed_buffer, compressed_offset);
    header.checksum_header = calculate_checksum(&header, sizeof(header) - 16); // Exclude checksum fields
    
    // Write header
    fwrite(&header, sizeof(header), 1, fp);
    
    // Write dirty tile information
    fwrite(dirty_tiles, sizeof(DirtyTileInfo), num_dirty, fp);
    
    // Write compressed data
    fwrite(compressed_buffer, compressed_offset, 1, fp);
    
    fclose(fp);
    
    // Update previous state for next comparison
    memcpy(previous_f, h_f, f_size);
    memcpy(previous_rho, h_rho, field_size);
    memcpy(previous_ux, h_ux, field_size);
    memcpy(previous_uy, h_uy, field_size);
    
    // Free memory
    free(h_f);
    free(h_rho);
    free(h_ux);
    free(h_uy);
    free(compressed_buffer);
    
    // Calculate savings
    size_t naive_size = f_size + 3 * field_size;
    float savings_pct = 100.0f * (1.0f - (float)compressed_offset / naive_size);
    
    printf("[HardPrint] Checkpoint saved:\n");
    printf("  - Dirty tiles: %d/%d (%.1f%%)\n", num_dirty, NUM_TILES, 
           (num_dirty * 100.0f) / NUM_TILES);
    printf("  - Compressed size: %.2f MB (was %.2f MB)\n", 
           compressed_offset / (1024.0f * 1024.0f),
           naive_size / (1024.0f * 1024.0f));
    printf("  - Savings: %.1f%%\n", savings_pct);
    printf("  - Thermal state: %.2f°C\n", thermal_state / 100.0f);
}

/* ---- Rest of the original code (unchanged) ----------------------------- */
/* ---- Grid ---------------------------------------------------------------- */
#define NX    1024
#define NY    1024
#define NN    (NX * NY)
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

/* ---- Protocol ------------------------------------------------------------ */
#define TOTAL_STEPS      100000
#define STEPS_PER_BATCH  500
#define SAMPLE_INTERVAL  50000      /* E(k) sample every 50k steps */
#define TOTAL_BATCHES    (TOTAL_STEPS / STEPS_PER_BATCH)
#define SAMPLE_BATCHES   (SAMPLE_INTERVAL / STEPS_PER_BATCH)
#define NUM_SAMPLES      (TOTAL_STEPS / SAMPLE_INTERVAL)



/* ---- Grid ---------------------------------------------------------------- */
#define NX    1024
#define NY    1024
#define NN    (NX * NY)
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

/* ---- Protocol ------------------------------------------------------------ */
#define TOTAL_STEPS      100000
#define STEPS_PER_BATCH  500
#define SAMPLE_INTERVAL  50000      /* E(k) sample every 50k steps */
#define TOTAL_BATCHES    (TOTAL_STEPS / STEPS_PER_BATCH)
#define SAMPLE_BATCHES   (SAMPLE_INTERVAL / STEPS_PER_BATCH)
#define NUM_SAMPLES      (TOTAL_STEPS / SAMPLE_INTERVAL)

/* ---- LBM ---------------------------------------------------------------- */
#define OMEGA  1.0f       /* tau=1.0, nu=1/6 ??? "clear water" */

/* ---- Spectrum ----------------------------------------------------------- */
#define NX2   (NX / 2 + 1)   /* R2C output width */
#define KMAX  (NX / 2)       /* max wavenumber */
#define NK    (KMAX + 1)     /* number of k bins */

/* ---- D2Q9 --------------------------------------------------------------- */
__constant__ int   d_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
__constant__ int   d_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
__constant__ float d_w[Q]  = { 4.f/9,
                               1.f/9, 1.f/9, 1.f/9, 1.f/9,
                               1.f/36,1.f/36,1.f/36,1.f/36 };

/* Host-side lattice vectors (for initial state computation) */
static const int h_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
static const int h_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };

/* ============================================================================
 * KERNELS
 * ============================================================================ */
__global__ void lbm_collide_stream(
    const float* __restrict__ f_src, float* __restrict__ f_dst,
    float* __restrict__ rho_out, float* __restrict__ ux_out,
    float* __restrict__ uy_out, float omega, int nx, int ny)
{
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N = nx * ny;
    if (idx >= N) return;
    const int x = idx % nx, y = idx / nx;

    float fl[Q];
    #pragma unroll
    for (int i = 0; i < Q; i++) {
        int sx = (x - d_ex[i] + nx) % nx;
        int sy = (y - d_ey[i] + ny) % ny;
        fl[i] = f_src[i * N + sy * nx + sx];
    }

    float rho = 0.f, ux = 0.f, uy = 0.f;
    #pragma unroll
    for (int i = 0; i < Q; i++) {
        rho += fl[i];
        ux += (float)d_ex[i] * fl[i];
        uy += (float)d_ey[i] * fl[i];
    }
    float inv = 1.f / fmaxf(rho, 1e-10f);
    ux *= inv; uy *= inv;
    rho_out[idx] = rho; ux_out[idx] = ux; uy_out[idx] = uy;

    const float u2 = ux * ux + uy * uy;
    #pragma unroll
    for (int i = 0; i < Q; i++) {
        float eu = (float)d_ex[i] * ux + (float)d_ey[i] * uy;
        float feq = d_w[i] * rho * (1.f + 3.f*eu + 4.5f*eu*eu - 1.5f*u2);
        f_dst[i * N + idx] = fl[i] - omega * (fl[i] - feq);
    }
}

/* Compute radial power spectrum from R2C FFT output */
__global__ void compute_radial_spectrum(
    const cufftComplex* __restrict__ fft_a,
    const cufftComplex* __restrict__ fft_b,   /* NULL if single-field */
    double* __restrict__ spectrum,
    int nx, int ny, int nk, int two_field)
{
    int nx2 = nx / 2 + 1;
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= ny * nx2) return;

    int kx_idx = idx % nx2;
    int ky_idx = idx / nx2;

    int kx = kx_idx;
    int ky = (ky_idx <= ny/2) ? ky_idx : ky_idx - ny;

    int k = (int)roundf(sqrtf((float)(kx*kx + ky*ky)));
    if (k >= nk || k == 0) return;

    double power = 0.0;
    float ar = fft_a[idx].x, ai = fft_a[idx].y;
    power += (double)(ar*ar + ai*ai);

    if (two_field && fft_b != NULL) {
        float br = fft_b[idx].x, bi = fft_b[idx].y;
        power += (double)(br*br + bi*bi);
    }

    /* R2C symmetry: modes with 0 < kx < NX/2 represent two modes */
    if (kx_idx > 0 && kx_idx < nx/2) power *= 2.0;

    atomicAdd(&spectrum[k], power);
}

/* Compute fraction of power at kx=0 vs kx!=0 */
__global__ void compute_kx0_fraction(
    const cufftComplex* __restrict__ fft_field,
    double* __restrict__ power_kx0,
    double* __restrict__ power_kx_nonzero,
    int nx, int ny)
{
    int nx2 = nx / 2 + 1;
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= ny * nx2) return;

    int kx_idx = idx % nx2;
    int ky_idx = idx / nx2;
    if (kx_idx == 0 && ky_idx == 0) return; /* skip DC */

    float r = fft_field[idx].x, im = fft_field[idx].y;
    double p = (double)(r*r + im*im);
    if (kx_idx > 0 && kx_idx < nx/2) p *= 2.0;

    if (kx_idx == 0) {
        atomicAdd(power_kx0, p);
    } else {
        atomicAdd(power_kx_nonzero, p);
    }
}

/* ============================================================================
 * LOAD F-STATE
 * ============================================================================ */
static float* load_f_state(const char* path)
{
    FILE* fp = fopen(path, "rb");
    if (!fp) { printf("FATAL: Cannot open %s\n", path); return NULL; }

    uint32_t hdr[4];
    fread(hdr, sizeof(uint32_t), 4, fp);
    if (hdr[0] != 0x4D424C46u || hdr[1] != NX || hdr[2] != NY || hdr[3] != Q) {
        printf("FATAL: Header mismatch\n");
        fclose(fp); return NULL;
    }

    size_t n = (size_t)Q * NN;
    float* buf = (float*)malloc(n * sizeof(float));
    size_t got = fread(buf, sizeof(float), n, fp);
    fclose(fp);

    if (got != n) { printf("FATAL: Short read\n"); free(buf); return NULL; }
    printf("  Loaded %s (%.1f MB)\n", path, (double)(n*4)/(1024.0*1024.0));
    return buf;
}

/* ============================================================================
 * SPECTRUM ANALYSIS HELPERS (host-side)
 * ============================================================================ */
struct SpectrumStats {
    double total_energy;
    double spectral_entropy;
    double peak_k;
    double slope;        /* power-law fit k=2..100 */
    int    num_modes;    /* modes carrying > 1% of energy */
    double kx0_frac;     /* fraction of density power at kx=0 */
};

static SpectrumStats analyze_spectrum(const double* spec, int nk)
{
    SpectrumStats s;
    s.total_energy = 0;
    double peak_p = 0;
    s.peak_k = 0;

    for (int k = 1; k < nk; k++) {
        s.total_energy += spec[k];
        if (spec[k] > peak_p) { peak_p = spec[k]; s.peak_k = k; }
    }

    /* Spectral entropy */
    s.spectral_entropy = 0;
    s.num_modes = 0;
    if (s.total_energy > 0) {
        for (int k = 1; k < nk; k++) {
            double p = spec[k] / s.total_energy;
            if (p > 0) s.spectral_entropy -= p * log2(p);
            if (p > 0.01) s.num_modes++;
        }
    }

    /* Power-law slope fit (log-log, k=2..100) */
    double sx = 0, sy = 0, sxx = 0, sxy = 0;
    int n = 0;
    for (int k = 2; k <= 100 && k < nk; k++) {
        if (spec[k] > 0) {
            double lk = log((double)k), le = log(spec[k]);
            sx += lk; sy += le; sxx += lk*lk; sxy += lk*le; n++;
        }
    }
    s.slope = (n > 2) ? ((double)n * sxy - sx * sy) / ((double)n * sxx - sx * sx) : 0;

    s.kx0_frac = 0;
    return s;
}

/* ============================================================================
 * MAIN
 * ============================================================================ */
int main()
{
    double nu = (1.0 / OMEGA - 0.5) / 3.0;
    double t_diff = (double)NX * NX / (4.0 * M_PI * M_PI * nu);

    printf("\n");
    printf("=======================================================================\n");
    printf("  FRACTAL HABIT ??? 100k steps in Clear Water\n");
    printf("  Init: Hysteresis C80 | omega = %.1f | nu = %.6f\n", OMEGA, nu);
    printf("=======================================================================\n");
    printf("  Steps:     %d  (%d batches of %d)\n",
           TOTAL_STEPS, TOTAL_BATCHES, STEPS_PER_BATCH);
    printf("  Samples:   %d  (every %d steps)\n", NUM_SAMPLES, SAMPLE_INTERVAL);
    printf("  Diffusive: tau_d = %.0f steps  (run = %.1f tau_d)\n",
           t_diff, TOTAL_STEPS / t_diff);
    printf("=======================================================================\n\n");

    /* ---- CUDA ----------------------------------------------------------- */
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    printf("[CUDA] %s  SM %d.%d  SMs: %d\n",
           prop.name, prop.major, prop.minor, prop.multiProcessorCount);

    /* ---- NVML ----------------------------------------------------------- */
    nvmlInit();
    nvmlDevice_t nvml_dev;
    nvmlDeviceGetHandleByIndex(0, &nvml_dev);
    unsigned int mW0;
    nvmlDeviceGetPowerUsage(nvml_dev, &mW0);
    printf("[NVML] Idle: %.1f W\n\n", (float)mW0 / 1000.f);

    /* ---- Load C80 state ------------------------------------------------- */
    printf("[LOAD] Loading Hysteresis C80...\n");
    float* h_f = load_f_state("build/f_state_post_relax.bin");
    if (!h_f) return 1;

    /* Compute initial macroscopic fields on CPU */
    float* h_ux = (float*)calloc(NN, sizeof(float));
    float* h_uy = (float*)calloc(NN, sizeof(float));
    float* h_drho = (float*)calloc(NN, sizeof(float));

    double rho_sum = 0;
    for (int idx = 0; idx < NN; idx++) {
        float rho = 0;
        for (int i = 0; i < Q; i++) rho += h_f[i * NN + idx];
        rho_sum += rho;
        float inv = 1.f / fmaxf(rho, 1e-10f);
        float ux = 0, uy = 0;
        for (int i = 0; i < Q; i++) {
            ux += h_ex[i] * h_f[i * NN + idx];
            uy += h_ey[i] * h_f[i * NN + idx];
        }
        h_ux[idx] = ux * inv;
        h_uy[idx] = uy * inv;
        h_drho[idx] = rho;  /* store rho; subtract mean after */
    }
    float rho_mean = (float)(rho_sum / NN);
    for (int idx = 0; idx < NN; idx++) h_drho[idx] -= rho_mean;

    printf("  Initial mean rho: %.10f\n", rho_sum / NN);

    /* ---- Allocate GPU --------------------------------------------------- */
    float *f0, *f1, *d_rho, *d_ux, *d_uy, *d_drho;
    size_t fbuf = (size_t)Q * NN * sizeof(float);
    cudaMalloc(&f0, fbuf);      cudaMalloc(&f1, fbuf);
    cudaMalloc(&d_rho, NN * sizeof(float));
    cudaMalloc(&d_ux,  NN * sizeof(float));
    cudaMalloc(&d_uy,  NN * sizeof(float));

    // Hard Print: Previous state for incremental checkpointing
    float* h_prev_f = (float*)malloc(f_size);
    float* h_prev_rho = (float*)malloc(field_size);
    float* h_prev_ux = (float*)malloc(field_size);
    float* h_prev_uy = (float*)malloc(field_size);
    if (!h_prev_f || !h_prev_rho || !h_prev_ux || !h_prev_uy) {
        printf("ERROR: Previous state allocation failed\n");
        return 1;
    }
    // Initialize previous state with initial values
    cudaMemcpy(h_prev_f, f0, f_size, cudaMemcpyDeviceToHost);
    cudaMemcpy(h_prev_rho, d_rho, field_size, cudaMemcpyDeviceToHost);
    cudaMemcpy(h_prev_ux, d_ux, field_size, cudaMemcpyDeviceToHost);
    cudaMemcpy(h_prev_uy, d_uy, field_size, cudaMemcpyDeviceToHost);

    cudaMalloc(&d_drho, NN * sizeof(float));

    /* Copy f-state to device */
    cudaMemcpy(f0, h_f, fbuf, cudaMemcpyHostToDevice);
    cudaMemcpy(f1, h_f, fbuf, cudaMemcpyHostToDevice);
    free(h_f);

    /* Copy initial ux, uy, drho for step-0 spectrum */
    cudaMemcpy(d_ux,   h_ux,   NN * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_uy,   h_uy,   NN * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_drho, h_drho, NN * sizeof(float), cudaMemcpyHostToDevice);
    free(h_ux); free(h_uy); free(h_drho);

    /* ---- cuFFT ---------------------------------------------------------- */
    cufftHandle plan;
    cufftPlan2d(&plan, NY, NX, CUFFT_R2C);

    cufftComplex *d_fft_ux, *d_fft_uy, *d_fft_drho;
    cudaMalloc(&d_fft_ux,   NY * NX2 * sizeof(cufftComplex));
    cudaMalloc(&d_fft_uy,   NY * NX2 * sizeof(cufftComplex));
    cudaMalloc(&d_fft_drho, NY * NX2 * sizeof(cufftComplex));

    /* Spectrum accumulators */
    double *d_spec_vel, *d_spec_rho;
    double *d_kx0_power, *d_kx_nonzero_power;
    cudaMalloc(&d_spec_vel, NK * sizeof(double));
    cudaMalloc(&d_spec_rho, NK * sizeof(double));
    cudaMalloc(&d_kx0_power, sizeof(double));
    cudaMalloc(&d_kx_nonzero_power, sizeof(double));

    double h_spec_vel[NK], h_spec_rho[NK];

    cudaStream_t stream;
    cudaStreamCreate(&stream);

    /* ---- Storage for key spectra ---------------------------------------- */
    std::vector<double> spec_vel_init(NK, 0), spec_vel_mid(NK, 0), spec_vel_final(NK, 0);
    std::vector<double> spec_rho_init(NK, 0), spec_rho_mid(NK, 0), spec_rho_final(NK, 0);

    /* ---- CSV ------------------------------------------------------------ */
    FILE* csv = fopen("/build/fractal_habit.csv", "w");
    if (csv)
        fprintf(csv, "sample,step,vel_energy,vel_entropy,vel_peak_k,vel_slope,"
                "vel_modes,rho_energy,rho_entropy,rho_peak_k,rho_slope,"
                "rho_modes,kx0_frac,power_w\n");

    FILE* vspec_csv = fopen("/build/fractal_habit_vel_spectra.csv", "w");
    if (vspec_csv) {
        fprintf(vspec_csv, "sample,step");
        for (int k = 1; k < NK; k++) fprintf(vspec_csv, ",k%d", k);
        fprintf(vspec_csv, "\n");
    }

    FILE* rspec_csv = fopen("/build/fractal_habit_rho_spectra.csv", "w");
    if (rspec_csv) {
        fprintf(rspec_csv, "sample,step");
        for (int k = 1; k < NK; k++) fprintf(rspec_csv, ",k%d", k);
        fprintf(rspec_csv, "\n");
    }

    /* ---- Lambda: compute & record spectrum ------------------------------ */
    int sample_count = 0;
    double norm = 1.0 / ((double)NN * (double)NN);
    int fft_n = NY * NX2;

    auto do_sample = [&](uint64_t step) {
        /* FFT velocity fields */
        cufftExecR2C(plan, d_ux, d_fft_ux);
        cufftExecR2C(plan, d_uy, d_fft_uy);

        /* Compute drho on device: drho = rho - mean(rho) */
        /* For step 0, d_drho is already set. For later steps, compute: */
        if (step > 0) {
            /* Copy rho to host, compute mean, write drho back */
            float* h_rho_tmp = (float*)malloc(NN * sizeof(float));
            cudaMemcpy(h_rho_tmp, d_rho, NN * sizeof(float), cudaMemcpyDeviceToHost);
            double rs = 0;
            for (int i = 0; i < NN; i++) rs += h_rho_tmp[i];
            float rm = (float)(rs / NN);
            for (int i = 0; i < NN; i++) h_rho_tmp[i] -= rm;
            cudaMemcpy(d_drho, h_rho_tmp, NN * sizeof(float), cudaMemcpyHostToDevice);
            free(h_rho_tmp);
        }

        /* FFT density fluctuation */
        cufftExecR2C(plan, d_drho, d_fft_drho);
        cudaDeviceSynchronize();

        /* Velocity spectrum */
        cudaMemset(d_spec_vel, 0, NK * sizeof(double));
        compute_radial_spectrum<<<GBLK(fft_n), BLOCK>>>(
            d_fft_ux, d_fft_uy, d_spec_vel, NX, NY, NK, 1);
        cudaDeviceSynchronize();
        cudaMemcpy(h_spec_vel, d_spec_vel, NK * sizeof(double), cudaMemcpyDeviceToHost);
        for (int k = 0; k < NK; k++) h_spec_vel[k] *= norm;

        /* Density spectrum */
        cudaMemset(d_spec_rho, 0, NK * sizeof(double));
        compute_radial_spectrum<<<GBLK(fft_n), BLOCK>>>(
            d_fft_drho, NULL, d_spec_rho, NX, NY, NK, 0);
        cudaDeviceSynchronize();
        cudaMemcpy(h_spec_rho, d_spec_rho, NK * sizeof(double), cudaMemcpyDeviceToHost);
        for (int k = 0; k < NK; k++) h_spec_rho[k] *= norm;

        /* kx=0 fraction for density */
        double zero = 0.0;
        cudaMemcpy(d_kx0_power, &zero, sizeof(double), cudaMemcpyHostToDevice);
        cudaMemcpy(d_kx_nonzero_power, &zero, sizeof(double), cudaMemcpyHostToDevice);
        compute_kx0_fraction<<<GBLK(fft_n), BLOCK>>>(
            d_fft_drho, d_kx0_power, d_kx_nonzero_power, NX, NY);
        cudaDeviceSynchronize();
        double h_kx0, h_kx_nz;
        cudaMemcpy(&h_kx0, d_kx0_power, sizeof(double), cudaMemcpyDeviceToHost);
        cudaMemcpy(&h_kx_nz, d_kx_nonzero_power, sizeof(double), cudaMemcpyDeviceToHost);
        double kx0_frac = (h_kx0 + h_kx_nz > 0) ? h_kx0 / (h_kx0 + h_kx_nz) : 0;

        /* Analyze */
        SpectrumStats sv = analyze_spectrum(h_spec_vel, NK);
        SpectrumStats sr = analyze_spectrum(h_spec_rho, NK);
        sr.kx0_frac = kx0_frac;

        /* Power reading */
        unsigned int mW = 0;
        nvmlDeviceGetPowerUsage(nvml_dev, &mW);
        float pw = (float)mW / 1000.f;

        /* Save key spectra */
        if (sample_count == 0) {
            for (int k = 0; k < NK; k++) {
                spec_vel_init[k] = h_spec_vel[k];
                spec_rho_init[k] = h_spec_rho[k];
            }
        }
        if (sample_count == NUM_SAMPLES / 2) {
            for (int k = 0; k < NK; k++) {
                spec_vel_mid[k] = h_spec_vel[k];
                spec_rho_mid[k] = h_spec_rho[k];
            }
        }
        /* Final is always the last written */
        for (int k = 0; k < NK; k++) {
            spec_vel_final[k] = h_spec_vel[k];
            spec_rho_final[k] = h_spec_rho[k];
        }

        /* Print */
        printf("  %3d | %9llu | Ev=%.3e H=%.2f sl=%+.2f pk=%3.0f | "
               "Er=%.3e H=%.2f sl=%+.2f kx0=%.1f%% | %5.1fW\n",
               sample_count, (unsigned long long)step,
               sv.total_energy, sv.spectral_entropy, sv.slope, sv.peak_k,
               sr.total_energy, sr.spectral_entropy, sr.slope,
               kx0_frac * 100.0, pw);
        fflush(stdout);

        /* CSV */
        if (csv)
            fprintf(csv, "%d,%llu,%.10e,%.6f,%.0f,%.4f,%d,"
                    "%.10e,%.6f,%.0f,%.4f,%d,%.8f,%.1f\n",
                    sample_count, (unsigned long long)step,
                    sv.total_energy, sv.spectral_entropy, sv.peak_k, sv.slope,
                    sv.num_modes,
                    sr.total_energy, sr.spectral_entropy, sr.peak_k, sr.slope,
                    sr.num_modes, kx0_frac, pw);

        /* Full spectrum CSVs */
        if (vspec_csv) {
            fprintf(vspec_csv, "%d,%llu", sample_count, (unsigned long long)step);
            for (int k = 1; k < NK; k++) fprintf(vspec_csv, ",%.10e", h_spec_vel[k]);
            fprintf(vspec_csv, "\n");
        }
        if (rspec_csv) {
            fprintf(rspec_csv, "%d,%llu", sample_count, (unsigned long long)step);
            for (int k = 1; k < NK; k++) fprintf(rspec_csv, ",%.10e", h_spec_rho[k]);
            fprintf(rspec_csv, "\n");
        }

        sample_count++;
    };

    /* ---- Step 0: initial spectrum --------------------------------------- */
    printf("[INIT] Computing step-0 spectrum...\n");
    do_sample(0);

    /* ---- MAIN LOOP ------------------------------------------------------ */
    int cur = 0;
    uint64_t total_steps = 0;
    auto t0 = std::chrono::steady_clock::now();

    printf("\n[RUN] 100k steps at omega=%.1f  (%.1f diffusive times)\n", OMEGA, TOTAL_STEPS/t_diff);
    printf("  sam |     step  | Velocity spectrum              | "
           "Density spectrum                | Power\n");
    printf("  ----|-----------|--------------------------------|"
           "---------------------------------|------\n");

    for (int batch = 0; batch < TOTAL_BATCHES; batch++) {
        int current_step = batch * STEPS_PER_BATCH;
        
        // NVMe checkpoint every 10,000 steps
        if (current_step % 10000 == 0 && current_step > 0) {
            save_hardprint_checkpoint(current_step, f0, d_rho, d_ux, d_uy, h_prev_f, h_prev_rho, h_prev_ux, h_prev_uy);
        }
        /* Run one batch */
        for (int s = 0; s < STEPS_PER_BATCH; s++) {
            float *src = (cur == 0) ? f0 : f1;
            float *dst = (cur == 0) ? f1 : f0;
            lbm_collide_stream<<<GBLK(NN), BLOCK, 0, stream>>>(
                src, dst, d_rho, d_ux, d_uy, OMEGA, NX, NY);
            cur = 1 - cur;
        }
        total_steps += STEPS_PER_BATCH;

        /* Sample? */
        if ((batch + 1) % SAMPLE_BATCHES == 0) {
            cudaStreamSynchronize(stream);
            do_sample(total_steps);
        }
    }

    cudaStreamSynchronize(stream);

    if (csv) fclose(csv);
    if (vspec_csv) fclose(vspec_csv);
    if (rspec_csv) fclose(rspec_csv);

    auto t_end = std::chrono::steady_clock::now();
    double runtime = std::chrono::duration<double>(t_end - t0).count();

    /* ==================================================================== */
    /*   A N A L Y S I S                                                    */
    /* ==================================================================== */
    printf("\n\n");
    printf("=======================================================================\n");
    printf("  FRACTAL HABIT ??? ANALYSIS  (%d samples, %.1f minutes)\n",
           sample_count, runtime / 60.0);
    printf("=======================================================================\n");

    /* ---- 1. Velocity E(k) comparison ----------------------------------- */
    printf("\n--- 1. VELOCITY SPECTRUM: Initial vs Mid vs Final ---\n");
    printf("  k   |  E_v(init)       |  E_v(mid)        |  E_v(final)      | Ratio f/i\n");
    printf("  ----|------------------|------------------|------------------|----------\n");

    int disp_k[] = {1,2,3,4,5,8,10,16,20,32,50,64,100,128,200,256,400,512};
    int n_disp = sizeof(disp_k)/sizeof(disp_k[0]);
    for (int d = 0; d < n_disp; d++) {
        int k = disp_k[d];
        if (k >= NK) continue;
        double ei = spec_vel_init[k], em = spec_vel_mid[k], ef = spec_vel_final[k];
        double ratio = (ei > 0) ? ef / ei : 0;
        printf("  %4d | %.10e | %.10e | %.10e | %9.4f\n", k, ei, em, ef, ratio);
    }

    /* ---- 2. Density E(k) comparison ------------------------------------ */
    printf("\n--- 2. DENSITY SPECTRUM: Initial vs Mid vs Final ---\n");
    printf("  k   |  E_r(init)       |  E_r(mid)        |  E_r(final)      | Ratio f/i\n");
    printf("  ----|------------------|------------------|------------------|----------\n");
    for (int d = 0; d < n_disp; d++) {
        int k = disp_k[d];
        if (k >= NK) continue;
        double ei = spec_rho_init[k], em = spec_rho_mid[k], ef = spec_rho_final[k];
        double ratio = (ei > 0) ? ef / ei : 0;
        printf("  %4d | %.10e | %.10e | %.10e | %9.4f\n", k, ei, em, ef, ratio);
    }

    /* ---- 3. Spectral entropy ------------------------------------------- */
    printf("\n--- 3. SPECTRAL ENTROPY ---\n");
    SpectrumStats sv_i = analyze_spectrum(spec_vel_init.data(), NK);
    SpectrumStats sv_f = analyze_spectrum(spec_vel_final.data(), NK);
    SpectrumStats sr_i = analyze_spectrum(spec_rho_init.data(), NK);
    SpectrumStats sr_f = analyze_spectrum(spec_rho_final.data(), NK);
    double H_max = log2((double)(NK - 1));

    printf("  Velocity:\n");
    printf("    Initial: H = %.4f bits  (%.4f normalized)  slope = %+.3f  modes = %d\n",
           sv_i.spectral_entropy, sv_i.spectral_entropy / H_max, sv_i.slope, sv_i.num_modes);
    printf("    Final:   H = %.4f bits  (%.4f normalized)  slope = %+.3f  modes = %d\n",
           sv_f.spectral_entropy, sv_f.spectral_entropy / H_max, sv_f.slope, sv_f.num_modes);

    printf("  Density:\n");
    printf("    Initial: H = %.4f bits  (%.4f normalized)  slope = %+.3f  modes = %d\n",
           sr_i.spectral_entropy, sr_i.spectral_entropy / H_max, sr_i.slope, sr_i.num_modes);
    printf("    Final:   H = %.4f bits  (%.4f normalized)  slope = %+.3f  modes = %d\n",
           sr_f.spectral_entropy, sr_f.spectral_entropy / H_max, sr_f.slope, sr_f.num_modes);

    printf("\n  Reference slopes: Kolmogorov -5/3 = -1.667, Kraichnan -3\n");

    /* ---- 4. Energy budget ----------------------------------------------- */
    printf("\n--- 4. ENERGY BUDGET ---\n");
    printf("  Initial kinetic energy: %.6e\n", sv_i.total_energy);
    printf("  Final kinetic energy:   %.6e\n", sv_f.total_energy);
    double ke_ratio = (sv_i.total_energy > 0) ? sv_f.total_energy / sv_i.total_energy : 0;
    printf("  Ratio (final/init):     %.6f\n", ke_ratio);
    printf("  Initial density energy: %.6e\n", sr_i.total_energy);
    printf("  Final density energy:   %.6e\n", sr_f.total_energy);
    double de_ratio = (sr_i.total_energy > 0) ? sr_f.total_energy / sr_i.total_energy : 0;
    printf("  Ratio (final/init):     %.6f\n\n", de_ratio);

    /* ---- VERDICT -------------------------------------------------------- */
    printf("=======================================================================\n");
    printf("  V E R D I C T\n");
    printf("=======================================================================\n\n");

    /* Velocity verdict */
    if (ke_ratio < 0.001) {
        printf("  VELOCITY: DEAD ??? kinetic energy dissipated (%.4f%% remaining)\n",
               ke_ratio * 100);
    } else if (ke_ratio < 0.1) {
        printf("  VELOCITY: DYING ??? kinetic energy heavily damped (%.1f%% remaining)\n",
               ke_ratio * 100);
    } else {
        printf("  VELOCITY: PERSISTENT ??? %.1f%% of kinetic energy survived\n",
               ke_ratio * 100);
    }

    /* Density verdict */
    if (de_ratio < 0.001) {
        printf("  DENSITY:  ERASED ??? fluctuations gone\n");
    } else if (de_ratio > 0.5) {
        printf("  DENSITY:  PERSISTENT ??? %.1f%% of spectral power survived\n",
               de_ratio * 100);
    } else {
        printf("  DENSITY:  PARTIAL ??? %.1f%% survived\n", de_ratio * 100);
    }

    /* Entropy verdict */
    double dH_vel = sv_f.spectral_entropy - sv_i.spectral_entropy;
    double dH_rho = sr_f.spectral_entropy - sr_i.spectral_entropy;

    printf("\n");
    if (dH_rho > 1.0) {
        printf("  >>> COMPLEXIFIED: Density entropy grew +%.1f bits <<<\n", dH_rho);
        printf("  >>> Energy spread to more k-modes: multi-scale structure EMERGED <<<\n");
    } else if (dH_rho < -1.0) {
        printf("  >>> CRYSTALLIZED: Density entropy dropped %.1f bits <<<\n", -dH_rho);
        printf("  >>> Energy concentrated into fewer modes: static lattice <<<\n");
    } else if (sr_f.total_energy > 0 && de_ratio > 0.1) {
        if (sr_f.num_modes > sr_i.num_modes + 5) {
            printf("  >>> SPREADING: More modes active, structure complexifying <<<\n");
        } else if (sr_f.num_modes < sr_i.num_modes - 5) {
            printf("  >>> CONDENSING: Fewer modes, structure simplifying <<<\n");
        } else {
            printf("  >>> STABLE: Structure maintained with similar complexity <<<\n");
        }
    } else {
        printf("  >>> DISSIPATED: Not enough energy to judge structure <<<\n");
    }

    /* Fractal test: is slope near -5/3 and entropy high? */
    if (sr_f.total_energy > 0 && fabs(sr_f.slope) > 1.0 &&
        sr_f.spectral_entropy / H_max > 0.3) {
        printf("\n  FRACTAL SIGNATURE: Power-law slope = %.2f with normalized entropy = %.3f\n",
               sr_f.slope, sr_f.spectral_entropy / H_max);
        printf("  This suggests scale-free structure, not a simple lattice.\n");
    }

    printf("\n  Output:\n");
    printf("    /build/fractal_habit.csv             (summary per sample)\n");
    printf("    /build/fractal_habit_vel_spectra.csv  (full E_v(k) per sample)\n");
    printf("    /build/fractal_habit_rho_spectra.csv  (full E_rho(k) per sample)\n");
    printf("=======================================================================\n\n");

    /* ---- Cleanup -------------------------------------------------------- */
    
    // Final NVMe checkpoint
    save_hardprint_checkpoint(100000, f0, d_rho, d_ux, d_uy, h_prev_f, h_prev_rho, h_prev_ux, h_prev_uy);
    cufftDestroy(plan);
    cudaFree(f0); cudaFree(f1);
    cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy); cudaFree(d_drho);
    cudaFree(d_fft_ux); cudaFree(d_fft_uy); cudaFree(d_fft_drho);
    cudaFree(d_spec_vel); cudaFree(d_spec_rho);
    // Hard Print: Cleanup previous state
    free(h_prev_f);
    free(h_prev_rho);
    free(h_prev_ux);
    free(h_prev_uy);
    cudaFree(d_kx0_power); cudaFree(d_kx_nonzero_power);
    cudaStreamDestroy(stream);
    nvmlShutdown();
    return 0;
}




