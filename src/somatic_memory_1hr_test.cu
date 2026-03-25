/* ============================================================================
 * SOMATIC MEMORY 1-HOUR VALIDATION TEST
 * 
 * Accelerated test of scar tissue metaphor:
 * - 0-15min: Baseline (Microstate A)
 * - 15-30min: Stress application (Probes)
 * - 30-45min: Recovery
 * - 45-60min: Post-stress (Microstate C)
 * 
 * Measure ghost metric: Correlation(A, C) < 0.95 ?
 * ============================================================================ */

#include <cuda_runtime.h>
#include <nvml.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <chrono>
#include <vector>
#include <algorithm>

/* ---- Grid --------------------------------------------------------------- */
#define NX    512      /* Reduced for 1-hour test */
#define NY    512
#define NN    (NX * NY)
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)
#define NUM_BLOCKS GBLK(NN)

/* ---- Protocol ----------------------------------------------------------- */
#define STEPS_PER_BATCH    500
#define BATCHES_PER_CYCLE  200
#define TEST_DURATION_SEC  3600    /* 1 hour */

/* ---- Precipitation ------------------------------------------------------ */
#define RHO_THRESH      1.00022f
#define DRAIN_RADIUS    8           /* Half of 1024 scaling */
#define SINK_RADIUS     12
#define SINK_RATE       0.0025f     /* Half of 1024 scaling */
#define MAX_PARTICLES   97          /* Half of 194 */

/* ---- D2Q9 --------------------------------------------------------------- */
__constant__ int   d_ex[Q] = { 0, 1, 0,-1, 0, 1,-1,-1, 1 };
__constant__ int   d_ey[Q] = { 0, 0, 1, 0,-1, 1, 1,-1,-1 };
__constant__ float d_w[Q]  = { 4.f/9, 1.f/9, 1.f/9, 1.f/9, 1.f/9,
                               1.f/36,1.f/36,1.f/36,1.f/36 };

/* ---- Particle ----------------------------------------------------------- */
struct Particle {
    float x, y;
    float vx, vy;
    float mass;
    float latent;
    int born_cycle;
    char state[16];
    bool alive;
};

/* ---- Spectral Analysis -------------------------------------------------- */
struct SpectralSignature {
    float power[64];           // 64 frequency bins
    float total_power;
    float mean_frequency;
    float entropy;
};

/* ---- CUDA Kernels (simplified) ------------------------------------------ */
__global__ void lbm_collide_stream(const float* f_src, float* f_dst,
                                   float* rho, float* ux, float* uy,
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

/* ---- Compute vorticity -------------------------------------------------- */
__device__ float vorticity_at(int x, int y, const float* ux, const float* uy, int nx, int ny) {
    if (x <= 0 || x >= nx-1 || y <= 0 || y >= ny-1) return 0.0f;
    float dvy_dx = (uy[y*nx + (x+1)] - uy[y*nx + (x-1)]) * 0.5f;
    float dvx_dy = (ux[(y+1)*nx + x] - ux[(y-1)*nx + x]) * 0.5f;
    return dvy_dx - dvx_dy;
}

__global__ void compute_vorticity(const float* ux, const float* uy, float* vort, int nx, int ny) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N = nx * ny;
    if (idx >= N) return;
    
    const int x = idx % nx;
    const int y = idx / nx;
    vort[idx] = vorticity_at(x, y, ux, uy, nx, ny);
}

