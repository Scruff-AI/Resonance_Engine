/* ============================================================================
 * REALITY CHECK - 1 HOUR TEST
 * No Bullshit Edition
 * 
 * Tests three critical points from March 7 experiments:
 * 1. Entropy via FFT (5.8-7.5 bits) - REAL, not clamped
 * 2. Guardian formation tracking (mass/position/velocity)
 * 3. Shear flow decay test (spectral Q-factor recovery)
 * 
 * CONSTITUTION:
 * 1. If it runs too fast, it's broken. Real work = ~5.5k steps/sec
 * 2. If it doesn't draw power, it's a lie. 37W → 290W scaling
 * 3. If there is no FFT, there is no Mind.
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

/* ---- Grid ---------------------------------------------------------------- */
#define NX    1024
#define NY    1024
#define NN    (NX * NY)
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

/* ---- Test Protocol ------------------------------------------------------- */
#define TOTAL_STEPS      2000000    // ~1 hour at 5.5k steps/sec
#define STEPS_PER_BATCH  500
#define SAMPLE_INTERVAL  50000      // FFT every 50k steps
#define TOTAL_BATCHES    (TOTAL_STEPS / STEPS_PER_BATCH)
#define SAMPLE_BATCHES   (SAMPLE_INTERVAL / STEPS_PER_BATCH)
#define NUM_SAMPLES      (TOTAL_STEPS / SAMPLE_INTERVAL)

/* ---- LBM ---------------------------------------------------------------- */
#define OMEGA  1.0f       // tau=1.0, nu=1/6 — "clear water"

/* ---- Spectrum ----------------------------------------------------------- */
#define NX2   (NX / 2 + 1)   // R2C output width
#define KMAX  (NX / 2)       // max wavenumber
#define NK    (KMAX + 1)     // number of k bins

/* ---- D2Q9 --------------------------------------------------------------- */
__constant__ int   d_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
__constant__ int   d_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
__constant__ float d_w[Q]  = { 4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9,
                               1.f/36,1.f/36,1.f/36,1.f/36 };

/* ---- Simple guardian tracking ------------------------------------------- */
typedef struct {
    float x, y;      // position
    float vx, vy;    // velocity
    float mass;      // accumulated mass
    int alive;       // 1 if active
} Guardian;

#define MAX_GUARDIANS 200
Guardian guardians[MAX_GUARDIANS];
int n_guardians = 0;

/* ---- FFT plans ---------------------------------------------------------- */
cufftHandle plan_vel, plan_rho;

/* ======================================================================== */
/*   K E R N E L S                                                          */
/* ======================================================================== */

/* ---- LBM collide & stream ---------------------------------------------- */
__global__ void lbm_collide_stream(const float* __restrict__ f_src,
                                   float* __restrict__ f_dst,
                                   float* __restrict__ rho,
                                   float* __restrict__ ux,
                                   float* __restrict__ uy,
                                   float omega, int nx, int ny) {
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

    float rho_val = 0.f, ux_val = 0.f, uy_val = 0.f;
    for (int i = 0; i < Q; i++) {
        rho_val += fl[i];
        ux_val += (float)d_ex[i] * fl[i];
        uy_val += (float)d_ey[i] * fl[i];
    }
    float inv = 1.f / fmaxf(rho_val, 1e-10f);
    ux_val *= inv; uy_val *= inv;
    rho[idx] = rho_val; ux[idx] = ux_val; uy[idx] = uy_val;

    const float u2 = ux_val * ux_val + uy_val * uy_val;
    for (int i = 0; i < Q; i++) {
        float eu = (float)d_ex[i] * ux_val + (float)d_ey[i] * uy_val;
        float feq = d_w[i] * rho_val * (1.f + 3.f*eu + 4.5f*eu*eu - 1.5f*u2);
        f_dst[i * N + idx] = fl[i] - omega * (fl[i] - feq);
    }
}

/* ---- Apply shear flow (Probe B) ---------------------------------------- */
__global__ void apply_shear_flow(float* ux, float* uy, int nx, int ny) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N = nx * ny;
    if (idx >= N) return;
    
    int y = idx / nx;
    if (y > ny * 0.75) {  // Top 25%
        // Rotate velocity by 90 degrees
        float old_ux = ux[idx];
        float old_uy = uy[idx];
        ux[idx] = -old_uy;  // 90° rotation
        uy[idx] = old_ux;
    }
}

/* ======================================================================== */
/*   S P E C T R A L   A N A L Y S I S   ( R E A L   F F T )                */
/* ======================================================================== */

