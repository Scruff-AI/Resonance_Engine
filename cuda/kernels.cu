/* ============================================================================
 * Seed Brain v0.3 — CUDA Kernels
 *
 * All GPU compute lives here:
 *   K0  lbm_collide_stream   — D2Q9 pull-collide-scatter (fused)
 *   K1  hebbian_update        — PLL-locked, hard-gated Hebbian learning
 *   K2  metabolic_decay       — A(D) = A₀·(1-D)^β, ΔD clock-locked to PLL
 *   K3  morton_dirty_check    — Coherence-threshold dirty-tile marking
 *   K4  snapshot_weights      — memcpy hebb → hebb_prev for Δw tracking
 *   K5  re_equilibrate        — Reconstruct f_i from (ρ, u) on load
 * ============================================================================ */
#include "seed_brain.h"
#include "morton.h"
#include <cstdio>
#include <cmath>

/* ---- D2Q9 constant memory ------------------------------------------------ */
/*  Direction:  0(rest) 1(E) 2(N) 3(W) 4(S) 5(NE) 6(NW) 7(SW) 8(SE)         */

__constant__ int   d_ex[SB_Q]  = { 0,  1,  0, -1,  0,  1, -1, -1,  1 };
__constant__ int   d_ey[SB_Q]  = { 0,  0,  1,  0, -1,  1,  1, -1, -1 };
__constant__ float d_w[SB_Q]   = { 4.0f/9.0f,
                                   1.0f/9.0f,  1.0f/9.0f,
                                   1.0f/9.0f,  1.0f/9.0f,
                                   1.0f/36.0f, 1.0f/36.0f,
                                   1.0f/36.0f, 1.0f/36.0f };
__constant__ int   d_opp[SB_Q] = { 0, 3, 4, 1, 2, 7, 8, 5, 6 };

/* Host-side copies for calibration / setup                                    */
static const int   h_ex[SB_Q]  = { 0,  1,  0, -1,  0,  1, -1, -1,  1 };
static const int   h_ey[SB_Q]  = { 0,  0,  1,  0, -1,  1,  1, -1, -1 };
static const float h_w[SB_Q]   = { 4.0f/9.0f,
                                   1.0f/9.0f,  1.0f/9.0f,
                                   1.0f/9.0f,  1.0f/9.0f,
                                   1.0f/36.0f, 1.0f/36.0f,
                                   1.0f/36.0f, 1.0f/36.0f };

void init_d2q9_constants() {
    /* Constants are statically initialised in __constant__; nothing to copy.
       This function exists for the pluggable-interface contract.              */
}

/* ============================================================================
 * K0: D2Q9 LBM — Pull-Collide, Fused with Macroscopic Output
 *
 * Memory layout (SoA, contiguous):
 *   f_src[i * N + idx]  →  distribution i at flat node idx
 *   f_dst[i * N + idx]  →  post-collision output
 *
 * Pull pattern (gather):  for each node (x,y), read f_i from neighbour
 *   (x − eₓ, y − eᵧ) in f_src.  This gives coalesced WRITES to f_dst.
 * ============================================================================ */
__global__ void lbm_collide_stream_kernel(
    const float* __restrict__ f_src,
    float*       __restrict__ f_dst,
    float*       __restrict__ rho_out,
    float*       __restrict__ ux_out,
    float*       __restrict__ uy_out,
    const float omega,
    const int   nx,
    const int   ny)
{
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N   = nx * ny;
    if (idx >= N) return;

    const int x = idx % nx;
    const int y = idx / nx;

    /* ---- Pull streaming -------------------------------------------------- */
    float f[SB_Q];
    #pragma unroll
    for (int i = 0; i < SB_Q; i++) {
        int sx = (x - d_ex[i] + nx) % nx;         /* periodic BC             */
        int sy = (y - d_ey[i] + ny) % ny;
        f[i] = f_src[i * N + sy * nx + sx];
    }

    /* ---- Macroscopic fields ---------------------------------------------- */
    float rho = 0.0f, u_x = 0.0f, u_y = 0.0f;
    #pragma unroll
    for (int i = 0; i < SB_Q; i++) {
        rho += f[i];
        u_x += (float)d_ex[i] * f[i];
        u_y += (float)d_ey[i] * f[i];
    }
    float inv_rho = 1.0f / rho;
    u_x *= inv_rho;
    u_y *= inv_rho;

    rho_out[idx] = rho;
    ux_out[idx]  = u_x;
    uy_out[idx]  = u_y;

    /* ---- BGK collision --------------------------------------------------- */
    const float u2 = u_x * u_x + u_y * u_y;
    #pragma unroll
    for (int i = 0; i < SB_Q; i++) {
        float eu  = (float)d_ex[i] * u_x + (float)d_ey[i] * u_y;
        float feq = d_w[i] * rho * (1.0f + 3.0f*eu + 4.5f*eu*eu - 1.5f*u2);
        f_dst[i * N + idx] = f[i] - omega * (f[i] - feq);
    }
}