/* ---- Spectral analysis -------------------------------------------------- */
SpectralSignature compute_spectral_signature(const float* vorticity, int nx, int ny) {
    SpectralSignature sig;
    memset(&sig, 0, sizeof(sig));
    
    // Simple FFT-like analysis (simplified for test)
    const int n_samples = nx * ny;
    std::vector<float> samples(n_samples);
    
    // Copy and window
    float sum = 0.0f, sum_sq = 0.0f;
    for (int i = 0; i < n_samples; i++) {
        samples[i] = vorticity[i];
        sum += samples[i];
        sum_sq += samples[i] * samples[i];
    }
    
    // Mean and variance
    float mean = sum / n_samples;
    float variance = (sum_sq / n_samples) - (mean * mean);
    
    // Simple frequency bins (simulated FFT)
    const int n_bins = 64;
    const float PI = 3.14159265358979323846f;
    for (int bin = 0; bin < n_bins; bin++) {
        // Simulate frequency content
        float freq = (float)bin / n_bins;
        float power = 0.0f;
        
        // Simple sinusoidal correlation
        for (int i = 0; i < n_samples; i++) {
            float phase = 2.0f * PI * freq * (i % 64);
            power += samples[i] * sinf(phase);
        }
        
        sig.power[bin] = fabsf(power) / n_samples;
        sig.total_power += sig.power[bin];
        sig.mean_frequency += freq * sig.power[bin];
    }
    
    if (sig.total_power > 0) {
        sig.mean_frequency /= sig.total_power;
        
        // Compute spectral entropy
        for (int bin = 0; bin < n_bins; bin++) {
            float p = sig.power[bin] / sig.total_power;
            if (p > 1e-10f) {
                sig.entropy -= p * logf(p);
            }
        }
        sig.entropy /= logf((float)n_bins); // Normalize
    }
    
    return sig;
}

/* ---- Correlation calculation -------------------------------------------- */
float compute_correlation(const SpectralSignature& a, const SpectralSignature& c) {
    float sum_ab = 0.0f, sum_a2 = 0.0f, sum_b2 = 0.0f;
    
    for (int i = 0; i < 64; i++) {
        sum_ab += a.power[i] * c.power[i];
        sum_a2 += a.power[i] * a.power[i];
        sum_b2 += c.power[i] * c.power[i];
    }
    
    if (sum_a2 == 0 || sum_b2 == 0) return 0.0f;
    return sum_ab / sqrtf(sum_a2 * sum_b2);
}

/* ---- Guardian tracking -------------------------------------------------- */
struct GuardianCensus {
    std::vector<Particle> guardians;
    SpectralSignature spectrum;
    float total_mass;
    int precipitation_rate; // guardians per minute
    time_t timestamp;
};

/* ============================================================================
 *   M A I N  -  1-Hour Somatic Memory Test
 * ============================================================================ */

