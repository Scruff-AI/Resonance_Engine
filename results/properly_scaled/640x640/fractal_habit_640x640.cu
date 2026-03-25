/* ============================================================================
 * FRACTAL HABIT ??? 200k steps in Clear Water
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

/* ---- Grid ---------------------------------------------------------------- */
#define NX    640
#define NY    640
#define NN    (NX * NY)
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

/* ---- Protocol ------------------------------------------------------------ */
#define TOTAL_STEPS      200000
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
    printf("  FRACTAL HABIT ??? 200k steps in Clear Water\n");
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

    printf("\n[RUN] 200k steps at omega=%.1f  (%.1f diffusive times)\n", OMEGA, TOTAL_STEPS/t_diff);
    printf("  sam |     step  | Velocity spectrum              | "
           "Density spectrum                | Power\n");
    printf("  ----|-----------|--------------------------------|"
           "---------------------------------|------\n");

    for (int batch = 0; batch < TOTAL_BATCHES; batch++) {
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

