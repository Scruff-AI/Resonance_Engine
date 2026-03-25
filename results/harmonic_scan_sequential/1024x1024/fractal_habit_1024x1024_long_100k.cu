/* ============================================================================
 * LONG TEST - 100k steps with metabolic kick
 * Monitor entropy evolution, create crystals for crash recovery
 * ============================================================================ */

#include <cuda_runtime.h>
#include <cufft.h>
#include <nvml.h>
#include <curand_kernel.h>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cmath>
#include <chrono>
#include <vector>
#include <cstring>

/* ---- Grid ---------------------------------------------------------------- */
#define NX    1024
#define NY    1024
#define NN    (NX * NY)
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

/* ---- Protocol ------------------------------------------------------------ */
#define TOTAL_STEPS      100000  // LONG TEST: 100k steps
#define STEPS_PER_BATCH  500
#define SAMPLE_INTERVAL  10000   // Sample every 10k steps
#define TOTAL_BATCHES    (TOTAL_STEPS / STEPS_PER_BATCH)
#define SAMPLE_BATCHES   (SAMPLE_INTERVAL / STEPS_PER_BATCH)
#define NUM_SAMPLES      (TOTAL_STEPS / SAMPLE_INTERVAL)

/* ---- Metabolic Kick Parameters ------------------------------------------ */
#define OMEGA  1.85f
#define NOISE_AMPLITUDE 0.05f
#define NOISE_INTERVAL 50

/* ---- Spectrum ----------------------------------------------------------- */
#define NX2   (NX / 2 + 1)
#define KMAX  (NX / 2)
#define NK    (KMAX + 1)

/* ---- Crystallization Header -------------------------------------------- */
typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t grid_x;
    uint32_t grid_y;
    uint32_t q;
    uint32_t step;
    float omega;
    float viscosity;
    float entropy;
    float slope;
    float kx0_fraction;
    float total_energy;
    uint32_t peak_k;
    uint32_t thermal_state;
    uint64_t timestamp;
    uint64_t checksum_data;
    uint64_t checksum_header;
    char hostname[64];
    char user[32];
    char annotation[128];
    uint32_t reserved[8];
} CrystallizationHeader;

#define CRYSTAL_MAGIC 0x43525953
#define CRYSTAL_VERSION 0x01000002  // v1.0.2 for long test

/* ---- D2Q9 --------------------------------------------------------------- */
__constant__ int   d_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
__constant__ int   d_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
__constant__ float d_w[Q]  = { 4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9,
                               1.f/36,1.f/36,1.f/36,1.f/36 };
static const int h_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
static const int h_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };

/* ---- Metabolic Kick Kernel --------------------------------------------- */
__global__ void inject_noise(float* f, int nx, int ny, float amplitude, unsigned int seed, int step) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N = nx * ny;
    if (idx >= N) return;
    
    curandState state;
    curand_init(seed + idx + step * 10000, 0, 0, &state);
    
    for (int i = 0; i < Q; i++) {
        float noise = amplitude * (curand_uniform(&state) - 0.5f);
        f[i * N + idx] += noise;
    }
}

/* ---- Helper Functions --------------------------------------------------- */
uint64_t calculate_checksum(const void* data, size_t size) {
    const uint32_t* words = (const uint32_t*)data;
    size_t num_words = size / sizeof(uint32_t);
    uint64_t sum1 = 0, sum2 = 0;
    for (size_t i = 0; i < num_words; i++) {
        sum1 = (sum1 + words[i]) % 0xFFFFFFFF;
        sum2 = (sum2 + sum1) % 0xFFFFFFFF;
    }
    return (sum2 << 32) | sum1;
}

uint32_t get_gpu_temperature() {
    nvmlReturn_t result;
    nvmlDevice_t device;
    unsigned int temp = 0;
    result = nvmlInit();
    if (result != NVML_SUCCESS) return 0;
    result = nvmlDeviceGetHandleByIndex(0, &device);
    if (result != NVML_SUCCESS) { nvmlShutdown(); return 0; }
    result = nvmlDeviceGetTemperature(device, NVML_TEMPERATURE_GPU, &temp);
    nvmlShutdown();
    if (result != NVML_SUCCESS) return 0;
    return temp * 100;
}

