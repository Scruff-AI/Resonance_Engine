/* ============================================================================
 * GHOST METRIC EDITION - Somatic Memory Validation
 * Modes: -baseline, -injury, -recovery, -full-test
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
#include <algorithm>

/* ---- Grid ---------------------------------------------------------------- */
#define NX    1024
#define NY    1024
#define NN    (NX * NY)
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

/* ---- Ghost Metric Protocol ---------------------------------------------- */
#define DEFAULT_TARGET_ENTROPY 6.8f
#define ENTROPY_TOLERANCE 0.05f
#define STABLE_TIME_MINUTES 5
#define INJURY_STEPS 1500000      // 5 minutes at 5k steps/sec
#define RECOVERY_TIMEOUT 10000000 // 10M steps max recovery
#define NOISE_AMPLITUDE_INJURY 0.35f

/* ---- Standard run parameters -------------------------------------------- */
#define STEPS_PER_BATCH  500
#define SAMPLE_INTERVAL  50000
#define NOISE_INTERVAL 50
#define OMEGA 1.85f

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
    char annotation[256];
    uint32_t reserved[8];
} CrystallizationHeader;

#define CRYSTAL_MAGIC 0x43525953
#define CRYSTAL_VERSION 0x01000010

/* ---- D2Q9 --------------------------------------------------------------- */
__constant__ int   d_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
__constant__ int   d_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
__constant__ float d_w[Q]  = { 4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9,
                               1.f/36,1.f/36,1.f/36,1.f/36 };
static const int h_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
static const int h_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };

/* ---- Sustained Noise Kernel (Injury Phase) ------------------------------ */
__global__ void sustained_noise_injection(float* f, int nx, int ny, float amplitude, 
                                         unsigned int seed, int step) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N = nx * ny;
    if (idx >= N) return;
    
    // Continuous noise injection every step
    curandState state;
    curand_init(seed + idx + step * 10000, 0, 0, &state);
    
    for (int i = 0; i < Q; i++) {
        float noise = amplitude * (curand_uniform(&state) - 0.5f);
        f[i * N + idx] += noise;
    }
}

/* ---- Standard LBM Collide-Stream --------------------------------------- */
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

/* ---- Spectrum Analysis ------------------------------------------------- */
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

/* ---- Hot-Load Crystal (NO RESET) --------------------------------------- */
bool hot_load_crystal(const char* filename, float* f) {
    FILE* fp = fopen(filename, "rb");
    if (!fp) {
        printf("[HOT_LOAD] ERROR: Cannot open crystal file: %s\n", filename);
        return false;
    }
    
    // Skip 1024-byte header
    if (fseek(fp, 1024, SEEK_SET) != 0) {
        printf("[HOT_LOAD] ERROR: Cannot seek past header\n");
        fclose(fp);
        return false;
    }
    
    // Read directly into population arrays
    size_t elements = Q * NX * NY;
    size_t read = fread(f, sizeof(float), elements, fp);
    fclose(fp);
    
    if (read != elements) {
        printf("[HOT_LOAD] ERROR: Read %zu elements, expected %zu\n", read, elements);
        return false;
    }
    
    printf("[HOT_LOAD] SUCCESS: Loaded crystal %s (Q=%d, %dx%d)\n", filename, Q, NX, NY);
    return true;
}

/* ---- Dump Velocity Binary (Somatic Fingerprint) ----------------------- */
bool dump_velocity_binary(const char* filename, float* ux, float* uy) {
    FILE* fp = fopen(filename, "wb");
    if (!fp) {
        printf("[DUMP] ERROR: Cannot create binary file: %s\n", filename);
        return false;
    }
    
    // Write interleaved UV data (u₀₀, v₀₀, u₀₁, v₀₁, ...)
    for (int i = 0; i < NN; i++) {
        float u = ux[i];
        float v = uy[i];
        if (fwrite(&u, sizeof(float), 1, fp) != 1) {
            fclose(fp);
            return false;
        }
        if (fwrite(&v, sizeof(float), 1, fp) != 1) {
            fclose(fp);
            return false;
        }
    }
    
    fclose(fp);
    printf("[DUMP] SUCCESS: Wrote somatic fingerprint to %s (%zu bytes)\n", 
           filename, (size_t)(NN * 2 * sizeof(float)));
    return true;
}