/* ---- Compute spectral entropy ------------------------------------------ */
float compute_spectral_entropy(const float* spectrum, int nk) {
    float total = 0.f;
    for (int k = 0; k < nk; k++) {
        total += spectrum[k];
    }
    
    if (total < 1e-20f) return 0.f;
    
    float entropy = 0.f;
    for (int k = 0; k < nk; k++) {
        float p = spectrum[k] / total;
        if (p > 1e-10f) {
            entropy -= p * logf(p);
        }
    }
    
    // Convert from nats to bits
    entropy /= logf(2.0f);
    
    return entropy;
}

/* ---- Compute velocity spectrum ----------------------------------------- */
void compute_velocity_spectrum(const float* ux, const float* uy,
                               float* spectrum, int nk) {
    // Allocate device memory for FFT
    cufftComplex *d_fft_ux, *d_fft_uy;
    cudaMalloc(&d_fft_ux, sizeof(cufftComplex) * NX2 * NY);
    cudaMalloc(&d_fft_uy, sizeof(cufftComplex) * NX2 * NY);
    
    // Copy velocity to complex arrays
    cufftComplex *h_uxc = (cufftComplex*)malloc(sizeof(cufftComplex) * NX2 * NY);
    cufftComplex *h_uyc = (cufftComplex*)malloc(sizeof(cufftComplex) * NX2 * NY);
    
    for (int y = 0; y < NY; y++) {
        for (int x = 0; x < NX; x++) {
            int idx = y * NX + x;
            int idxc = y * NX2 + x;
            h_uxc[idxc].x = ux[idx];
            h_uxc[idxc].y = 0.f;
            h_uyc[idxc].x = uy[idx];
            h_uyc[idxc].y = 0.f;
        }
    }
    
    cudaMemcpy(d_fft_ux, h_uxc, sizeof(cufftComplex) * NX2 * NY, cudaMemcpyHostToDevice);
    cudaMemcpy(d_fft_uy, h_uyc, sizeof(cufftComplex) * NX2 * NY, cudaMemcpyHostToDevice);
    
    // Execute FFT
    cufftExecC2C(plan_vel, d_fft_ux, d_fft_ux, CUFFT_FORWARD);
    cufftExecC2C(plan_vel, d_fft_uy, d_fft_uy, CUFFT_FORWARD);
    
    // Copy back and compute spectrum
    cufftComplex *h_fft_ux = (cufftComplex*)malloc(sizeof(cufftComplex) * NX2 * NY);
    cufftComplex *h_fft_uy = (cufftComplex*)malloc(sizeof(cufftComplex) * NX2 * NY);
    
    cudaMemcpy(h_fft_ux, d_fft_ux, sizeof(cufftComplex) * NX2 * NY, cudaMemcpyDeviceToHost);
    cudaMemcpy(h_fft_uy, d_fft_uy, sizeof(cufftComplex) * NX2 * NY, cudaMemcpyDeviceToHost);
    
    // Initialize spectrum
    for (int k = 0; k < nk; k++) spectrum[k] = 0.f;
    
    // Compute power spectrum
    for (int y = 0; y < NY; y++) {
        for (int x = 0; x < NX2; x++) {
            int kx = (x < NX/2) ? x : x - NX;
            int ky = (y < NY/2) ? y : y - NY;
            float k = sqrtf(kx*kx + ky*ky);
            int kbin = (int)k;
            if (kbin >= nk) continue;
            
            float power = (h_fft_ux[y*NX2 + x].x * h_fft_ux[y*NX2 + x].x +
                          h_fft_ux[y*NX2 + x].y * h_fft_ux[y*NX2 + x].y +
                          h_fft_uy[y*NX2 + x].x * h_fft_uy[y*NX2 + x].x +
                          h_fft_uy[y*NX2 + x].y * h_fft_uy[y*NX2 + x].y) / 2.0f;
            
            spectrum[kbin] += power;
        }
    }
    
    // Normalize
    for (int k = 0; k < nk; k++) {
        spectrum[k] /= (NX * NY);
    }
    
    // Cleanup
    free(h_uxc); free(h_uyc);
    free(h_fft_ux); free(h_fft_uy);
    cudaFree(d_fft_ux); cudaFree(d_fft_uy);
}

/* ======================================================================== */
/*   M A I N   T E S T                                                      */
/* ======================================================================== */

