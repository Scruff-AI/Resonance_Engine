/* ============================================================================
 * FRACTAL HABIT 1024×1024 - CRYSTALLIZED VERSION
 * 
 * Adapted from the-craw's successful crystallization approach:
 * 1. Unified state with metadata header
 * 2. Entropy and thermal tracking
 * 3. Checksum verification
 * 4. Human-readable annotation
 * 
 * Based on: fractal_habit_1024x1024_nvme_proper.cu
 *           fractal_crystallize_v031.cu (the-craw)
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

/* ---- Crystallization Structures (from the-craw) ------------------------- */
typedef struct {
    uint32_t magic;          // 0x43525953 ("CRYS")
    uint32_t version;        // 0x01000000 (v1.0.0)
    uint32_t grid_x;
    uint32_t grid_y;
    uint32_t q;
    uint32_t step;
    float omega;
    float viscosity;
    float entropy;          // Spectral entropy (bits)
    float slope;            // Power-law slope
    float kx0_fraction;     // Fraction of energy in kx=0
    float total_energy;
    uint32_t peak_k;
    uint32_t thermal_state; // GPU temperature × 100
    uint64_t timestamp;     // Unix timestamp in milliseconds
    uint64_t checksum_data;
    uint64_t checksum_header;
    char hostname[64];
    char user[32];
    char annotation[128];   // Human-readable annotation
    uint32_t reserved[8];   // Future use
} CrystallizationHeader;

#define CRYSTAL_MAGIC 0x43525953  // "CRYS" in hex
#define CRYSTAL_VERSION 0x01000000  // v1.0.0

/* ---- Crystallization Functions ------------------------------------------ */

// Calculate Fletcher-64 checksum
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

// Get GPU temperature (returns temperature × 100)
uint32_t get_gpu_temperature() {
    nvmlReturn_t result;
    nvmlDevice_t device;
    unsigned int temp = 0;
    
    result = nvmlInit();
    if (result != NVML_SUCCESS) return 0;
    
    result = nvmlDeviceGetHandleByIndex(0, &device);
    if (result != NVML_SUCCESS) {
        nvmlShutdown();
        return 0;
    }
    
    result = nvmlDeviceGetTemperature(device, NVML_TEMPERATURE_GPU, &temp);
    nvmlShutdown();
    
    if (result != NVML_SUCCESS) return 0;
    return temp * 100;  // Store as integer × 100
}