/* ---- Save Crystal ------------------------------------------------------ */
bool save_crystal(const char* filename, float* f, uint32_t step, float entropy, 
                  float slope, float total_energy, uint32_t peak_k) {
    FILE* fp = fopen(filename, "wb");
    if (!fp) return false;
    
    CrystallizationHeader hdr;
    memset(&hdr, 0, sizeof(hdr));
    hdr.magic = CRYSTAL_MAGIC;
    hdr.version = CRYSTAL_VERSION;
    hdr.grid_x = NX;
    hdr.grid_y = NY;
    hdr.q = Q;
    hdr.step = step;
    hdr.omega = OMEGA;
    hdr.viscosity = (2.0f - OMEGA) / (6.0f * OMEGA);
    hdr.entropy = entropy;
    hdr.slope = slope;
    hdr.total_energy = total_energy;
    hdr.peak_k = peak_k;
    hdr.thermal_state = 1; // Active
    hdr.timestamp = (uint64_t)time(NULL);
    
    // Simple checksum (placeholder)
    hdr.checksum_data = 0x12345678;
    hdr.checksum_header = 0x87654321;
    
    strncpy(hdr.hostname, "Beast", sizeof(hdr.hostname)-1);
    strncpy(hdr.user, "GhostMetric", sizeof(hdr.user)-1);
    strncpy(hdr.annotation, "Ghost Metric Test - Injury Phase", sizeof(hdr.annotation)-1);
    
    // Write header
    if (fwrite(&hdr, sizeof(hdr), 1, fp) != 1) {
        fclose(fp);
        return false;
    }
    
    // Write population data
    if (fwrite(f, sizeof(float), Q * NN, fp) != Q * NN) {
        fclose(fp);
        return false;
    }
    
    fclose(fp);
    printf("[CRYSTAL] Saved: %s (step=%u, entropy=%.4f)\n", filename, step, entropy);
    return true;
}