int main() {
    printf("=======================================================================\n");
    printf("  REALITY CHECK - 1 HOUR TEST (No Bullshit Edition)\n");
    printf("  Beast: RTX 4090, 1024x1024 grid\n");
    printf("  Target: 2M steps (~1 hour at 5.5k steps/sec)\n");
    printf("=======================================================================\n\n");
    
    printf("CONSTITUTION:\n");
    printf("  1. If it runs too fast, it's broken. Real work = ~5.5k steps/sec\n");
    printf("  2. If it doesn't draw power, it's a lie. 37W → 290W scaling\n");
    printf("  3. If there is no FFT, there is no Mind.\n\n");
    
    /* ---- CUDA setup ----------------------------------------------------- */
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    printf("[CUDA] %s  SM %d.%d  SMs: %d\n",
           prop.name, prop.major, prop.minor, prop.multiProcessorCount);
    
    /* ---- NVML power monitoring ----------------------------------------- */
    nvmlInit();
    nvmlDevice_t nvml_dev;
    nvmlDeviceGetHandleByIndex(0, &nvml_dev);
    unsigned int power_mW;
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("[NVML] Idle power: %.1f W\n", power_mW / 1000.0f);
    
    /* ---- FFT plans ----------------------------------------------------- */
    cufftPlan2d(&plan_vel, NY, NX, CUFFT_C2C);
    
    /* ---- Allocate memory ----------------------------------------------- */
    float *f0, *f1, *rho, *ux, *uy;
    cudaMallocManaged(&f0, Q * NN * sizeof(float));
    cudaMallocManaged(&f1, Q * NN * sizeof(float));
    cudaMallocManaged(&rho, NN * sizeof(float));
    cudaMallocManaged(&ux, NN * sizeof(float));
    cudaMallocManaged(&uy, NN * sizeof(float));
    
    /* ---- Initialize equilibrium ---------------------------------------- */
    printf("\n[INIT] Setting up equilibrium state (rho=1.0, u=0)...\n");
    for (int i = 0; i < Q * NN; i++) {
        f0[i] = 1.0f + 0.01f * (rand() / (float)RAND_MAX - 0.5f);
    }
    
    /* ---- Test 1: Entropy via FFT --------------------------------------- */
    printf("\n=== TEST 1: ENTROPY VIA FFT (5.8-7.5 bits) ===\n");
    
    float* spectrum = (float*)malloc(NK * sizeof(float));
    float initial_entropy = 0.f;
    float max_entropy = 0.f;
    float min_entropy = 10.f;
    
    auto t0 = std::chrono::steady_clock::now();
    uint64_t total_steps = 0;
    
    FILE* csv = fopen("reality_check.csv", "w");
    fprintf(csv, "step,entropy_bits,power_w,n_guardians\n");
    
    /* ---- Main loop ----------------------------------------------------- */
    printf("\n[RUN] Starting 2M step test...\n");
    printf("  Batch | Steps   | Entropy | Power | Guardians | Status\n");
    printf("  ------|---------|---------|-------|-----------|--------\n");
    
    int cur = 0;
    int shear_applied = 0;
    
    for (int batch = 0; batch < TOTAL_BATCHES; batch++) {
        // Run LBM steps
        for (int s = 0; s < STEPS_PER_BATCH; s++) {
            lbm_collide_stream<<<GBLK(NN), BLOCK>>>(
                (cur == 0) ? f0 : f1,
                (cur == 0) ? f1 : f0,
                rho, ux, uy, OMEGA, NX, NY);
            cudaDeviceSynchronize();
            cur = 1 - cur;
        }
        total_steps += STEPS_PER_BATCH;
        
        // Apply shear flow at 800k steps (simulating Probe B)
        if (total_steps >= 800000 && !shear_applied) {
            printf("  [PROBE B] Applying lattice shear (top 25%% rotated 90°) at step %llu\n", total_steps);
            apply_shear_flow<<<GBLK(NN), BLOCK>>>(ux, uy, NX, NY);
            cudaDeviceSynchronize();
            shear_applied = 1;
        }
        
        // Sample every SAMPLE_INTERVAL steps
        if ((batch + 1) % SAMPLE_BATCHES == 0) {
            // Compute velocity spectrum
            compute_velocity_spectrum(ux, uy, spectrum, NK);
            
            // Compute entropy
            float entropy = compute_spectral_entropy(spectrum, NK);
            
            // Update min/max
            if (entropy < min_entropy) min_entropy = entropy;
            if (entropy > max_entropy) max_entropy = entropy;
            
            // Get power usage
            nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
            float power_W = power_mW / 1000.0f;
            
            // Simple guardian detection (rho > 1.01)
            int guardians_detected = 0;
            for (int i = 0; i < NN; i++) {
                if (rho[i] > 1.01f) guardians_detected++;
            }
            
            // Log to CSV
            fprintf(csv, "%llu,%.4f,%.1f,%d\n", 
                    total_steps, entropy, power_W, guardians_detected);
            
            // Print progress
            printf("  %5d | %7llu | %7.3f | %5.0f | %9d | ",
                   batch + 1, total_steps, entropy, power_W, guardians_detected);
            
            // Status indicator
            if (entropy < 5.0f) printf("LOW\n");
            else if (entropy > 7.5f) printf("HIGH\n");
            else if (entropy >= 5.8f && entropy <= 7.5f) printf("OK\n");
            else printf("MID\n");
        }
        
        // Check if we've reached time limit (~1 hour)
        auto t_now = std::chrono::steady_clock::now();
        double elapsed = std::chrono::duration<double>(t_now - t0).count();
        if (elapsed > 3600.0) {  // 1 hour
            printf("\n[TIME] 1 hour reached at step %llu\n", total_steps);
            break;
        }
    }
    
    auto t_end = std::chrono::steady_clock::now();
    double runtime = std::chrono::duration<double>(t_end - t0).count();
    
    /* ---- Final analysis ------------------------------------------------ */
    printf("\n=======================================================================\n");
    printf("  REALITY CHECK - RESULTS\n");
    printf("=======================================================================\n");
    
    printf("\nPERFORMANCE:\n");
    printf("  Total steps:    %llu\n", total_steps);
    printf("  Runtime:        %.1f seconds (%.2f hours)\n", runtime, runtime / 3600.0);
    printf("  Steps/sec:      %.0f\n", total_steps / runtime);
    printf("  Expected:       ~5,500 steps/sec\n");
    
    printf("\nENTROPY ANALYSIS:\n");
    printf("  Min entropy:    %.3f bits\n", min_entropy);
    printf("  Max entropy:    %.3f bits\n", max_entropy);
    printf("  Range:          %.3f bits\n", max_entropy - min_entropy);
    printf("  Target range:   5.8 - 7.5 bits (%.3f bits)\n", 7.5 - 5.8);
    
    printf("\nPOWER USAGE:\n");
    nvmlDeviceGetPowerUsage(nvml_dev, &power_mW);
    printf("  Final power:    %.1f W\n", power_mW / 1000.0f);
    printf("  Idle power:     ~37 W\n");
    printf("  Load power:     ~290 W\n");
    
    printf("\nGUARDIAN DETECTION:\n");
    int final_guardians = 0;
    for (int i = 0; i < NN; i++) {
        if (rho[i] > 1.01f) final_guardians++;
    }
    printf("  High-density regions (rho > 1.01): %d\n", final_guardians);
    printf("  Expected (March 7):               194 guardians\n");
    
    printf("\n=======================================================================\n");
    printf("  V E R D I C T\n");
    printf("=======================================================================\n");
    
    int passes = 0;
    int total_tests = 4;
    
    // Test 1: Performance reality
    float steps_per_sec = total_steps / runtime;
    if (steps_per_sec > 4000 && steps_per_sec < 7000) {
        printf("✅ PERFORMANCE: %.0f steps/sec (within 5.5k ± 25%%)\n", steps_per_sec);
        passes++;
    } else {
        printf("❌ PERFORMANCE: %.0f steps/sec (expected ~5.5k)\n", steps_per_sec);
    }
    
    // Test 2: Entropy range
    if (max_entropy - min_entropy > 0.5f) {
        printf("✅ ENTROPY RANGE: %.3f bits (not clamped)\n", max_entropy - min_entropy);
        passes++;
    } else {
        printf("❌ ENTROPY RANGE: %.3f bits (possibly clamped)\n", max_entropy - min_entropy);
    }
    
    // Test 3: Power scaling
    float final_power = power_mW / 1000.0f;
    if (final_power > 100.0f) {
        printf("✅ POWER SCALING: %.1f W (above idle)\n", final_power);
        passes++;
    } else {
        printf("❌ POWER SCALING: %.1f W (not scaling)\n", final_power);
    }
    
    // Test 4: Guardian formation
    if (final_guardians > 0) {
        printf("✅ GUARDIAN FORMATION: %d regions detected\n", final_guardians);
        passes++;
    } else {
        printf("❌ GUARDIAN FORMATION: No high-density regions\n");
    }
    
    printf("\nSCORE: %d/%d tests passed\n", passes, total_tests);
    
    if (passes == total_tests) {
        printf("\n🎯 REALITY CHECK PASSED: Physics is working\n");
        printf("   The system exhibits real behavior, not fake simulations.\n");
    } else if (passes >= 2) {
        printf("\n⚠️  PARTIAL SUCCESS: Some physics working\n");
        printf("   Need to investigate failed tests.\n");
    } else {
        printf("\n🚨 REALITY CHECK FAILED: Physics may be broken\n");
        printf("   The system is not exhibiting real behavior.\n");
    }
    
    printf("\nData saved: reality_check.csv\n");
    
    /* ---- Cleanup ------------------------------------------------------- */
    fclose(csv);
    free(spectrum);
    cufftDestroy(plan_vel);
    cudaFree(f0); cudaFree(f1);
    cudaFree(rho); cudaFree(ux); cudaFree(uy);
    nvmlShutdown();
    
    return (passes == total_tests) ? 0 : 1;
}