/* ---- Crystallization Function ------------------------------------------ */
void crystallize_state(int step, float* d_f, float* d_rho, float* d_ux, float* d_uy,
                       double entropy, double slope, double kx0_frac, 
                       double total_energy, uint32_t peak_k, int noise_injections) {
    char filename[256];
    sprintf(filename, "C:\\fractal_nvme_test\\long_100k\\crystal_%08d.crys", step);
    
    printf("[Crystal] Step %d: %.3f bits, slope %.2f, k=%d, noise=%d\n", 
           step, entropy, slope, peak_k, noise_injections);
    system("mkdir C:\\fractal_nvme_test\\long_100k 2>nul");
    
    FILE* fp = fopen(filename, "wb");
    if (!fp) { printf("[Crystal] ERROR: Cannot open file\n"); return; }
    
    size_t f_size = Q * NN * sizeof(float);
    size_t field_size = NN * sizeof(float);
    
    float* h_f = (float*)malloc(f_size);
    float* h_rho = (float*)malloc(field_size);
    float* h_ux = (float*)malloc(field_size);
    float* h_uy = (float*)malloc(field_size);
    
    if (!h_f || !h_rho || !h_ux || !h_uy) {
        printf("[Crystal] ERROR: Memory allocation failed\n");
        if (h_f) free(h_f); if (h_rho) free(h_rho);
        if (h_ux) free(h_ux); if (h_uy) free(h_uy);
        fclose(fp); return;
    }
    
    cudaMemcpy(h_f, d_f, f_size, cudaMemcpyDeviceToHost);
    cudaMemcpy(h_rho, d_rho, field_size, cudaMemcpyDeviceToHost);
    cudaMemcpy(h_ux, d_ux, field_size, cudaMemcpyDeviceToHost);
    cudaMemcpy(h_uy, d_uy, field_size, cudaMemcpyDeviceToHost);
    
    CrystallizationHeader header;
    memset(&header, 0, sizeof(header));
    
    header.magic = CRYSTAL_MAGIC;
    header.version = CRYSTAL_VERSION;
    header.grid_x = NX;
    header.grid_y = NY;
    header.q = Q;
    header.step = step;
    header.omega = OMEGA;
    header.viscosity = (1.0f/OMEGA - 0.5f)/3.0f;
    header.entropy = (float)entropy;
    header.slope = (float)slope;
    header.kx0_fraction = (float)kx0_frac;
    header.total_energy = (float)total_energy;
    header.peak_k = peak_k;
    header.thermal_state = get_gpu_temperature();
    header.timestamp = (uint64_t)time(NULL) * 1000;
    
    strncpy(header.hostname, "Beast-Windows", 63);
    strncpy(header.user, "Administrator", 31);
    
    char annotation[128];
    if (entropy > 6.0) {
        sprintf(annotation, "HIGH-ENTROPY: %.2f bits, slope %.2f, k=%d, noise=%d", 
                entropy, slope, peak_k, noise_injections);
    } else if (entropy > 4.0) {
        sprintf(annotation, "MODERATE: %.2f bits, noise=%d", entropy, noise_injections);
    } else {
        sprintf(annotation, "LOW: %.2f bits, noise=%d", entropy, noise_injections);
    }
    strncpy(header.annotation, annotation, 127);
    
    size_t data_size = f_size + 3 * field_size;
    uint8_t* data_buffer = (uint8_t*)malloc(data_size);
    if (data_buffer) {
        memcpy(data_buffer, h_f, f_size);
        memcpy(data_buffer + f_size, h_rho, field_size);
        memcpy(data_buffer + f_size + field_size, h_ux, field_size);
        memcpy(data_buffer + f_size + 2 * field_size, h_uy, field_size);
        header.checksum_data = calculate_checksum(data_buffer, data_size);
        free(data_buffer);
    }
    
    header.checksum_header = calculate_checksum(&header, sizeof(header) - 16);
    
    fwrite(&header, sizeof(header), 1, fp);
    fwrite(h_f, f_size, 1, fp);
    fwrite(h_rho, field_size, 1, fp);
    fwrite(h_ux, field_size, 1, fp);
    fwrite(h_uy, field_size, 1, fp);
    
    fclose(fp);
    free(h_f); free(h_rho); free(h_ux); free(h_uy);
}

