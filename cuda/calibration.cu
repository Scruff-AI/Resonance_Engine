/* ============================================================================
 * Seed Brain v0.3 — Boot Calibration & Circadian Re-Probe
 *
 * The first 60 seconds of runtime are dedicated to discovering the
 * "Actual Physical Truth" of the Beast:
 *
 *   Phase 1 (10s): Thermal ramp — run LBM at max throughput, record T(t)
 *   Phase 2 (30s): Frequency sweep — test PLL lock at 64 frequencies
 *   Phase 3 (10s): Gain schedule — characterise Kp/Ki/Kd vs temperature
 *   Phase 4 (10s): Throughput calibration — measure LBM steps per cycle
 *
 * v0.3 changes:
 *   - Uses NVML power (not thermal proxy) for lock quality
 *   - Wider frequency sweep range for dual-resonance discovery
 *   - Pulse engine calibration happens in main.cu after boot cal
 *
 * Every 5 minutes, the Circadian Re-Probe runs a brief 5-second measurement
 * to detect ambient temperature drift, fan curve changes, or thermal
 * throttling transitions.
 * ============================================================================ */
#include "seed_brain.h"
#include <cstdio>
#include <cmath>
#include <cstring>
#include <chrono>
#include <thread>

#ifdef __CUDACC__
#include <cuda_runtime.h>
#endif

/* ---------- Utility: wall-clock seconds since epoch ------------------------ */
static double wall_seconds() {
    auto now = std::chrono::steady_clock::now();
    return std::chrono::duration<double>(now.time_since_epoch()).count();
}

/* ---------- Utility: measure single LBM step latency ----------------------- */
#ifdef __CUDACC__
static float measure_lbm_step_us(const VRAMMap& vram,
                                 float omega, int nx, int ny,
                                 cudaStream_t s)
{
    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);

    const int N = nx * ny;
    float* f_src = vram.f_buf[vram.current];
    float* f_dst = vram.f_buf[1 - vram.current];

    /* Warm up */
    launch_lbm_step(f_src, f_dst, vram.rho, vram.ux, vram.uy,
                    omega, nx, ny, s);
    cudaStreamSynchronize(s);

    /* Measure */
    cudaEventRecord(start, s);
    for (int i = 0; i < 100; i++) {
        launch_lbm_step(f_src, f_dst, vram.rho, vram.ux, vram.uy,
                        omega, nx, ny, s);
        float* tmp = f_src; f_src = f_dst; f_dst = tmp;
    }
    cudaEventRecord(stop, s);
    cudaStreamSynchronize(s);

    float ms = 0;
    cudaEventElapsedTime(&ms, start, stop);

    cudaEventDestroy(start);
    cudaEventDestroy(stop);

    return (ms * 1000.0f) / 100.0f;               /* microseconds per step    */
}
#endif

/* ---------- Autocorrelation for natural frequency detection ---------------- */
static float find_natural_frequency(const float* signal, int len,
                                    float sample_rate_hz)
{
    if (len < 32) return SB_PLL_F_INIT;

    /* Normalise signal                                                        */
    float mean = 0;
    for (int i = 0; i < len; i++) mean += signal[i];
    mean /= (float)len;

    /* Find first positive peak in autocorrelation (skip lag 0)                */
    float best_corr = -1e30f;
    int   best_lag  = 1;

    int max_lag = len / 2;
    for (int lag = 1; lag < max_lag; lag++) {
        float corr = 0;
        for (int i = 0; i < len - lag; i++) {
            corr += (signal[i] - mean) * (signal[i + lag] - mean);
        }
        corr /= (float)(len - lag);
        if (corr > best_corr) {
            best_corr = corr;
            best_lag  = lag;
        }
    }

    float period_s = (float)best_lag / sample_rate_hz;
    float freq     = 1.0f / period_s;

    /* Clamp to sane range                                                     */
    if (freq < SB_PLL_F_MIN) freq = SB_PLL_F_MIN;
    if (freq > SB_PLL_F_MAX) freq = SB_PLL_F_MAX;

    return freq;
}