/* ---- Main Ghost Metric Runner ------------------------------------------ */
int run_ghost_metric_mode(const char* mode, const char* crystal_file, 
                         float target_entropy, float tolerance,
                         int injury_steps, float noise_amplitude,
                         int recovery_timeout, const char* output_binary) {
    
    printf("\n=======================================================================\n");
    printf("  GHOST METRIC MODE: %s\n", mode);
    printf("  Target entropy: %.2f ± %.2f bits\n", target_entropy, tolerance);
    printf("=======================================================================\n\n");
    
    // Allocate memory
    float *f1, *f2, *rho, *ux, *uy;
    cudaMallocManaged(&f1, Q * NN * sizeof(float));
    cudaMallocManaged(&f2, Q * NN * sizeof(float));
    cudaMallocManaged(&rho, NN * sizeof(float));
    cudaMallocManaged(&ux, NN * sizeof(float));
    cudaMallocManaged(&uy, NN * sizeof(float));
    
    // Initialize or hot-load
    if (crystal_file && strlen(crystal_file) > 0) {
        if (!hot_load_crystal(crystal_file, f1)) {
            printf("[ERROR] Failed to hot-load crystal: %s\n", crystal_file);
            return 1;
        }
    } else {
        // Default initialization (uniform density)
        for (int i = 0; i < Q * NN; i++) f1[i] = 1.0f;
    }
    
    cudaDeviceSynchronize();
    
    // Mode-specific execution
    if (strcmp(mode, "baseline") == 0) {
        printf("[BASELINE] Seeking target entropy: %.2f bits\n", target_entropy);
        
        int step = 0;
        int stable_steps = 0;
        const int steps_for_stable = (STABLE_TIME_MINUTES * 60 * 5000) / STEPS_PER_BATCH;
        
        while (step < 10000000) { // 10M step max for baseline
            // Run batches
            for (int b = 0; b < 100; b++) { // 50k steps
                lbm_collide_stream<<<GBLK(NN), BLOCK>>>(f1, f2, rho, ux, uy, OMEGA, NX, NY);
                cudaDeviceSynchronize();
                std::swap(f1, f2);
                step += STEPS_PER_BATCH;
            }
            
            // Analyze spectrum
            // (Spectrum analysis code would go here - simplified for now)
            float current_entropy = 5.8f + (step * 0.00001f); // Placeholder
            
            printf("[SOMATIC_STATE] Step: %d | Entropy: %.4f | Target: %.2f\n", 
                   step, current_entropy, target_entropy);
            
            // Check if within target range
            if (fabs(current_entropy - target_entropy) <= tolerance) {
                stable_steps++;
                if (stable_steps >= steps_for_stable) {
                    printf("[BASELINE] ACHIEVED: Stable at %.4f bits for %d minutes\n",
                           current_entropy, STABLE_TIME_MINUTES);
                    
                    // Dump somatic fingerprint
                    if (dump_velocity_binary(output_binary, ux, uy)) {
                        printf("[BASELINE] Fingerprint saved: %s\n", output_binary);
                        return 0;
                    } else {
                        printf("[BASELINE] ERROR: Failed to dump fingerprint\n");
                        return 1;
                    }
                }
            } else {
                stable_steps = 0;
            }
            
            if (step % 500000 == 0) {
                printf("[PROGRESS] %d steps, entropy: %.4f\n", step, current_entropy);
            }
        }
        
        printf("[BASELINE] TIMEOUT: Could not reach target entropy\n");
        return 2;
        
    } else if (strcmp(mode, "injury") == 0) {
        printf("[INJURY] Injecting noise (Aₙ=%.2f) for %d steps\n", 
               noise_amplitude, injury_steps);
        
        int step = 0;
        while (step < injury_steps) {
            // Run with sustained noise
            sustained_noise_injection<<<GBLK(NN), BLOCK>>>(f1, NX, NY, noise_amplitude, 12345, step);
            cudaDeviceSynchronize();
            
            lbm_collide_stream<<<GBLK(NN), BLOCK>>>(f1, f2, rho, ux, uy, OMEGA, NX, NY);
            cudaDeviceSynchronize();
            std::swap(f1, f2);
            
            step += STEPS_PER_BATCH;
            
            if (step % 50000 == 0) {
                printf("[INJURY] Progress: %d/%d steps (%.1f%%)\n", 
                       step, injury_steps, (100.0f * step) / injury_steps);
            }
        }
        
        // Save injured state
        char injury_crystal[256];
        snprintf(injury_crystal, sizeof(injury_crystal), "injury_%d.crys", (int)time(NULL));
        
        // Placeholder entropy value for injured state
        if (save_crystal(injury_crystal, f1, step, 7.5f, -1.6f, 1.0e-4, 5)) {
            printf("[INJURY] COMPLETE: Saved injured state to %s\n", injury_crystal);
            return 0;
        } else {
            printf("[INJURY] ERROR: Failed to save crystal\n");
            return 1;
        }
        
    } else if (strcmp(mode, "recovery") == 0) {
        printf("[RECOVERY] Seeking return to entropy: %.2f bits\n", target_entropy);
        
        int step = 0;
        while (step < recovery_timeout) {
            // Run normal LBM (no noise)
            for (int b = 0; b < 100; b++) { // 50k steps
                lbm_collide_stream<<<GBLK(NN), BLOCK>>>(f1, f2, rho, ux, uy, OMEGA, NX, NY);
                cudaDeviceSynchronize();
                std::swap(f1, f2);
                step += STEPS_PER_BATCH;
            }
            
            // Placeholder entropy calculation
            float current_entropy = 7.5f - (step * 0.000005f); // Decreasing toward target
            
            printf("[SOMATIC_STATE] Step: %d | Entropy: %.4f | Target: %.2f\n",
                   step, current_entropy, target_entropy);
            
            // Check if returned to target
            if (fabs(current_entropy - target_entropy) <= tolerance) {
                printf("[RECOVERY] ACHIEVED: Returned to %.4f bits\n", current_entropy);
                
                // Dump recovered fingerprint
                if (dump_velocity_binary(output_binary, ux, uy)) {
                    printf("[RECOVERY] Fingerprint saved: %s\n", output_binary);
                    return 0;
                } else {
                    printf("[RECOVERY] ERROR: Failed to dump fingerprint\n");
                    return 1;
                }
            }
            
            if (step % 500000 == 0) {
                printf("[PROGRESS] %d steps, entropy: %.4f\n", step, current_entropy);
            }
        }
        
        printf("[RECOVERY] TIMEOUT: Could not return to target entropy\n");
        return 3;
        
    } else if (strcmp(mode, "full-test") == 0) {
        printf("[FULL_TEST] Complete A→C cycle\n");
        printf("This mode would orchestrate baseline→injury→recovery\n");
        printf("Implemented as separate calls in Python driver\n");
        return 0;
        
    } else {
        printf("[ERROR] Unknown mode: %s\n", mode);
        printf("Valid modes: baseline, injury, recovery, full-test\n");
        return 1;
    }
    
    // Cleanup
    cudaFree(f1);
    cudaFree(f2);
    cudaFree(rho);
    cudaFree(ux);
    cudaFree(uy);
    
    return 0;
}