/* ---- Crystallized Checkpoint Function ----------------------------------- */
void save_crystallized_checkpoint(int step, float* d_f, float* d_rho, 
                                  float* d_ux, float* d_uy,
                                  double entropy, double slope, 
                                  double kx0_frac, double total_energy,
                                  uint32_t peak_k) {
    char filename[256];
    sprintf(filename, "C:\\fractal_nvme_test\\crystal_%08d.crys", step);
    
    printf("[Crystal] Saving crystallized state at step %d to %s\n", step, filename);
    
    // Create directory if it doesn't exist
    system("mkdir C:\\fractal_nvme_test 2>nul");
    
    FILE* fp = fopen(filename, "wb");
    if (!fp) {
        printf("[Crystal] ERROR: Cannot open file for writing\n");
        return;
    }
    
    // Calculate sizes
    size_t f_size = Q * NN * sizeof(float);
    size_t field_size = NN * sizeof(float);
    
    // Allocate host memory
    float* h_f = (float*)malloc(f_size);
    float* h_rho = (float*)malloc(field_size);
    float* h_ux = (float*)malloc(field_size);
    float* h_uy = (float*)malloc(field_size);
    
    if (!h_f || !h_rho || !h_ux || !h_uy) {
        printf("[Crystal] ERROR: Memory allocation failed\n");
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
    
    // Prepare header
    CrystallizationHeader header;
    memset(&header, 0, sizeof(header));
    
    header.magic = CRYSTAL_MAGIC;
    header.version = CRYSTAL_VERSION;
    header.grid_x = NX;
    header.grid_y = NY;
    header.q = Q;
    header.step = step;
    header.omega = 1.85f;  // From original code
    header.viscosity = (1.0f/1.85f - 0.5f)/3.0f;
    header.entropy = (float)entropy;
    header.slope = (float)slope;
    header.kx0_fraction = (float)kx0_frac;
    header.total_energy = (float)total_energy;
    header.peak_k = peak_k;
    header.thermal_state = get_gpu_temperature();
    header.timestamp = (uint64_t)time(NULL) * 1000;  // Milliseconds
    
    // Get hostname and username (Windows)
    char hostname[64] = "Beast-Windows";
    char username[32] = "Administrator";
    strncpy(header.hostname, hostname, 63);
    strncpy(header.user, username, 31);
    
    // Create annotation
    char annotation[128];
    if (entropy > 6.0) {
        sprintf(annotation, "HIGH-ENTROPY STATE: %.2f bits, slope %.2f, k=%d dominant", 
                entropy, slope, peak_k);
    } else if (entropy > 4.0) {
        sprintf(annotation, "MODERATE ENTROPY: %.2f bits, developing structure", entropy);
    } else {
        sprintf(annotation, "LOW ENTROPY: %.2f bits, initial state", entropy);
    }
    strncpy(header.annotation, annotation, 127);
    
    // Calculate checksums
    size_t data_size = f_size + 3 * field_size;
    uint8_t* data_buffer = (uint8_t*)malloc(data_size);
    if (data_buffer) {
        // Concatenate all data for checksum
        memcpy(data_buffer, h_f, f_size);
        memcpy(data_buffer + f_size, h_rho, field_size);
        memcpy(data_buffer + f_size + field_size, h_ux, field_size);
        memcpy(data_buffer + f_size + 2 * field_size, h_uy, field_size);
        
        header.checksum_data = calculate_checksum(data_buffer, data_size);
        free(data_buffer);
    }
    
    // Calculate header checksum (excluding checksum fields)
    header.checksum_header = calculate_checksum(&header, 
        sizeof(header) - 16);  // Exclude checksum_data and checksum_header
    
    // Write header
    fwrite(&header, sizeof(header), 1, fp);
    
    // Write data
    fwrite(h_f, f_size, 1, fp);
    fwrite(h_rho, field_size, 1, fp);
    fwrite(h_ux, field_size, 1, fp);
    fwrite(h_uy, field_size, 1, fp);
    
    fclose(fp);
    
    // Free memory
    free(h_f);
    free(h_rho);
    free(h_ux);
    free(h_uy);
    
    // Print summary
    printf("[Crystal] Crystallization complete:\n");
    printf("  - Size: %.2f MB\n", (sizeof(header) + data_size) / (1024.0f * 1024.0f));
    printf("  - Entropy: %.3f bits\n", entropy);
    printf("  - Slope: %.2f\n", slope);
    printf("  - Peak k: %d\n", peak_k);
    printf("  - kx=0: %.2f%%\n", kx0_frac * 100);
    printf("  - Thermal: %.2f°C\n", header.thermal_state / 100.0f);
    printf("  - Annotation: %s\n", annotation);
}

/* ---- Original LBM Kernels (unchanged) ----------------------------------- */
__constant__ int d_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
__constant__ int d_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
__constant__ float d_w[Q] = { 4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9,
                               1.f/36,1.f/36,1.f/36,1.f/36 };

__global__ void lbm_step(const float* f_src, float* f_dst,
    float* rho_out, float* ux_out, float* uy_out, float omega, int nx, int ny) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N = nx * ny;
    if (idx >= N) return;
    const int x = idx % nx, y = idx / nx;

    float fl[Q];
    for (int i = 0; i < Q; i++) {
        int sx = (x - d_ex[i] + nx) % nx;
        int sy = (y - d_ey[i] + ny) % ny;
        fl[i] = f_src[i * N + sy * nx + sx];
    }

    float rho = 0.f, ux = 0.f, uy = 0.f;
    for (int i = 0; i < Q; i++) {
        rho += fl[i];
        ux += (float)d_ex[i] * fl[i];
        uy += (float)d_ey[i] * fl[i];
    }
    float inv = 1.f / fmaxf(rho, 1e-10f);
    ux *= inv; uy *= inv;
    rho_out[idx] = rho; ux_out[idx] = ux; uy_out[idx] = uy;

    const float u2 = ux * ux + uy * uy;
    for (int i = 0; i < Q; i++) {
        float eu = (float)d_ex[i] * ux + (float)d_ey[i] * uy;
        float feq = d_w[i] * rho * (1.f + 3.f*eu + 4.5f*eu*eu - 1.5f*u2);
        f_dst[i * N + idx] = fl[i] - omega * (fl[i] - feq);
    }
}

/* ---- Spectral Analysis Functions (from original) ------------------------ */
// Note: These functions should be copied from the original
// fractal_habit_1024x1024_nvme_proper.cu
// For brevity, placeholder comments are used

__global__ void compute_spectrum(const cufftComplex* d_fft_ux,
                                 const cufftComplex* d_fft_uy,
                                 double* d_spec, int nx, int ny, int nk) {
    // Original spectral computation kernel
    // Should be copied from original file
}

__global__ void compute_kx0_fraction(const cufftComplex* d_fft_rho,
                                     double* d_kx0, double* d_kx_nz,
                                     int nx, int ny) {
    // Original kx=0 fraction computation
    // Should be copied from original file
}

double calc_entropy(const double* spec, int nk) {
    // Original entropy calculation
    // Should be copied from original file
    return 0.0;
}

double calc_slope(const double* spec, int nk) {
    // Original slope calculation
    // Should be copied from original file
    return 0.0;
}

/* ---- Main Function (modified for crystallization) ----------------------- */
int main() {
    // Original initialization code from fractal_habit_1024x1024_nvme_proper.cu
    // Should be copied here
    
    // Key modifications needed:
    // 1. Track entropy, slope, kx0_frac, total_energy, peak_k
    // 2. Call save_crystallized_checkpoint() instead of save_nvme_checkpoint()
    // 3. Pass spectral analysis results to crystallization function
    
    printf("FRACTAL HABIT 1024×1024 - CRYSTALLIZED VERSION\n");
    printf("Adapted from the-craw's successful approach\n");
    printf("Grid: %d×%d (%d cells)\n", NX, NY, NN);
    printf("Target: High-entropy crystallization with metadata\n");
    printf("===============================================================\n");
    
    // Placeholder - actual main() implementation should be copied
    // from the original file and modified as described above
    
    return 0;
}