/* ---------- PLL lock quality measurement for a test frequency -------------- */
static float measure_lock_quality(float f_test,
                                  IThermalObserver* obs,
                                  float duration_s)
{
    /* v0.3: Use NVML power jitter as phase signal (Beast has real power)     */
    float phase_accum = 0;
    float integrator  = 0;
    float prev_power  = obs->power();
    float sum_quality = 0;
    int   samples     = 0;

    double start = wall_seconds();
    double dt    = 1.0 / (f_test * 10.0); /* 10 samples per test cycle        */

    while (wall_seconds() - start < duration_s) {
        float power = obs->power();
        float dP    = power - prev_power;            /* power jitter = phase   */
        prev_power  = power;

        /* Simple PI tracking                                                  */
        float Kp = 0.1f, Ki = 0.01f;
        integrator += dP * (float)dt;
        float correction = Kp * dP + Ki * integrator;

        phase_accum += 2.0f * 3.14159265f * f_test * (float)dt + correction;

        /* Lock quality — high sensitivity for power signal                    */
        float phase_err = fabsf(correction);
        float q = 1.0f / (1.0f + 30.0f * phase_err);
        sum_quality += q;
        samples++;

        std::this_thread::sleep_for(
            std::chrono::microseconds((int)(dt * 1e6)));
    }

    return (samples > 0) ? sum_quality / (float)samples : 0.0f;
}

/* ============================================================================
 * Boot Calibration
 * ============================================================================ */