/* ---- Kernels ----------------------------------------------------------- */
__global__ void lbm_collide_stream(const float* __restrict__ f_src, float* __restrict__ f_dst,
    float* __restrict__ rho_out, float* __restrict__ ux_out,
    float* __restrict__ uy_out, float omega, int nx, int ny) {
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

__global__ void compute_radial_spectrum(const cufftComplex* __restrict__ fft_a,
    const cufftComplex* __restrict__ fft_b, double* __restrict__ spectrum,
    int nx, int ny, int nk, int two_field) {
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
    if (kx_idx > 0 && kx_idx < nx/2) power *= 2.0;
    atomicAdd(&spectrum[k], power);
}

__global__ void compute_kx0_fraction(const cufftComplex* __restrict__ fft_field,
    double* __restrict__ power_kx0, double* __restrict__ power_kx_nonzero,
    int nx, int ny) {
    int nx2 = nx / 2 + 1;
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= ny * nx2) return;
    int kx_idx = idx % nx2;
    int ky_idx = idx / nx2;
    if (kx_idx == 0 && ky_idx == 0) return;
    float r = fft_field[idx].x, im = fft_field[idx].y;
    double p = (double)(r*r + im*im);
    if (kx_idx > 0 && kx_idx < nx/2) p *= 2.0;
    if (kx_idx == 0) atomicAdd(power_kx0, p);
    else atomicAdd(power_kx_nonzero, p);
}

/* ---- Spectrum Analysis -------------------------------------------------- */
struct SpectrumStats {
    double total_energy;
    double spectral_entropy;
    double peak_k;
    double slope;
    int num_modes;
    double kx0_frac;
};

