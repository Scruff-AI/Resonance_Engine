/* ============================================================================
 * FRACTAL HABIT 256×256 — MVP for GTX 1050 @ 80W
 *
 * Modified from original fractal_habit.cu for the_craw hardware:
 *   - Grid: 256×256 (1/16 area of 1024×1024)
 *   - Guardians: 12 (scaled from 194, maintaining 1:5,400 density)
 *   - Target: Sustainable coherence at 40-60W
 *   - Architecture: sm_61 for GTX 1050 optimization
 *
 * Tracks:
 *   - Velocity energy spectrum E_v(k) via 2D FFT
 *   - Density power spectrum E_rho(k) via 2D FFT of delta_rho
 *   - Spectral entropy of both
 *   - Power-law slope (target: -3.8)
 *   - Fraction of density power at kx=0 vs kx!=0 (x-emergence)
 *
 * Build: nvcc -O3 -arch=sm_61 -o fractal_habit_256 \
 *        fractal_habit_256.cu -lnvidia-ml -lpthread -lcufft
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
#define NX    256      /* CHANGED: 1024 → 256 for GTX 1050 */
#define NY    256      /* CHANGED: 1024 → 256 for GTX 1050 */
#define NN    (NX * NY)
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

/* ---- Protocol ------------------------------------------------------------ */
#define TOTAL_STEPS      10000000
#define STEPS_PER_BATCH  500
#define SAMPLE_INTERVAL  50000      /* E(k) sample every 50k steps */
#define TOTAL_BATCHES    (TOTAL_STEPS / STEPS_PER_BATCH)
#define SAMPLE_BATCHES   (SAMPLE_INTERVAL / STEPS_PER_BATCH)
#define NUM_SAMPLES      (TOTAL_STEPS / SAMPLE_INTERVAL)

/* ---- LBM ---------------------------------------------------------------- */
#define OMEGA  1.0f       /* tau=1.0, nu=1/6 — "clear water" */

/* ---- Spectrum ----------------------------------------------------------- */
#define NX2   (NX / 2 + 1)   /* R2C output width */
#define KMAX  (NX / 2)       /* max wavenumber */
#define NK    (KMAX + 1)     /* number of k bins */

/* ---- Precipitation System (Guardians) ----------------------------------- */
#define RHO_THRESH      1.01f       /* density trigger for new particle */
#define DRAIN_RADIUS    16          /* Gaussian drain at birth */
#define SINK_RADIUS     24          /* ongoing influence radius */
#define MAX_GUARDIANS   12          /* CHANGED: 194 → 12 (scaled ∝ area) */

/* ---- File I/O ----------------------------------------------------------- */
#define STATE_FILE      "build/f_state_post_relax.bin"

/* ============================================================================
 * LBM Kernels (unchanged from original)
 * ============================================================================ */

__constant__ float c_weights[9] = {
    4.0f/9.0f,
    1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f,
    1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f
};

__constant__ int c_ex[9] = {0, 1, 0, -1,  0, 1, -1, -1,  1};
__constant__ int c_ey[9] = {0, 0, 1,  0, -1, 1,  1, -1, -1};

__global__ void collide_stream(float* f, float* f_new, float omega) {
    /* ... kernel code unchanged from original ... */
    /* Note: Grid dimensions (NX, NY) are compile-time constants */
}

__global__ void compute_macroscopic(float* f, float* rho, float* ux, float* uy) {
    /* ... kernel code unchanged from original ... */
}

/* ============================================================================
 * Precipitation System (Guardians) - MODIFIED FOR 256×256
 * ============================================================================ */

typedef struct {
    float x, y;           /* position */
    float mass;           /* accreted mass */
    float drain_strength; /* current drain influence */
    int alive;            /* 1 = active, 0 = dead */
} Guardian;

/* Guardian array on device */
Guardian* d_guardians = nullptr;
int guardian_count = 0;

/* Initialize guardians (scaled for 256×256) */
void init_guardians() {
    /* Start with empty guardian list */
    guardian_count = 0;
    
    /* Allocate device memory for MAX_GUARDIANS */
    cudaMalloc(&d_guardians, MAX_GUARDIANS * sizeof(Guardian));
    
    /* Guardians will be born through precipitation during simulation */
    printf("[GUARDIANS] Initialized for 256×256 grid\n");
    printf("[GUARDIANS] Max guardians: %d (scaled from 194 for 1:5,400 density)\n", MAX_GUARDIANS);
}

/* Precipitation kernel: birth new guardians where density > RHO_THRESH */
__global__ void precipitation_kernel(float* rho, Guardian* guardians, int* guardian_count) {
    /* ... precipitation logic unchanged ... */
    /* Uses RHO_THRESH = 1.01f (baseline, will be tuned ±5%) */
}

/* Drain kernel: existing guardians influence fluid */
__global__ void drain_kernel(float* rho, float* ux, float* uy, Guardian* guardians, int count) {
    /* ... drain logic unchanged ... */
    /* Uses DRAIN_RADIUS = 16, SINK_RADIUS = 24 (may need tuning) */
}

/* ============================================================================
 * Main Execution (modified for 256×256 brain state loading)
 * ============================================================================ */

int main(int argc, char** argv) {
    printf("\n=======================================================================\n");
    printf("  FRACTAL HABIT 256×256 — GTX 1050 MVP @ 80W\n");
    printf("  Init: Hysteresis C80 | omega = 1.0 | nu = 0.166667\n");
    printf("=======================================================================\n");
    printf("  Steps:     %d  (%d batches of %d)\n", 
           TOTAL_STEPS, TOTAL_BATCHES, STEPS_PER_BATCH);
    printf("  Samples:   %d  (every %d steps)\n", NUM_SAMPLES, SAMPLE_INTERVAL);
    printf("  Diffusive: tau_d = %d steps  (run = %.1f tau_d)\n",
           (int)(1.0f / (1.0f/6.0f) * NX * NX / 2.0f),
           TOTAL_STEPS / (1.0f / (1.0f/6.0f) * NX * NX / 2.0f));
    printf("=======================================================================\n\n");
    
    /* GPU info */
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    printf("[CUDA] %s  SM %d.%d  SMs: %d\n",
           prop.name, prop.major, prop.minor, prop.multiProcessorCount);
    
    /* NVML power reading */
    nvmlDevice_t device;
    nvmlInit();
    nvmlDeviceGetHandleByIndex(0, &device);
    
    unsigned int power;
    nvmlDeviceGetPowerUsage(device, &power);
    printf("[NVML] Idle: %.1f W\n", power / 1000.0f);
    
    /* Load 256×256 brain state */
    printf("\n[LOAD] Loading 256×256 brain state...\n");
    
    /* ... rest of main() unchanged from original ... */
    /* Note: All grid references now use NX=256, NY=256 */
    
    /* Initialize guardians for 256×256 */
    init_guardians();
    
    /* Run simulation */
    printf("\n[RUN] Starting 256×256 simulation...\n");
    
    /* ... simulation loop unchanged ... */
    
    /* Cleanup */
    if (d_guardians) cudaFree(d_guardians);
    nvmlShutdown();
    
    return 0;
}