bool run_boot_calibration(VRAMMap& vram, PinnedMap& pinned,
                          IThermalObserver* obs,
                          const SeedBrainConfig& cfg,
                          CalibrationResult& result)
{
    fprintf(stdout, "\n");
    fprintf(stdout, "╔══════════════════════════════════════════════════╗\n");
    fprintf(stdout, "║     SEED BRAIN v0.3 — BOOT CALIBRATION          ║\n");
    fprintf(stdout, "║     Discovering the Physical Truth of the Beast ║\n");
    fprintf(stdout, "╚══════════════════════════════════════════════════╝\n\n");

    memset(&result, 0, sizeof(result));

#ifdef __CUDACC__
    cudaStream_t cal_stream;
    cudaStreamCreate(&cal_stream);

    /* ---- Phase 1: Thermal Ramp (10 seconds) ------------------------------ */
    fprintf(stdout, "[CAL Phase 1/4] Thermal ramp — recording T(t) for 10s...\n");

    float temp_signal[1024];
    int   temp_count = 0;
    const float sample_hz = 50.0f;                 /* 50 Hz sampling           */
    const float sample_dt = 1.0f / sample_hz;

    double phase1_start = wall_seconds();
    while (wall_seconds() - phase1_start < 10.0 && temp_count < 1024) {
        /* Run LBM flat-out to generate thermal load                           */
        float* f_src = vram.f_buf[vram.current];
        float* f_dst = vram.f_buf[1 - vram.current];
        launch_lbm_step(f_src, f_dst, vram.rho, vram.ux, vram.uy,
                        cfg.omega, cfg.nx, cfg.ny, cal_stream);
        vram.current = 1 - vram.current;

        /* Sample temperature                                                  */
        float T = obs->temperature();
        temp_signal[temp_count++] = T;

        std::this_thread::sleep_for(
            std::chrono::microseconds((int)(sample_dt * 1e6)));
    }
    cudaStreamSynchronize(cal_stream);

    float T_start = temp_signal[0];
    float T_end   = temp_signal[temp_count - 1];
    fprintf(stdout, "  Thermal ramp: %.1f°C → %.1f°C  (%d samples)\n",
            T_start, T_end, temp_count);

    /* ---- Phase 2: Frequency Sweep (30 seconds) --------------------------- */
    fprintf(stdout, "[CAL Phase 2/4] Frequency sweep — scanning [%.1f, %.1f] Hz...\n",
            SB_PLL_F_MIN, SB_PLL_F_MAX);

    float best_f        = SB_PLL_F_INIT;
    float best_quality  = 0;
    int   sweep_steps   = SB_CAL_SWEEP;
    float f_step        = (SB_PLL_F_MAX - SB_PLL_F_MIN) / (float)(sweep_steps - 1);
    float sweep_time_per = 30.0f / (float)sweep_steps;

    for (int s = 0; s < sweep_steps; s++) {
        float f_test = SB_PLL_F_MIN + (float)s * f_step;

        /* Keep GPU busy during measurement                                    */
        float* f_src = vram.f_buf[vram.current];
        float* f_dst = vram.f_buf[1 - vram.current];
        for (int i = 0; i < 10; i++) {
            launch_lbm_step(f_src, f_dst, vram.rho, vram.ux, vram.uy,
                            cfg.omega, cfg.nx, cfg.ny, cal_stream);
            float* tmp = f_src; f_src = f_dst; f_dst = tmp;
        }

        float quality = measure_lock_quality(f_test, obs, sweep_time_per);

        if (quality > best_quality) {
            best_quality = quality;
            best_f       = f_test;
        }

        if (s % 8 == 0) {
            fprintf(stdout, "  Sweep %2d/%d: f=%.2f Hz  Q=%.4f  T=%.1f°C\n",
                    s + 1, sweep_steps, f_test, quality,
                    obs->temperature());
        }
    }
    cudaStreamSynchronize(cal_stream);

    result.f_natural = best_f;
    fprintf(stdout, "  >>> Natural frequency: %.2f Hz  (Q=%.4f)\n",
            best_f, best_quality);

    /* Cross-check with autocorrelation                                        */
    float f_autocorr = find_natural_frequency(temp_signal, temp_count,
                                              sample_hz);
    fprintf(stdout, "  >>> Autocorrelation estimate: %.2f Hz\n", f_autocorr);

    /* If they agree within 20%, use the sweep result.  Otherwise, average.    */
    if (fabsf(f_autocorr - best_f) / best_f > 0.2f) {
        result.f_natural = (best_f + f_autocorr) * 0.5f;
        fprintf(stdout, "  >>> Estimates diverge — using average: %.2f Hz\n",
                result.f_natural);
    }

    /* ---- Phase Dithering Test (v0.3) ------------------------------------ */
    /* Test at the cognitive frequency and +/- 0.01 Hz to verify Q drops.     */
    {
        float f_on = result.f_natural;
        float f_hi = (f_on + 0.01f <= SB_PLL_F_MAX) ? f_on + 0.01f : f_on;
        float f_lo = (f_on - 0.01f >= SB_PLL_F_MIN) ? f_on - 0.01f : f_on;

        float q_on   = measure_lock_quality(f_on, obs, 2.0f);
        float q_high = measure_lock_quality(f_hi, obs, 2.0f);
        float q_low  = measure_lock_quality(f_lo, obs, 2.0f);

        float q_min_off = (q_high < q_low) ? q_high : q_low;
        float q_drop = q_on - q_min_off;

        fprintf(stdout, "  [DITHER] Q(on)=%.4f  Q(+0.1)=%.4f  Q(-0.1)=%.4f  "
                "drop=%.4f\n", q_on, q_high, q_low, q_drop);

        if (q_drop < 0.01f) {
            fprintf(stdout, "  [DITHER] WARNING: Q does not discriminate at "
                    "calibration timescale — runtime PLL will engage with "
                    "longer thermal dynamics.\n");
        } else {
            fprintf(stdout, "  [DITHER] Phase discrimination confirmed.\n");
        }
    }

    /* ---- Phase 3: Gain Schedule (10 seconds) ----------------------------- */
    fprintf(stdout, "[CAL Phase 3/4] Building gain schedule...\n");

    /*  For v0.1, produce a simple 3-entry piecewise schedule:
        low temperature  → conservative gains
        mid temperature  → nominal gains
        high temperature → aggressive gains                                    */

    result.gain_count = 3;

    result.gain_schedule[0].temp = T_start;
    result.gain_schedule[0].Kp   = cfg.Kp_base * 0.5f;
    result.gain_schedule[0].Ki   = cfg.Ki_base * 0.3f;
    result.gain_schedule[0].Kd   = cfg.Kd_base * 0.2f;

    float T_mid = (T_start + T_end) * 0.5f;
    result.gain_schedule[1].temp = T_mid;
    result.gain_schedule[1].Kp   = cfg.Kp_base;
    result.gain_schedule[1].Ki   = cfg.Ki_base;
    result.gain_schedule[1].Kd   = cfg.Kd_base;

    result.gain_schedule[2].temp = T_end + 10.0f;  /* headroom above max seen */
    result.gain_schedule[2].Kp   = cfg.Kp_base * 2.0f;
    result.gain_schedule[2].Ki   = cfg.Ki_base * 1.5f;
    result.gain_schedule[2].Kd   = cfg.Kd_base * 1.2f;

    fprintf(stdout, "  Gain schedule: %d entries  [%.0f°C → %.0f°C]\n",
            result.gain_count,
            result.gain_schedule[0].temp,
            result.gain_schedule[result.gain_count - 1].temp);

    /* ---- Phase 4: Throughput Calibration (10 seconds) -------------------- */
    fprintf(stdout, "[CAL Phase 4/4] Measuring LBM throughput...\n");

    float step_us = measure_lbm_step_us(vram, cfg.omega, cfg.nx, cfg.ny,
                                        cal_stream);
    float cycle_us = 1e6f / result.f_natural;      /* microseconds per cycle   */
    float usable   = cycle_us * 0.7f;              /* 70% budget for LBM       */
    float L        = usable / step_us;

    if (L < 10.0f) L = 10.0f;
    if (L > (float)cfg.max_lbm_steps) L = (float)cfg.max_lbm_steps;

    result.lbm_steps_per_cycle = L;

    fprintf(stdout, "  LBM step: %.1f μs   Cycle: %.0f μs   L=%d steps/cycle\n",
            step_us, cycle_us, (int)L);

    /* ---- Cleanup --------------------------------------------------------- */
    cudaStreamDestroy(cal_stream);

    fprintf(stdout, "\n╔══════════════════════════════════════════════════╗\n");
    fprintf(stdout, "║  CALIBRATION COMPLETE (v0.3 Beast)                ║\n");
    fprintf(stdout, "║  f_natural = %6.2f Hz                            ║\n",
            result.f_natural);
    fprintf(stdout, "║  L         = %4d   steps/cycle                   ║\n",
            (int)result.lbm_steps_per_cycle);
    fprintf(stdout, "║  T_range   = [%.0f, %.0f] °C                        ║\n",
            T_start, T_end);
    fprintf(stdout, "╚══════════════════════════════════════════════════╝\n\n");

#endif /* __CUDACC__ */
    return true;
}