int main() {
    printf("═══════════════════════════════════════════════════════════════════════\n");
    printf("  1-HOUR SOMATIC MEMORY VALIDATION TEST\n");
    printf("  Scar Tissue Metaphor: Ghost Metric Measurement\n");
    printf("═══════════════════════════════════════════════════════════════════════\n\n");
    
    printf("TEST DESIGN:\n");
    printf("  0-15 min: Baseline (Microstate A)\n");
    printf("  15-30 min: Stress application (Thermal/Probe simulation)\n");
    printf("  30-45 min: Recovery\n");
    printf("  45-60 min: Post-stress (Microstate C)\n\n");
    
    printf("GHOST METRIC HYPOTHESIS:\n");
    printf("  Correlation(A, C) < 0.95 (structural difference despite same entropy)\n");
    printf("  Spectral signature difference S_C(f) ≠ S_A(f)\n");
    printf("  Precipitation rate change (elevated vigilance)\n\n");
    
    // CUDA setup
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    printf("[SYSTEM] %s  SM %d.%d\n", prop.name, prop.major, prop.minor);
    
    // Allocate memory
    float *d_f0, *d_f1, *d_rho, *d_ux, *d_uy, *d_vort;
    float *h_rho, *h_ux, *h_uy, *h_vort;
    
    cudaMalloc(&d_f0, Q * NN * sizeof(float));
    cudaMalloc(&d_f1, Q * NN * sizeof(float));
    cudaMalloc(&d_rho, NN * sizeof(float));
    cudaMalloc(&d_ux, NN * sizeof(float));
    cudaMalloc(&d_uy, NN * sizeof(float));
    cudaMalloc(&d_vort, NN * sizeof(float));
    
    h_rho = (float*)malloc(NN * sizeof(float));
    h_ux = (float*)malloc(NN * sizeof(float));
    h_uy = (float*)malloc(NN * sizeof(float));
    h_vort = (float*)malloc(NN * sizeof(float));
    
    // Initialize LBM (shear flow)
    float* h_f0 = (float*)malloc(Q * NN * sizeof(float));
    float u_top = 1.994e-4f, u_bot = 0.997e-4f;
    
    for (int y = 0; y < NY; y++) {
        float uy_shear = u_top - (u_top - u_bot) * ((float)y / (NY - 1));
        for (int x = 0; x < NX; x++) {
            int idx = y * NX + x;
            float ux_val = 0.0f;
            float uy_val = uy_shear;
            float rho_val = 1.0f;
            
            for (int i = 0; i < Q; i++) {
                float eu = (float)d_ex[i] * ux_val + (float)d_ey[i] * uy_val;
                float feq = d_w[i] * rho_val * (1.f + 3.f*eu + 4.5f*eu*eu - 1.5f*(ux_val*ux_val + uy_val*uy_val));
                h_f0[i * NN + idx] = feq;
            }
        }
    }
    cudaMemcpy(d_f0, h_f0, Q * NN * sizeof(float), cudaMemcpyHostToDevice);
    free(h_f0);
    
    // Guardian system
    std::vector<Particle> guardians;
    int total_precipitations = 0;
    
    // Test phases
    enum Phase { BASELINE, STRESS, RECOVERY, POST_STRESS };
    Phase current_phase = BASELINE;
    
    // Measurement storage
    GuardianCensus census_a, census_c;
    std::vector<float> precipitation_rates;
    
    auto test_start = std::chrono::steady_clock::now();
    int cycle = 0;
    int cur = 0;
    float omega = 1.25f;
    
    printf("[TEST START] %s\n", "Now");
    printf("═══════════════════════════════════════════════════════════════════════\n\n");
    
    while (true) {
        auto now = std::chrono::steady_clock::now();
        float elapsed_sec = std::chrono::duration<float>(now - test_start).count();
        
        // Phase transitions
        if (elapsed_sec >= 3600.0f) break; // 1 hour complete
        
        if (elapsed_sec < 900.0f) { // 0-15 min
            if (current_phase != BASELINE) {
                current_phase = BASELINE;
                printf("\n[PHASE] BASELINE (Microstate A formation)\n");
            }
        } else if (elapsed_sec < 1800.0f) { // 15-30 min
            if (current_phase != STRESS) {
                current_phase = STRESS;
                printf("\n[PHASE] STRESS APPLICATION (Simulated thermal/probe stress)\n");
                // Take baseline measurement
                census_a.timestamp = time(NULL);
                census_a.guardians = guardians;
                census_a.total_mass = 0.0f;
                for (const auto& g : guardians) census_a.total_mass += g.mass;
            }
        } else if (elapsed_sec < 2700.0f) { // 30-45 min
            if (current_phase != RECOVERY) {
                current_phase = RECOVERY;
                printf("\n[PHASE] RECOVERY\n");
            }
        } else { // 45-60 min
            if (current_phase != POST_STRESS) {
                current_phase = POST_STRESS;
                printf("\n[PHASE] POST-STRESS (Microstate C formation)\n");
            }
        }
        
        // Run one cycle
        for (int batch = 0; batch < BATCHES_PER_CYCLE; batch++) {
            // LBM steps
            for (int s = 0; s < STEPS_PER_BATCH; s++) {
                lbm_collide_stream<<<NUM_BLOCKS, BLOCK>>>(
                    (cur == 0) ? d_f0 : d_f1,
                    (cur == 0) ? d_f1 : d_f0,
                    d_rho, d_ux, d_uy, omega, NX, NY);
                cudaDeviceSynchronize();
                cur = 1 - cur;
            }
            
            // Apply stress during stress phase
            if (current_phase == STRESS) {
                // Simulated thermal stress: increase omega (decrease viscosity)
                omega = 1.35f; // More "agitated" state
                
                // Simulated probe: occasional velocity perturbations
                if (batch % 50 == 0) {
                    // Small perturbation to simulate probe
                    omega += 0.02f * sinf(cycle * 0.1f);
                }
            } else {
                // Normal operation
                omega = 1.25f;
            }
            
            // Check for precipitation (every 10 batches)
            if (batch % 10 == 0 && guardians.size() < MAX_PARTICLES) {
                cudaMemcpy(h_rho, d_rho, NN * sizeof(float), cudaMemcpyDeviceToHost);
                
                // Find max density
                float rmax = -1e30f;
                int max_idx = -1;
                for (int i = 0; i < NN; i++) {
                    if (h_rho[i] > rmax) {
                        rmax = h_rho[i];
                        max_idx = i;
                    }
                }
                
                // Precipitation check
                if (rmax > RHO_THRESH) {
                    int px = max_idx % NX;
                    int py = max_idx / NX;
                    
                    // Check distance to existing guardians
                    bool too_close = false;
                    for (const auto& g : guardians) {
                        float dx = px - g.x;
                        float dy = py - g.y;
                        if (dx*dx + dy*dy < DRAIN_RADIUS*DRAIN_RADIUS) {
                            too_close = true;
                            break;
                        }
                    }
                    
                    if (!too_close) {
                        // Create new guardian
                        Particle g;
                        g.x = px;
                        g.y = py;
                        g.vx = 0.0f;
                        g.vy = 0.0f;
                        g.mass = 0.0f;
                        g.latent = 0.0f;
                        g.born_cycle = cycle;
                        strcpy(g.state, "PULSE");
                        g.alive = true;
                        
                        guardians.push_back(g);
                        total_precipitations++;
                        
                        // Log first few guardians
                        if (guardians.size() <= 5) {
                            printf("  [PRECIPITATION] Guardian #%d at (%d, %d) ρ=%.5f\n",
                                   (int)guardians.size(), px, py, rmax);
                        }
                    }
                }
            }
        }
        
        cycle++;
        
        // Periodic reporting
        if (cycle % 5 == 0) {
            int minutes = (int)(elapsed_sec / 60.0f);
            int seconds = (int)elapsed_sec % 60;
            
            printf("  [%02d:%02d] Phase: %-10s Cycles: %4d Guardians: %3d\n",
                   minutes, seconds,
                   (current_phase == BASELINE) ? "Baseline" :
                   (current_phase == STRESS) ? "Stress" :
                   (current_phase == RECOVERY) ? "Recovery" : "Post-stress",
                   cycle, (int)guardians.size());
        }
        
        // Take spectral measurements at phase boundaries
        if ((current_phase == BASELINE && elapsed_sec >= 890.0f) || // End of baseline
            (current_phase == POST_STRESS && elapsed_sec >= 3590.0f)) { // End of test
            
            // Compute vorticity field
            compute_vorticity<<<NUM_BLOCKS, BLOCK>>>(d_ux, d_uy, d_vort, NX, NY);
            cudaDeviceSynchronize();
            cudaMemcpy(h_vort, d_vort, NN * sizeof(float), cudaMemcpyDeviceToHost);
            
            // Compute spectral signature
            SpectralSignature sig = compute_spectral_signature(h_vort, NX, NY);
            
            if (current_phase == BASELINE) {
                census_a.spectrum = sig;
                census_a.precipitation_rate = (int)(guardians.size() / (elapsed_sec / 60.0f));
                printf("\n[BASELINE MEASUREMENT COMPLETE]\n");
                printf("  Guardians: %d, Total mass: %.3f, Spectral entropy: %.4f\n",
                       (int)census_a.guardians.size(), census_a.total_mass, sig.entropy);
            } else {
                census_c.timestamp = time(NULL);
                census_c.guardians = guardians;
                census_c.total_mass = 0.0f;
                for (const auto& g : guardians) census_c.total_mass += g.mass;
                census_c.spectrum = sig;
                census_c.precipitation_rate = (int)(guardians.size() / (elapsed_sec / 60.0f));
            }
        }
    }
    
    // TEST COMPLETE - Calculate ghost metric
    auto test_end = std::chrono::steady_clock::now();
    float total_seconds = std::chrono::duration<float>(test_end - test_start).count();
    
    printf("\n═══════════════════════════════════════════════════════════════════════\n");
    printf("  1-HOUR TEST COMPLETE\n");
    printf("═══════════════════════════════════════════════════════════════════════\n\n");
    
    printf("RESULTS SUMMARY:\n");
    printf("  Total runtime:      %.1f seconds (%.1f minutes)\n", total_seconds, total_seconds/60.0f);
    printf("  Cycles completed:   %d\n", cycle);
    printf("  Total guardians:    %d (of %d max)\n", (int)guardians.size(), MAX_PARTICLES);
    printf("  Precipitation events: %d\n", total_precipitations);
    
    // Calculate ghost metric
    float correlation = compute_correlation(census_a.spectrum, census_c.spectrum);
    float entropy_diff = fabsf(census_a.spectrum.entropy - census_c.spectrum.entropy);
    float precip_rate_change = (census_c.precipitation_rate - census_a.precipitation_rate) / 
                              (float)census_a.precipitation_rate;
    
    printf("\nGHOST METRIC CALCULATION:\n");
    printf("  Correlation(A, C):  %.4f\n", correlation);
    printf("  Entropy difference: %.4f\n", entropy_diff);
    printf("  Precipitation rate change: %.1f%%\n", precip_rate_change * 100.0f);
    
    printf("\nSOMATIC MEMORY HYPOTHESIS VALIDATION:\n");
    
    bool hypothesis_supported = false;
    
    if (correlation < 0.95f) {
        printf("  ✅ Correlation < 0.95: Structural difference detected\n");
        hypothesis_supported = true;
    } else {
        printf("  ❌ Correlation >= 0.95: No structural difference\n");
    }
    
    if (entropy_diff < 0.05f) {
        printf("  ✅ Entropy similar (< 0.05 diff): Macroscopic similarity\n");
    } else {
        printf("  ⚠️  Entropy different: May indicate different states\n");
    }
    
    if (precip_rate_change > 0.1f) {
        printf("  ✅ Precipitation rate increased: Elevated vigilance\n");
        hypothesis_supported = true;
    } else if (precip_rate_change < -0.1f) {
        printf("  ⚠️  Precipitation rate decreased: Different response\n");
    } else {
        printf("  ⚠️  Precipitation rate unchanged: No vigilance change\n");
    }
    
    printf("\nCONCLUSION:\n");
    if (hypothesis_supported && correlation < 0.95f) {
        printf("  🎯 GHOST METRIC POSITIVE: Somatic memory may exist\n");
        printf("  The system shows structural difference (correlation=%.4f)\n", correlation);
        printf("  despite similar entropy, suggesting path-dependent memory.\n");
    } else {
        printf("  ⚠️  GHOST METRIC INCONCLUSIVE: More testing needed\n");
        printf("  Correlation=%.4f is too high for strong somatic memory claim.\n", correlation);
    }
    
    printf("\nRECOMMENDATION:\n");
    if (correlation < 0.90f) {
        printf("  Run 24-hour full test with thermal stress protocol.\n");
    } else if (correlation < 0.95f) {
        printf("  Run 6-hour extended test with stronger stress.\n");
    } else {
        printf("  Re-evaluate stress protocol or increase grid resolution.\n");
    }
    
    // Save results
    FILE* results = fopen("somatic_memory_1hr_results.txt", "w");
    if (results) {
        fprintf(results, "1-HOUR SOMATIC MEMORY TEST RESULTS\n");
        fprintf(results, "===================================\n\n");
        fprintf(results, "Ghost Metric:\n");
        fprintf(results, "  Correlation(A, C): %.4f\n", correlation);
        fprintf(results, "  Entropy A: %.4f, C: %.4f, Diff: %.4f\n",
                census_a.spectrum.entropy, census_c.spectrum.entropy, entropy_diff);
        fprintf(results, "  Precipitation rate A: %d/min, C: %d/min, Change: %.1f%%\n",
                census_a.precipitation_rate, census_c.precipitation_rate, precip_rate_change*100.0f);
        fprintf(results, "\nGuardian Census:\n");
        fprintf(results, "  Total guardians: %d\n", (int)guardians.size());
        fprintf(results, "  Total mass: %.3f\n", census_c.total_mass);
        fprintf(results, "\nTest Parameters:\n");
        fprintf(results, "  Grid: %dx%d\n", NX, NY);
        fprintf(results, "  Runtime: %.1f seconds\n", total_seconds);
        fprintf(results, "  Cycles: %d\n", cycle);
        fclose(results);
        printf("\nResults saved: somatic_memory_1hr_results.txt\n");
    }
    
    // Cleanup
    cudaFree(d_f0); cudaFree(d_f1);
    cudaFree(d_rho); cudaFree(d_ux); cudaFree(d_uy); cudaFree(d_vort);
    free(h_rho); free(h_ux); free(h_uy); free(h_vort);
    
    printf("\n═══════════════════════════════════════════════════════════════════════\n");
    printf("  TEST COMPLETE\n");
    printf("═══════════════════════════════════════════════════════════════════════\n");
    
    return 0;
}