void launch_lbm_step(const float* f_src, float* f_dst,
                     float* rho, float* ux, float* uy,
                     float omega, int nx, int ny, cudaStream_t s)
{
    const int N = nx * ny;
    lbm_collide_stream_kernel<<<SB_GRID(N), SB_BLOCK, 0, s>>>(
        f_src, f_dst, rho, ux, uy, omega, nx, ny);
}

/* ============================================================================
 * K1: Hebbian Update — Hard-Gated by PLL Lock Quality
 *
 * Fires ONCE per resonance cycle.  If lock_quality < Q_min the entire
 * kernel is a no-op (the brain is "unconscious").
 *
 * Update rule:
 *   w_d(x) += η · ρ(x) · ρ(neighbour_d(x)) · A(x)
 *
 * The learning rate η is modulated by the activation field: decayed memories
 * learn more weakly, creating natural salience filtering.
 * ============================================================================ */
__global__ void hebbian_update_kernel(
    float*       __restrict__ hebb_buf,    /* 8 × N contiguous                */
    const float* __restrict__ rho,
    const float* __restrict__ activation,
    const float  eta,
    const float  Q_min,
    const PLLState* __restrict__ pll,
    const int    nx,
    const int    ny)
{
    /* ---- Hard gate: check PLL lock quality (uniform branch) -------------- */
    if (pll->lock_quality < Q_min) return;

    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N   = nx * ny;
    if (idx >= N) return;

    const int x = idx % nx;
    const int y = idx / nx;
    const float rho_self = rho[idx];
    const float act      = activation[idx];

    /* Directions 1–8 (skip rest direction 0)                                 */
    #pragma unroll
    for (int d = 0; d < SB_HEBB_DIRS; d++) {
        int di    = d + 1;                         /* D2Q9 direction index     */
        int nb_x  = (x + d_ex[di] + nx) % nx;
        int nb_y  = (y + d_ey[di] + ny) % ny;
        int nb_id = nb_y * nx + nb_x;

        float rho_nb = rho[nb_id];
        float dw     = eta * rho_self * rho_nb * act;
        hebb_buf[d * N + idx] += dw;
    }
}

void launch_hebbian_update(float* hebb_buf, const float* rho,
                           const float* activation,
                           float eta, float Q_min,
                           const PLLState* pll_dev,
                           int nx, int ny, cudaStream_t s)
{
    const int N = nx * ny;
    hebbian_update_kernel<<<SB_GRID(N), SB_BLOCK, 0, s>>>(
        hebb_buf, rho, activation, eta, Q_min, pll_dev, nx, ny);
}

/* ============================================================================
 * K2: Metabolic Decay — Thermally-Coupled Forgetting
 *
 *   D(t+1) = D(t) + ΔD · M        (M = decay modulator from OpenClaw)
 *   A(t)   = (1 − D(t))^β
 *
 * ΔD is clock-locked to the PLL: HOT silicon → higher PLL freq → more
 * decay ticks per wall-second → faster forgetting.  "Survival of the fittest."
 * ============================================================================ */
__global__ void metabolic_decay_kernel(
    float*       __restrict__ activation,
    float*       __restrict__ decay_age,
    const float  beta,
    const float  delta_D,
    const float  eps_cold,
    const float* __restrict__ decay_modulator,
    const int    N)
{
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= N) return;

    /* Environmental load modulates decay rate (1.0 = neutral)                 */
    float M = (decay_modulator != nullptr) ? *decay_modulator : 1.0f;

    float D = decay_age[idx] + delta_D * M;
    if (D > 1.0f) D = 1.0f;                       /* clamp                    */

    float A = powf(1.0f - D, beta);
    if (A < eps_cold) A = 0.0f;                    /* hard floor               */

    decay_age[idx]   = D;
    activation[idx]  = A;
}

void launch_metabolic_decay(float* activation, float* decay_age,
                            float beta, float delta_D, float eps_cold,
                            const float* decay_modulator,
                            int n, cudaStream_t s)
{
    metabolic_decay_kernel<<<SB_GRID(n), SB_BLOCK, 0, s>>>(
        activation, decay_age, beta, delta_D, eps_cold, decay_modulator, n);
}