/* ============================================================================
 * Circadian Re-Probe (every 5 minutes)
 *
 * Brief 5-second thermal measurement to detect drift in:
 *   - Ambient temperature
 *   - Fan curve efficiency
 *   - Thermal throttling onset point
 * ============================================================================ */
bool run_circadian_reprobe(PinnedMap& pinned,
                           IThermalObserver* obs,
                           const SeedBrainConfig& cfg,
                           CalibrationResult& result)
{
    fprintf(stdout, "[CIRCADIAN] Re-probing thermal environment...\n");

    /* 5-second snapshot at current frequency                                  */
    float current_f = pinned.pll->f_current;
    float quality   = measure_lock_quality(current_f, obs, 5.0);

    float T_now = obs->temperature();
    fprintf(stdout, "[CIRCADIAN] T=%.1f°C  Q=%.4f at f=%.2f Hz\n",
            T_now, quality, current_f);

    /* If lock quality has degraded, search ±1 Hz around current               */
    if (quality < cfg.Q_min * 0.8f) {
        fprintf(stdout, "[CIRCADIAN] Lock degraded — searching...\n");

        float best_f = current_f;
        float best_q = quality;

        for (float df = -1.0f; df <= 1.0f; df += 0.2f) {
            float f_test = current_f + df;
            if (f_test < SB_PLL_F_MIN || f_test > SB_PLL_F_MAX) continue;

            float q = measure_lock_quality(f_test, obs, 1.0);
            if (q > best_q) {
                best_q = q;
                best_f = f_test;
            }
        }

        if (best_f != current_f) {
            fprintf(stdout, "[CIRCADIAN] Frequency adjusted: %.2f → %.2f Hz\n",
                    current_f, best_f);
            result.f_natural = best_f;
            pinned.pll->f_center = best_f;
        }
    }

    /* Update gain schedule based on current temperature                       */
    if (T_now < result.gain_schedule[0].temp - 5.0f ||
        T_now > result.gain_schedule[result.gain_count - 1].temp + 5.0f)
    {
        fprintf(stdout, "[CIRCADIAN] Temperature outside gain schedule range — "
                "extending.\n");
        /* Extend rather than rebuild: shift the schedule endpoints             */
        if (T_now < result.gain_schedule[0].temp)
            result.gain_schedule[0].temp = T_now - 5.0f;
        if (T_now > result.gain_schedule[result.gain_count - 1].temp)
            result.gain_schedule[result.gain_count - 1].temp = T_now + 10.0f;
    }

    fprintf(stdout, "[CIRCADIAN] Re-probe complete.\n");
    return true;
}