SpectrumStats analyze_spectrum(const double* spec, int nk) {
    SpectrumStats s;
    s.total_energy = 0;
    double peak_p = 0;
    s.peak_k = 0;
    for (int k = 1; k < nk; k++) {
        s.total_energy += spec[k];
        if (spec[k] > peak_p) { peak_p = spec[k]; s.peak_k = k; }
    }
    s.spectral_entropy = 0;
    s.num_modes = 0;
    if (s.total_energy > 0) {
        for (int k = 1; k < nk; k++) {
            double p = spec[k] / s.total_energy;
            if (p > 0) s.spectral_entropy -= p * log2(p);
            if (p > 0.01) s.num_modes++;
        }
    }
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

/* ---- Load State --------------------------------------------------------- */
static float* load_f_state(const char* path) {
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

/* ---- Main --------------------------------------------------------------- */
int main() {
    double nu = (1.0 / OMEGA - 0.5) / 3.0;
    double t_diff = (double)NX * NX / (4.0 * M_PI * M_PI * nu);
    
    /* Spectral tracking */
    double current_entropy = 0.0;
    double current_slope = 0.0;
    double current_kx0_frac = 0.0;
    double current_total_energy = 0.0;
    uint32_t current_peak_k = 0;
    int spectral_available = 0;
    int noise_injections = 0;

    printf("\n");
    printf("=======================================================================\n");
    printf("  LONG TEST - 100k steps with metabolic kick\n");
    printf("  Grid: %dx%d | Omega: %.2f | Noise: %.3f every %d steps\n", 
           NX, NY, OMEGA, NOISE_AMPLITUDE, NOISE_INTERVAL);
    printf("  Crystals: Every 10k steps for crash recovery testing\n");
    printf("=======================================================================\n\n");

    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    printf("[CUDA] %s\n", prop.name);

    nvmlInit();
    nvmlDevice_t nvml_dev;
    nvmlDeviceGetHandleByIndex(0, &nvml_dev);

    printf("[LOAD] Loading Hysteresis C80...\n");
    float* h_f = load_f_state("build/f_state_post_relax.bin");
    if (!h_f) return 1;

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
        h_drho[idx] = rho;
    }
    float rho_mean = (float)(rho_sum / NN);
    for (int idx = 0; idx < NN; idx++) h_drho[idx] -= rho_mean;

    size_t fbuf = (size_t)Q * NN * sizeof(float);
    float *f0, *f1, *d_rho, *d_ux, *d_uy, *d_drho;
    cudaMalloc(&f0, fbuf); cudaMalloc(&f1, fbuf);
    cudaMalloc(&d_rho, NN * sizeof(float));
    cudaMalloc(&d_ux, NN * sizeof(float));
    cudaMalloc(&d_uy, NN * sizeof(float));
    cudaMalloc(&d_drho, NN * sizeof(float));

    cudaMemcpy(f0, h_f, fbuf, cudaMemcpyHostToDevice);
    cudaMemcpy(f1, h_f, fbuf, cudaMemcpyHostToDevice);
    free(h_f);
    cudaMemcpy(d_ux, h_ux, NN * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_uy, h_uy, NN * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_drho, h_drho, NN * sizeof(float), cudaMemcpyHostToDevice);
    free(h_ux); free(h_uy); free(h_drho);

    cufftHandle plan;
    cufftPlan2d(&plan, NY, NX, CUFFT_R2C);

    cufftComplex *d_fft_ux, *d_fft_uy, *d_fft_drho;
    cudaMalloc(&d_fft_ux, NY * NX2 * sizeof(cufftComplex));
    cudaMalloc(&d_fft_uy, NY * NX2 * sizeof(cufftComplex));
    cudaMalloc(&d_fft_drho, NY * NX2 * sizeof(cufftComplex));

    double *d_spec_vel, *d_spec_rho;
    double *d_kx0_power, *d_kx_nonzero_power;
    cudaMalloc(&d_spec_vel, NK * sizeof(double));
    cudaMalloc(&d_spec_rho, NK * sizeof(double));
    cudaMalloc(&d_kx0_power, sizeof(double));
    cudaMalloc(&d_kx_nonzero_power, sizeof(double));

    double h_spec_vel[NK], h_spec_rho[NK];

    cudaStream_t stream;
    cudaStreamCreate(&stream);

    std::vector<double> spec_vel_init(NK, 0), spec_vel_final(NK, 0);
    std::vector<double> spec_rho_init(NK, 0), spec_rho_final(NK, 0);

    int sample_count = 0;
    double norm = 1.0 / ((double)NN * (double)NN);
    int fft_n = NY * NX2;

    auto do_sample = [&](uint64_t step) {
        cufftExecR2C(plan, d_ux, d_fft_ux);
        cufftExecR2C(plan, d_uy, d_fft_uy);

        if (step > 0) {
            float* h_rho_tmp = (float*)malloc(NN * sizeof(float));
            cudaMemcpy(h_rho_tmp, d_rho, NN * sizeof(float), cudaMemcpyDeviceToHost);
            double rs = 0;
            for (int i = 0; i < NN; i++) rs += h_rho_tmp[i];
            float rm = (float)(rs / NN);
            for (int i = 0; i < NN; i++) h_rho_tmp[i] -= rm;
            cudaMemcpy(d_drho, h_rho_tmp, NN * sizeof(float), cudaMemcpyHostToDevice);
            free(h_rho_tmp);
        }

        cufftExecR2C(plan, d_drho, d_fft_drho);
        cudaDeviceSynchronize();

        cudaMemset(d_spec_vel, 0, NK * sizeof(double));
        compute_radial_spectrum<<<GBLK(fft_n), BLOCK>>>(
            d_fft_ux, d_fft_uy, d_spec_vel, NX, NY, NK, 1);
        cudaDeviceSynchronize();
        cudaMemcpy(h_spec_vel, d_spec_vel, NK * sizeof(double), cudaMemcpyDeviceToHost);
        for (int k = 0; k < NK; k++) h_spec_vel[k] *= norm;

        cudaMemset(d_spec_rho, 0, NK * sizeof(double));
        compute_radial_spectrum<<<GBLK(fft_n), BLOCK>>>(
            d_fft_drho, NULL, d_spec_rho, NX, NY, NK, 0);
        cudaDeviceSynchronize();
        cudaMemcpy(h_spec_rho, d_spec_rho, NK * sizeof(double), cudaMemcpyDeviceToHost);
        for (int k = 0; k < NK; k++) h_spec_rho[k] *= norm;

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

        SpectrumStats sv = analyze_spectrum(h_spec_vel, NK);
        SpectrumStats sr = analyze_spectrum(h_spec_rho, NK);
        sr.kx0_frac = kx0_frac;
        
        current_entropy = sr.spectral_entropy;
        current_slope = sr.slope;
        current_kx0_frac = sr.kx0_frac;
        current_total_energy = sr.total_energy;
        current_peak_k = (uint32_t)sr.peak_k;
        spectral_available = 1;

        unsigned int mW = 0;
        nvmlDeviceGetPowerUsage(nvml_dev, &mW);

        printf("  %3d | %9llu | Ev=%.3e H=%.2f | Er=%.3e H=%.2f sl=%+.2f kx0=%.1f%% | %5.1fW | Noise:%d\n",
               sample_count, (unsigned long long)step,
               sv.total_energy, sv.spectral_entropy,
               sr.total_energy, sr.spectral_entropy, sr.slope,
               kx0_frac * 100.0, (float)mW / 1000.f, noise_injections);

        if (sample_count == 0) {
            for (int k = 0; k < NK; k++) {
                spec_vel_init[k] = h_spec_vel[k];
                spec_rho_init[k] = h_spec_rho[k];
            }
        }
        for (int k = 0; k < NK; k++) {
            spec_vel_final[k] = h_spec_vel[k];
            spec_rho_final[k] = h_spec_rho[k];
        }

        sample_count++;
    };

    printf("[INIT] Computing step-0 spectrum...\n");
    do_sample(0);

    int cur = 0;
    uint64_t total_steps = 0;
    auto t0 = std::chrono::steady_clock::now();

    printf("\n[RUN] %d steps with metabolic kick\n", TOTAL_STEPS);
    printf("  sam |     step  | Velocity         | Density                       | Power | Noise\n");
    printf("  ----|-----------|------------------|-------------------------------|-------|------\n");

    for (int batch = 0; batch < TOTAL_BATCHES; batch++) {
        int current_step = batch * STEPS_PER_BATCH;
        
        /* Inject noise periodically */
        if (current_step % NOISE_INTERVAL == 0 && current_step > 0) {
            float* target = (cur == 0) ? f0 : f1;
            inject_noise<<<GBLK(NN), BLOCK>>>(target, NX, NY, NOISE_AMPLITUDE, 12345, current_step);
            cudaDeviceSynchronize();
            noise_injections++;
        }
        
        /* Crystallize every 10k steps (for crash recovery testing) */
        if (current_step % 10000 == 0 && current_step > 0 && spectral_available) {
            crystallize_state(current_step, f0, d_rho, d_ux, d_uy,
                            current_entropy, current_slope, current_kx0_frac,
                            current_total_energy, current_peak_k, noise_injections);
        }
        
        for (int s = 0; s < STEPS_PER_BATCH; s++) {
            float *src = (cur == 0) ? f0 : f1;
            float *dst = (cur == 0) ? f1 : f0;
            lbm_collide_stream<<<GBLK(NN), BLOCK, 0, stream>>>(
                src, dst, d_rho, d_ux, d_uy, OMEGA, NX, NY);
            cur = 1 - cur;
        }
        total_steps += STEPS_PER_BATCH;

        if ((batch + 1) % SAMPLE_BATCHES == 0) {
            cudaStreamSynchronize(stream);
            do_sample(total_steps);
        }
    }

    cudaStreamSynchronize(stream);
    auto t_end = std::chrono::steady_clock::now();
    double runtime = std::chrono::duration<double>(t_end - t0).count();

    /* Final crystallization */
    if (spectral_available) {
        crystallize_state(TOTAL_STEPS, f0, d_rho, d_ux, d_uy,
                        current_entropy, current_slope, current_kx0_frac,
                        current_total_energy, current_peak_k, noise_injections);
    }

    /* Final analysis */
    printf("\n\n");
    printf("=======================================================================\n");
    printf("  LONG TEST COMPLETE - %.1f seconds\n", runtime);
    printf("=======================================================================\n\n");

    SpectrumStats sv_f = analyze_spectrum(spec_vel_final.data(), NK);
    SpectrumStats sr_f = analyze_spectrum(spec_rho_final.data(), NK);
    double H_max = log2((double)(NK - 1));

    printf("  Velocity Spectrum:\n");
    printf("    - Total energy: %.6e\n", sv_f.total_energy);
    printf("    - Entropy: %.4f bits (%.4f normalized)\n", sv_f.spectral_entropy, sv_f.spectral_entropy / H_max);
    printf("    - Slope: %.3f\n", sv_f.slope);
    printf("    - Peak k: %.0f\n", sv_f.peak_k);
    printf("    - Active modes: %d\n", sv_f.num_modes);
    
    printf("\n  Density Spectrum:\n");
    printf("    - Total energy: %.6e\n", sr_f.total_energy);
    printf("    - Entropy: %.4f bits (%.4f normalized)\n", sr_f.spectral_entropy, sr_f.spectral_entropy / H_max);
    printf("    - Slope: %.3f\n", sr_f.slope);
    printf("    - Peak k: %.0f\n", sr_f.peak_k);
    printf("    - kx=0 fraction: %.2f%%\n", sr_f.kx0_frac * 100);
    printf("    - Active modes: %d\n", sr_f.num_modes);
    
    printf("\n  Metabolic Kick Statistics:\n");
    printf("    - Noise injections: %d\n", noise_injections);
    printf("    - Total steps: %d\n", TOTAL_STEPS);
    printf("    - Runtime: %.1f seconds (%.0f steps/sec)\n", runtime, TOTAL_STEPS / runtime);
    
    printf("\n  Crystallization Status:\n");
    printf("    - Crystal files: C:\\fractal_nvme_test\\long_100k\\crystal_*.crys\n");
    printf("    - Version: 0x%08X (long test)\n", CRYSTAL_VERSION);
    printf("    - Files for crash recovery: steps 10000, 20000, ..., 100000\n");
    
    if (sr_f.spectral_entropy > 6.0) {
        printf("\n  >>> HIGH-ENTROPY STATE ACHIEVED (%.2f bits) <<<\n", sr_f.spectral_entropy);
        printf("  >>> MATCHES THE-CRAW (6.75 bits) <<<\n");
    } else if (sr_f.spectral_entropy > 5.0) {
        printf("\n  >>> MODERATE ENTROPY STATE (%.2f bits) <<<\n", sr_f.spectral_entropy);
        printf("  >>> Close to the-craw, may need more noise <<<\n");
    } else {
        printf("\n  >>> LOW ENTROPY STATE (%.2f bits) <<<\n", sr_f.spectral_entropy);
        printf("  >>> Need parameter tuning <<<\n");
    }

    printf("\n=======================================================================\n");
    printf("  READY FOR CRASH RECOVERY TESTING\n");
    printf("  Crystal files available at: C:\\fractal_nvme_test\\long_100k\\\n");
    printf("=======================================================================\n\n");

    cufftDestroy(plan);
    cudaFree(f0); cudaFree(f1);
    cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy); cudaFree(d_drho);
    cudaFree(d_fft_ux); cudaFree(d_fft_uy); cudaFree(d_fft_drho);
    cudaFree(d_spec_vel); cudaFree(d_spec_rho);
    cudaFree(d_kx0_power); cudaFree(d_kx_nonzero_power);
    cudaStreamDestroy(stream);
    nvmlShutdown();
    return 0;
}