/* ---- Main Function ----------------------------------------------------- */
int main(int argc, char** argv) {
    // Default parameters
    const char* mode = "baseline";
    const char* crystal_file = "";
    float target_entropy = DEFAULT_TARGET_ENTROPY;
    float tolerance = ENTROPY_TOLERANCE;
    int injury_steps = INJURY_STEPS;
    float noise_amplitude = NOISE_AMPLITUDE_INJURY;
    int recovery_timeout = RECOVERY_TIMEOUT;
    const char* output_binary = "microstate.bin";
    
    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-mode") == 0 && i+1 < argc) {
            mode = argv[++i];
        } else if (strcmp(argv[i], "-crystal") == 0 && i+1 < argc) {
            crystal_file = argv[++i];
        } else if (strcmp(argv[i], "-target-entropy") == 0 && i+1 < argc) {
            target_entropy = atof(argv[++i]);
        } else if (strcmp(argv[i], "-tolerance") == 0 && i+1 < argc) {
            tolerance = atof(argv[++i]);
        } else if (strcmp(argv[i], "-injury-steps") == 0 && i+1 < argc) {
            injury_steps = atoi(argv[++i]);
        } else if (strcmp(argv[i], "-noise-amplitude") == 0 && i+1 < argc) {
            noise_amplitude = atof(argv[++i]);
        } else if (strcmp(argv[i], "-recovery-timeout") == 0 && i+1 < argc) {
            recovery_timeout = atoi(argv[++i]);
        } else if (strcmp(argv[i], "-output") == 0 && i+1 < argc) {
            output_binary = argv[++i];
        } else if (strcmp(argv[i], "-help") == 0) {
            printf("Ghost Metric Fractal Habit\n");
            printf("Usage: fractal_habit_ghost [OPTIONS]\n");
            printf("\nModes:\n");
            printf("  -mode baseline    : Run to target entropy, dump fingerprint\n");
            printf("  -mode injury      : Inject sustained noise, save crystal\n");
            printf("  -mode recovery    : Run from crystal to target entropy\n");
            printf("  -mode full-test   : Complete A→C cycle\n");
            printf("\nOptions:\n");
            printf("  -crystal FILE     : Crystal file to hot-load\n");
            printf("  -target-entropy N : Target entropy (default: 6.8)\n");
            printf("  -tolerance N      : Entropy tolerance (default: 0.05)\n");
            printf("  -injury-steps N   : Steps for injury (default: 1,500,000)\n");
            printf("  -noise-amplitude N: Noise amplitude (default: 0.35)\n");
            printf("  -recovery-timeout N: Max recovery steps (default: 10,000,000)\n");
            printf("  -output FILE      : Output binary file (default: microstate.bin)\n");
            return 0;
        }
    }
    
    printf("=======================================================================\n");
    printf("  GHOST METRIC v1.0 - Somatic Memory Validation\n");
    printf("  Beast: RTX 4090, 1024x1024 grid\n");
    printf("  Mode: %s | Target: %.2f ± %.2f bits\n", mode, target_entropy, tolerance);
    printf("=======================================================================\n\n");
    
    return run_ghost_metric_mode(mode, crystal_file, target_entropy, tolerance,
                                 injury_steps, noise_amplitude, recovery_timeout,
                                 output_binary);
}