/* ============================================================================
 * K3: Morton Dirty-Tile Check
 *
 * One thread per tile.  For each tile, scan all 64 nodes × 8 directions,
 * compare |w − w_prev| against the coherence threshold δ:
 *
 *   δ(tile) = coherence_thresh · (1 − D̄_tile)^β
 *
 * Hot tiles (low D̄) have a TIGHTER threshold → flush more aggressively.
 * Cold tiles tolerate drift → fewer writes.
 * ============================================================================ */
__global__ void morton_dirty_check_kernel(
    const float* __restrict__ hebb_buf,
    const float* __restrict__ hebb_prev,
    uint32_t*    __restrict__ tile_dirty,
    float*       __restrict__ tile_coherence,
    const float  coherence_thresh,
    const float  beta,
    const float* __restrict__ decay_age,
    const int    nx,
    const int    ny)
{
    const int tile_idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (tile_idx >= SB_NUM_TILES) return;

    const int N = nx * ny;

    /* Decode tile position                                                    */
    uint32_t tile_x, tile_y;
    morton_decode((uint32_t)tile_idx, tile_x, tile_y);

    /* Scan nodes in this tile                                                 */
    float max_dw   = 0.0f;
    float sum_D    = 0.0f;

    for (int ly = 0; ly < SB_TILE_DIM; ly++) {
        for (int lx = 0; lx < SB_TILE_DIM; lx++) {
            int gx  = (int)(tile_x * SB_TILE_DIM) + lx;
            int gy  = (int)(tile_y * SB_TILE_DIM) + ly;
            int idx = gy * nx + gx;

            sum_D += decay_age[idx];

            for (int d = 0; d < SB_HEBB_DIRS; d++) {
                float dw = fabsf(hebb_buf[d * N + idx] -
                                 hebb_prev[d * N + idx]);
                if (dw > max_dw) max_dw = dw;
            }
        }
    }

    float D_avg     = sum_D / (float)SB_TILE_NODES;
    float threshold = coherence_thresh * powf(1.0f - D_avg, beta);

    tile_coherence[tile_idx] = max_dw;

    if (max_dw > threshold) {
        /* Set dirty bit via atomic OR (multiple tiles share one uint32)        */
        int word = tile_idx / 32;
        int bit  = tile_idx % 32;
        atomicOr(&tile_dirty[word], 1u << bit);
    }
}

void launch_morton_dirty_check(const float* hebb_buf,
                               const float* hebb_prev,
                               uint32_t* tile_dirty,
                               float* tile_coherence,
                               float coherence_thresh, float beta,
                               const float* decay_age,
                               int nx, int ny, cudaStream_t s)
{
    morton_dirty_check_kernel<<<SB_GRID(SB_NUM_TILES), SB_BLOCK, 0, s>>>(
        hebb_buf, hebb_prev, tile_dirty, tile_coherence,
        coherence_thresh, beta, decay_age, nx, ny);
}

/* ============================================================================
 * K4: Snapshot Weights — bulk memcpy on device for Δw tracking
 * ============================================================================ */
__global__ void snapshot_kernel(const float* __restrict__ src,
                                float*       __restrict__ dst,
                                const int count)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < count)
        dst[idx] = src[idx];
}

void launch_snapshot_weights(const float* src, float* dst,
                             int count, cudaStream_t s)
{
    snapshot_kernel<<<SB_GRID(count), SB_BLOCK, 0, s>>>(src, dst, count);
}

/* ============================================================================
 * K5: Re-Equilibrate — Reconstruct f_i from (ρ, u) after loading from disk
 *
 *   f_i = w_i · ρ · (1 + 3·eᵢ·u + 4.5·(eᵢ·u)² − 1.5·u²)
 * ============================================================================ */
__global__ void re_equilibrate_kernel(
    float*       __restrict__ f_buf,
    const float* __restrict__ rho,
    const float* __restrict__ ux,
    const float* __restrict__ uy,
    const int    nx,
    const int    ny)
{
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int N   = nx * ny;
    if (idx >= N) return;

    float r  = rho[idx];
    float vx = ux[idx];
    float vy = uy[idx];
    float u2 = vx * vx + vy * vy;

    #pragma unroll
    for (int i = 0; i < SB_Q; i++) {
        float eu  = (float)d_ex[i] * vx + (float)d_ey[i] * vy;
        float feq = d_w[i] * r * (1.0f + 3.0f*eu + 4.5f*eu*eu - 1.5f*u2);
        f_buf[i * N + idx] = feq;
    }
}

void launch_re_equilibrate(float* f_buf, const float* rho,
                           const float* ux, const float* uy,
                           int nx, int ny, cudaStream_t s)
{
    const int N = nx * ny;
    re_equilibrate_kernel<<<SB_GRID(N), SB_BLOCK, 0, s>>>(
        f_buf, rho, ux, uy, nx, ny);
}
