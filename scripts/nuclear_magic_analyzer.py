#!/usr/bin/env python3
"""
Nuclear Magic Number Analyzer
Analyzes EM sweep data for signatures of nuclear shell structure
in the coherence mode spectrum of the Resonance Engine lattice.

Six analyses:
  1. Coherence peak clustering         — find & cluster coherence maxima
  2. Mode counting vs shell degeneracy — compare distinct mode counts to magic numbers
  3. Gap structure                      — coherence gap ratios vs nuclear shell gaps
  4. Omega-resolved shell occupancy     — occupied-state count per omega slice
  5. 2D torus mode comparison           — lattice mode degeneracies vs observed peaks
  6. GUE pair correlation               — nearest-neighbor spacing vs Wigner surmise

Usage:
  python3 nuclear_magic_analyzer.py <sweep_csv>

Output saved to: ../results/nuclear_magic_analysis_<timestamp>.txt
"""

import sys
import os
import numpy as np
import pandas as pd
from datetime import datetime
from collections import Counter

# ── Nuclear physics constants ──────────────────────────────────────
MAGIC_NUMBERS = [2, 8, 20, 28, 50, 82, 126]
# Shell degeneracies (2j+1 for each filled subshell up to each magic closure)
SHELL_DEGENERACIES = {
    2:   [2],                           # 1s1/2
    8:   [2, 4, 2],                     # 1s, 1p3/2, 1p1/2
    20:  [2, 4, 2, 6, 4, 2],           # sd shell
    28:  [2, 4, 2, 6, 4, 2, 8],        # f7/2
    50:  [2, 4, 2, 6, 4, 2, 8, 6, 10, 4, 2],
    82:  [2, 4, 2, 6, 4, 2, 8, 6, 10, 4, 2, 12, 8, 6, 4, 2],
}
# Gap ratios between successive magic numbers
MAGIC_GAPS = np.diff(MAGIC_NUMBERS[:6]).astype(float)
MAGIC_GAP_RATIOS = MAGIC_GAPS / MAGIC_GAPS[0]  # normalized to first gap


def load_sweep(csv_path):
    """Load and validate sweep CSV."""
    df = pd.read_csv(csv_path)
    required = ['omega', 'khra_amp', 'gixx_amp', 'coherence', 'asymmetry', 'vorticity_mean']
    missing = [c for c in required if c not in df.columns]
    if missing:
        print(f"ERROR: Missing columns: {missing}")
        sys.exit(1)
    return df


# ═══════════════════════════════════════════════════════════════════
# Analysis 1: Coherence Peak Clustering
# ═══════════════════════════════════════════════════════════════════
def analysis_coherence_peaks(df, out):
    out.append("=" * 70)
    out.append("ANALYSIS 1: Coherence Peak Clustering")
    out.append("=" * 70)

    # Group by omega, find max coherence per omega slice
    omega_groups = df.groupby('omega')
    omega_vals = sorted(df['omega'].unique())

    peak_data = []
    for omega in omega_vals:
        group = omega_groups.get_group(omega)
        idx_max = group['coherence'].idxmax()
        row = group.loc[idx_max]
        peak_data.append({
            'omega': omega,
            'coherence': row['coherence'],
            'khra_amp': row['khra_amp'],
            'gixx_amp': row['gixx_amp'],
            'asymmetry': row['asymmetry'],
            'vorticity': row['vorticity_mean'],
        })

    peaks_df = pd.DataFrame(peak_data)
    coh_values = peaks_df['coherence'].values
    global_mean = coh_values.mean()
    global_std = coh_values.std()

    out.append(f"\nPeak coherence per omega slice:")
    out.append(f"  Mean: {global_mean:.6f}   Std: {global_std:.6f}")
    out.append(f"  Range: [{coh_values.min():.6f}, {coh_values.max():.6f}]")
    out.append("")

    # Identify significant peaks (> mean + 1 sigma)
    threshold = global_mean + global_std
    strong_peaks = peaks_df[peaks_df['coherence'] > threshold]
    out.append(f"Strong peaks (>{threshold:.6f}):")
    if len(strong_peaks) == 0:
        out.append("  None above threshold — trying mean + 0.5*sigma...")
        threshold = global_mean + 0.5 * global_std
        strong_peaks = peaks_df[peaks_df['coherence'] > threshold]

    for _, row in strong_peaks.iterrows():
        out.append(f"  Ω={row['omega']:.1f}  Coh={row['coherence']:.6f}  "
                   f"K={row['khra_amp']:.3f}  G={row['gixx_amp']:.4f}")

    # Cluster adjacent peaks
    if len(strong_peaks) > 0:
        clusters = []
        current_cluster = [strong_peaks.iloc[0]['omega']]
        for i in range(1, len(strong_peaks)):
            if strong_peaks.iloc[i]['omega'] - strong_peaks.iloc[i-1]['omega'] <= 0.15:
                current_cluster.append(strong_peaks.iloc[i]['omega'])
            else:
                clusters.append(current_cluster)
                current_cluster = [strong_peaks.iloc[i]['omega']]
        clusters.append(current_cluster)

        out.append(f"\n  {len(clusters)} cluster(s) of strong peaks:")
        for i, cl in enumerate(clusters):
            center = np.mean(cl)
            out.append(f"    Cluster {i+1}: Ω ∈ [{min(cl):.1f}, {max(cl):.1f}], center={center:.2f}, width={len(cl)}")

    out.append(f"\nFull peak table:")
    out.append(f"  {'Omega':>6}  {'Coherence':>10}  {'Khra':>6}  {'Gixx':>7}  {'Asym':>8}  {'Vort':>10}")
    for _, row in peaks_df.iterrows():
        marker = " *" if row['coherence'] > threshold else "  "
        out.append(f"  {row['omega']:6.1f}  {row['coherence']:10.6f}  {row['khra_amp']:6.3f}  "
                   f"{row['gixx_amp']:7.4f}  {row['asymmetry']:8.4f}  {row['vorticity']:10.6f}{marker}")

    return peaks_df


# ═══════════════════════════════════════════════════════════════════
# Analysis 2: Mode Counting vs Nuclear Shell Degeneracies
# ═══════════════════════════════════════════════════════════════════
def analysis_mode_counting(df, out):
    out.append("")
    out.append("=" * 70)
    out.append("ANALYSIS 2: Mode Counting vs Nuclear Shell Degeneracies")
    out.append("=" * 70)

    omega_vals = sorted(df['omega'].unique())

    # For each omega slice, count distinct coherence levels
    # "Distinct" = separated by more than a tolerance
    all_coherences = df['coherence'].values
    resolution = np.std(all_coherences) * 0.1  # adaptive resolution
    if resolution < 1e-6:
        resolution = 1e-4
    out.append(f"\nCoherence resolution (tolerance): {resolution:.6f}")

    mode_counts = {}
    for omega in omega_vals:
        group = df[df['omega'] == omega]
        coh_sorted = np.sort(group['coherence'].values)
        # Count distinct levels: merge values within resolution
        modes = [coh_sorted[0]]
        for c in coh_sorted[1:]:
            if c - modes[-1] > resolution:
                modes.append(c)
        mode_counts[omega] = len(modes)

    out.append(f"\nDistinct coherence modes per omega slice:")
    out.append(f"  {'Omega':>6}  {'Modes':>6}  {'Nearest Magic':>14}  {'Δ':>4}")
    total_modes = []
    for omega in omega_vals:
        n = mode_counts[omega]
        total_modes.append(n)
        nearest_magic = min(MAGIC_NUMBERS, key=lambda m: abs(m - n))
        delta = n - nearest_magic
        marker = " <<<" if delta == 0 else ""
        out.append(f"  {omega:6.1f}  {n:6d}  {nearest_magic:14d}  {delta:+4d}{marker}")

    # Overall statistics
    mode_arr = np.array(total_modes)
    out.append(f"\n  Mode count range: [{mode_arr.min()}, {mode_arr.max()}]")
    out.append(f"  Mean modes: {mode_arr.mean():.1f}")

    # Cumulative mode count across all omega
    all_coh = np.sort(df['coherence'].unique())
    distinct_global = [all_coh[0]]
    for c in all_coh[1:]:
        if c - distinct_global[-1] > resolution:
            distinct_global.append(c)
    out.append(f"  Total distinct global modes: {len(distinct_global)}")

    # Compare to magic numbers
    out.append(f"\n  Magic number proximity:")
    for mn in MAGIC_NUMBERS[:6]:
        hits = [omega for omega, n in mode_counts.items() if n == mn]
        if hits:
            out.append(f"    N={mn}: matched at Ω = {', '.join(f'{h:.1f}' for h in hits)}")
        else:
            closest = min(mode_counts.items(), key=lambda x: abs(x[1] - mn))
            out.append(f"    N={mn}: no exact match (closest: Ω={closest[0]:.1f} with {closest[1]} modes)")

    return mode_counts


# ═══════════════════════════════════════════════════════════════════
# Analysis 3: Gap Structure
# ═══════════════════════════════════════════════════════════════════
def analysis_gap_structure(df, out):
    out.append("")
    out.append("=" * 70)
    out.append("ANALYSIS 3: Gap Structure (Coherence Gaps vs Nuclear Shell Gaps)")
    out.append("=" * 70)

    # Global coherence spectrum: sort all unique values, compute gaps
    coh_all = np.sort(df['coherence'].unique())
    gaps = np.diff(coh_all)

    out.append(f"\nGlobal coherence spectrum: {len(coh_all)} unique values")
    out.append(f"  Value range: [{coh_all[0]:.6f}, {coh_all[-1]:.6f}]")
    out.append(f"  Total span: {coh_all[-1] - coh_all[0]:.6f}")

    if len(gaps) > 0:
        out.append(f"\nGap statistics:")
        out.append(f"  Mean gap: {gaps.mean():.6f}")
        out.append(f"  Std gap:  {gaps.std():.6f}")
        out.append(f"  Min gap:  {gaps.min():.6f}")
        out.append(f"  Max gap:  {gaps.max():.6f}")

        # Find the largest gaps — these correspond to "shell closures"
        n_top = min(10, len(gaps))
        top_idx = np.argsort(gaps)[-n_top:][::-1]
        out.append(f"\n  Top {n_top} largest gaps (shell boundaries):")
        out.append(f"    {'Rank':>4}  {'Gap':>10}  {'Below':>10}  {'Above':>10}  {'Ratio':>8}")
        gap_ratios = []
        for rank, idx in enumerate(top_idx):
            ratio = gaps[idx] / gaps.mean() if gaps.mean() > 0 else 0
            gap_ratios.append(gaps[idx])
            out.append(f"    {rank+1:4d}  {gaps[idx]:10.6f}  {coh_all[idx]:10.6f}  "
                       f"{coh_all[idx+1]:10.6f}  {ratio:8.2f}x")

        # Compare gap ratios to nuclear shell gap ratios
        if len(gap_ratios) >= 5:
            observed_ratios = np.array(gap_ratios[:5]) / gap_ratios[0]
            out.append(f"\n  Gap ratio comparison (top 5 gaps, normalized to largest):")
            out.append(f"    Observed: {', '.join(f'{r:.3f}' for r in observed_ratios)}")
            out.append(f"    Nuclear:  {', '.join(f'{r:.3f}' for r in MAGIC_GAP_RATIOS)}")
            correlation = np.corrcoef(observed_ratios, MAGIC_GAP_RATIOS[:5])[0, 1]
            out.append(f"    Pearson correlation: {correlation:.4f}")

    # Per-omega gap structure
    out.append(f"\n  Per-omega max gap:")
    omega_vals = sorted(df['omega'].unique())
    for omega in omega_vals:
        group = df[df['omega'] == omega]
        coh_sorted = np.sort(group['coherence'].values)
        g = np.diff(coh_sorted)
        if len(g) > 0:
            max_gap = g.max()
            mean_gap = g.mean()
            ratio = max_gap / mean_gap if mean_gap > 0 else 0
            out.append(f"    Ω={omega:.1f}: max_gap={max_gap:.6f}  mean_gap={mean_gap:.6f}  "
                       f"ratio={ratio:.2f}x")


# ═══════════════════════════════════════════════════════════════════
# Analysis 4: Omega-Resolved Shell Occupancy
# ═══════════════════════════════════════════════════════════════════
def analysis_shell_occupancy(df, out):
    out.append("")
    out.append("=" * 70)
    out.append("ANALYSIS 4: Omega-Resolved Shell Occupancy")
    out.append("=" * 70)

    global_mean = df['coherence'].mean()
    global_std = df['coherence'].std()

    # Define "shells" as coherence bands
    n_shells = 6
    coh_min = df['coherence'].min()
    coh_max = df['coherence'].max()
    shell_edges = np.linspace(coh_min, coh_max + 1e-9, n_shells + 1)

    out.append(f"\nShell definition: {n_shells} equal-width coherence bands")
    out.append(f"  Coherence range: [{coh_min:.6f}, {coh_max:.6f}]")
    out.append(f"  Shell width: {(coh_max - coh_min) / n_shells:.6f}")
    out.append("")

    omega_vals = sorted(df['omega'].unique())

    # Build occupancy matrix: omega × shell
    occupancy = np.zeros((len(omega_vals), n_shells), dtype=int)
    for i, omega in enumerate(omega_vals):
        group = df[df['omega'] == omega]
        for j in range(n_shells):
            count = ((group['coherence'] >= shell_edges[j]) &
                     (group['coherence'] < shell_edges[j+1])).sum()
            occupancy[i, j] = count

    # Display occupancy matrix
    header = f"  {'Omega':>6}  " + "  ".join(f"S{j+1:d}" for j in range(n_shells)) + "  Total  Pattern"
    out.append(header)
    for i, omega in enumerate(omega_vals):
        row = occupancy[i]
        total = row.sum()
        # Binary pattern: 1 if occupied, 0 if not
        pattern = "".join("█" if x > 0 else "·" for x in row)
        out.append(f"  {omega:6.1f}  " + "  ".join(f"{x:2d}" for x in row) +
                   f"  {total:5d}  {pattern}")

    # Count unique occupancy patterns
    patterns = ["".join("1" if x > 0 else "0" for x in occupancy[i]) for i in range(len(omega_vals))]
    pattern_counts = Counter(patterns)
    out.append(f"\n  Unique occupancy patterns: {len(pattern_counts)}")
    for pat, count in sorted(pattern_counts.items(), key=lambda x: -x[1]):
        visual = "".join("█" if c == "1" else "·" for c in pat)
        out.append(f"    {visual} ({pat}): {count} omega values")

    # Shell filling: total occupancy per shell across all omega
    shell_totals = occupancy.sum(axis=0)
    out.append(f"\n  Total occupancy per shell:")
    for j in range(n_shells):
        bar = "█" * (shell_totals[j] // 2) if shell_totals[j] > 0 else ""
        out.append(f"    S{j+1} [{shell_edges[j]:.5f} – {shell_edges[j+1]:.5f}]: "
                   f"{shell_totals[j]:4d}  {bar}")

    # Compare to nuclear filling order
    if len(omega_vals) >= 5:
        # "Closed shell" = omega where all points fall in same shell
        closed = []
        for i, omega in enumerate(omega_vals):
            nonzero = np.count_nonzero(occupancy[i])
            if nonzero == 1:
                filled_shell = np.argmax(occupancy[i])
                closed.append((omega, filled_shell + 1))
        out.append(f"\n  Closed-shell configurations (all points in one band):")
        if closed:
            for omega, shell in closed:
                out.append(f"    Ω={omega:.1f} → Shell {shell}")
        else:
            out.append(f"    None found (points spread across multiple bands)")


# ═══════════════════════════════════════════════════════════════════
# Analysis 5: 2D Torus Mode Comparison
# ═══════════════════════════════════════════════════════════════════
def analysis_torus_modes(df, out):
    out.append("")
    out.append("=" * 70)
    out.append("ANALYSIS 5: 2D Torus Mode Comparison")
    out.append("=" * 70)

    # On a 2D torus (periodic lattice), modes are labeled (n, m)
    # with energy ~ n² + m². Degeneracy = # of (n,m) pairs giving same E.
    # This is the sum-of-two-squares function r₂(E).
    max_E = 50
    torus_degeneracy = {}
    for n in range(-int(np.sqrt(max_E)) - 1, int(np.sqrt(max_E)) + 2):
        for m in range(-int(np.sqrt(max_E)) - 1, int(np.sqrt(max_E)) + 2):
            E = n * n + m * m
            if 0 < E <= max_E:
                torus_degeneracy[E] = torus_degeneracy.get(E, 0) + 1

    torus_energies = sorted(torus_degeneracy.keys())
    torus_degens = [torus_degeneracy[E] for E in torus_energies]

    out.append(f"\nTheoretical 2D torus modes (E = n² + m², E ≤ {max_E}):")
    out.append(f"  Representable energies: {len(torus_energies)}")
    out.append(f"  Cumulative modes at each energy:")
    cumulative = np.cumsum(torus_degens)
    out.append(f"    {'E':>4}  {'Degen':>6}  {'Cumul':>6}  {'Magic?':>7}")
    for E, d, c in zip(torus_energies, torus_degens, cumulative):
        magic_hit = " <<<" if c in MAGIC_NUMBERS else ""
        out.append(f"    {E:4d}  {d:6d}  {c:6d}{magic_hit}")

    # Compare torus cumulative degeneracies to magic numbers
    magic_hits = []
    for mn in MAGIC_NUMBERS[:6]:
        if mn in cumulative.tolist():
            idx = cumulative.tolist().index(mn)
            magic_hits.append((mn, torus_energies[idx]))
    out.append(f"\n  Torus shell closures matching magic numbers:")
    if magic_hits:
        for mn, E in magic_hits:
            out.append(f"    Magic N={mn} occurs at torus energy E={E}")
    else:
        out.append(f"    No exact matches")
        # Find nearest
        for mn in MAGIC_NUMBERS[:6]:
            nearest_idx = np.argmin(np.abs(cumulative - mn))
            out.append(f"    Magic N={mn}: nearest cumulative = {cumulative[nearest_idx]} at E={torus_energies[nearest_idx]}")

    # Now compare to observed data
    # Use coherence as proxy for "energy level"
    # Count modes in the observed spectrum and compare degeneracies
    omega_vals = sorted(df['omega'].unique())
    resolution = np.std(df['coherence'].values) * 0.1
    if resolution < 1e-6:
        resolution = 1e-4

    # Per-omega mode degeneracy: count how many (khra, gixx) pairs
    # give the same coherence level (within resolution)
    out.append(f"\n  Observed mode degeneracies per omega:")
    out.append(f"    {'Omega':>6}  {'Modes':>6}  {'Max Degen':>10}  {'Degen Pattern':>20}")
    for omega in omega_vals:
        group = df[df['omega'] == omega]
        coh_sorted = np.sort(group['coherence'].values)
        # Bin into distinct modes
        modes = []
        current_mode = [coh_sorted[0]]
        for c in coh_sorted[1:]:
            if c - current_mode[-1] > resolution:
                modes.append(len(current_mode))
                current_mode = [c]
            else:
                current_mode.append(c)
        modes.append(len(current_mode))
        # modes[] now holds the degeneracy of each mode
        max_degen = max(modes)
        pattern = ",".join(str(d) for d in modes[:8])
        if len(modes) > 8:
            pattern += "..."
        out.append(f"    {omega:6.1f}  {len(modes):6d}  {max_degen:10d}  {pattern:>20}")

    # Correlation between observed degeneracy spectrum and torus degeneracies
    # Use the full dataset: histogram of degeneracies
    all_coh = np.sort(df['coherence'].values)
    global_modes = []
    current_mode = [all_coh[0]]
    for c in all_coh[1:]:
        if c - current_mode[-1] > resolution:
            global_modes.append(len(current_mode))
            current_mode = [c]
        else:
            current_mode.append(c)
    global_modes.append(len(current_mode))

    obs_degen_hist = Counter(global_modes)
    torus_degen_hist = Counter(torus_degens)

    out.append(f"\n  Degeneracy histograms:")
    out.append(f"    {'Degen':>6}  {'Observed':>9}  {'Torus':>6}")
    all_degens = sorted(set(list(obs_degen_hist.keys()) + list(torus_degen_hist.keys())))
    for d in all_degens[:15]:
        out.append(f"    {d:6d}  {obs_degen_hist.get(d, 0):9d}  {torus_degen_hist.get(d, 0):6d}")


# ═══════════════════════════════════════════════════════════════════
# Analysis 6: GUE Pair Correlation (Random Matrix Theory)
# ═══════════════════════════════════════════════════════════════════
def analysis_gue_correlation(df, out):
    out.append("")
    out.append("=" * 70)
    out.append("ANALYSIS 6: GUE Pair Correlation (Random Matrix Theory)")
    out.append("=" * 70)

    # Nearest-neighbor spacing distribution
    # For GUE (β=2): P(s) = (32/π²) s² exp(-4s²/π)  (Wigner surmise)
    # For Poisson:    P(s) = exp(-s)
    # Normalize spacings to mean = 1

    coh_sorted = np.sort(df['coherence'].unique())
    spacings = np.diff(coh_sorted)

    if len(spacings) < 5:
        out.append("\n  Insufficient unique coherence values for spacing analysis.")
        return

    mean_spacing = spacings.mean()
    if mean_spacing > 0:
        s_normalized = spacings / mean_spacing  # normalize to <s> = 1
    else:
        out.append("\n  Zero mean spacing — all values identical.")
        return

    out.append(f"\nSpacing statistics (normalized to mean=1):")
    out.append(f"  N unique levels: {len(coh_sorted)}")
    out.append(f"  N spacings:      {len(spacings)}")
    out.append(f"  Raw mean spacing: {mean_spacing:.6e}")
    out.append(f"  Normalized <s>:   {s_normalized.mean():.4f}")
    out.append(f"  Normalized var:   {np.var(s_normalized):.4f}")
    out.append(f"  Normalized <s²>:  {np.mean(s_normalized**2):.4f}")

    # GUE prediction: var(s) = (4 - π) * π / (2π²)  ≈ 0.178
    # Poisson prediction: var(s) = 1.0
    gue_var = (4 - np.pi) * np.pi / (2 * np.pi**2)
    obs_var = np.var(s_normalized)
    out.append(f"\n  Variance comparison:")
    out.append(f"    Observed:  {obs_var:.4f}")
    out.append(f"    GUE (β=2): {gue_var:.4f}")
    out.append(f"    Poisson:   1.0000")

    if abs(obs_var - gue_var) < abs(obs_var - 1.0):
        out.append(f"    → Closer to GUE (level repulsion present)")
    else:
        out.append(f"    → Closer to Poisson (uncorrelated levels)")

    # Histogram of normalized spacings
    n_bins = 20
    bin_edges = np.linspace(0, max(4.0, s_normalized.max()), n_bins + 1)
    hist, _ = np.histogram(s_normalized, bins=bin_edges, density=True)
    bin_centers = 0.5 * (bin_edges[:-1] + bin_edges[1:])

    # Theoretical curves
    gue_pdf = (32.0 / (np.pi**2)) * bin_centers**2 * np.exp(-4.0 * bin_centers**2 / np.pi)
    poisson_pdf = np.exp(-bin_centers)

    out.append(f"\n  Spacing distribution P(s):")
    out.append(f"    {'s':>6}  {'Observed':>9}  {'GUE':>7}  {'Poisson':>8}")
    for i in range(n_bins):
        out.append(f"    {bin_centers[i]:6.2f}  {hist[i]:9.4f}  {gue_pdf[i]:7.4f}  {poisson_pdf[i]:8.4f}")

    # Chi-squared goodness of fit (manual, no scipy)
    # Against GUE and Poisson
    chi2_gue = 0
    chi2_poisson = 0
    bins_used = 0
    for i in range(n_bins):
        if gue_pdf[i] > 0.01:  # only use bins with sufficient expected density
            chi2_gue += (hist[i] - gue_pdf[i])**2 / gue_pdf[i]
            bins_used += 1
        if poisson_pdf[i] > 0.01:
            chi2_poisson += (hist[i] - poisson_pdf[i])**2 / poisson_pdf[i]

    out.append(f"\n  Goodness of fit (χ²-like, lower is better):")
    out.append(f"    vs GUE:     {chi2_gue:.4f}  (over {bins_used} bins)")
    out.append(f"    vs Poisson: {chi2_poisson:.4f}")
    if chi2_gue < chi2_poisson:
        out.append(f"    → GUE is better fit")
    else:
        out.append(f"    → Poisson is better fit")

    # Number variance Σ²(L): count fluctuations in intervals of length L
    out.append(f"\n  Number variance Σ²(L):")
    out.append(f"    {'L':>6}  {'Σ²(obs)':>9}  {'GUE':>7}  {'Poisson':>8}")
    for L in [0.5, 1.0, 1.5, 2.0, 3.0, 5.0]:
        # Count how many spacings fall in windows of size L*mean_spacing
        window = L * mean_spacing
        counts = []
        for start_idx in range(len(coh_sorted) - 1):
            start_val = coh_sorted[start_idx]
            # Count levels in [start_val, start_val + window)
            n_in_window = np.sum((coh_sorted >= start_val) & (coh_sorted < start_val + window))
            counts.append(n_in_window)
        counts = np.array(counts, dtype=float)
        sigma2_obs = np.var(counts) if len(counts) > 0 else 0

        # GUE: Σ²(L) ≈ (2/π²)(ln(2πL) + γ + 1) for large L (γ = Euler-Mascheroni)
        gamma_em = 0.5772156649
        sigma2_gue = (2.0 / np.pi**2) * (np.log(2 * np.pi * L) + gamma_em + 1) if L > 0 else 0
        sigma2_poisson = L  # Poisson: Σ²(L) = L

        out.append(f"    {L:6.1f}  {sigma2_obs:9.4f}  {sigma2_gue:7.4f}  {sigma2_poisson:8.4f}")


# ═══════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════
def main():
    if len(sys.argv) < 2:
        # Auto-find latest sweep CSV
        sweep_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                 "sweep_results")
        csvs = sorted([f for f in os.listdir(sweep_dir) if f.startswith("em_direct_sweep") and f.endswith(".csv")])
        if not csvs:
            print("Usage: python3 nuclear_magic_analyzer.py <sweep_csv>")
            print("  No sweep CSVs found in sweep_results/")
            sys.exit(1)
        csv_path = os.path.join(sweep_dir, csvs[-1])
        print(f"Auto-selected latest sweep: {csvs[-1]}")
    else:
        csv_path = sys.argv[1]

    if not os.path.exists(csv_path):
        print(f"ERROR: File not found: {csv_path}")
        sys.exit(1)

    df = load_sweep(csv_path)
    print(f"Loaded {len(df)} data points from {os.path.basename(csv_path)}")
    print(f"  Omega range: {df['omega'].min():.1f} – {df['omega'].max():.1f}")
    print(f"  Coherence range: {df['coherence'].min():.6f} – {df['coherence'].max():.6f}")
    print()

    out = []
    out.append("╔══════════════════════════════════════════════════════════════════════╗")
    out.append("║           NUCLEAR MAGIC NUMBER ANALYSIS — RESONANCE ENGINE          ║")
    out.append("╚══════════════════════════════════════════════════════════════════════╝")
    out.append(f"Source: {os.path.basename(csv_path)}")
    out.append(f"Points: {len(df)}")
    out.append(f"Date:   {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    out.append(f"Omega:  {df['omega'].min():.1f} – {df['omega'].max():.1f} ({df['omega'].nunique()} steps)")
    out.append(f"Coherence: {df['coherence'].min():.6f} – {df['coherence'].max():.6f}")

    # Run all six analyses
    peaks_df = analysis_coherence_peaks(df, out)
    mode_counts = analysis_mode_counting(df, out)
    analysis_gap_structure(df, out)
    analysis_shell_occupancy(df, out)
    analysis_torus_modes(df, out)
    analysis_gue_correlation(df, out)

    # Summary
    out.append("")
    out.append("=" * 70)
    out.append("SUMMARY")
    out.append("=" * 70)

    best_omega = peaks_df.loc[peaks_df['coherence'].idxmax()]
    out.append(f"\n  Best coherence: {best_omega['coherence']:.6f} at "
               f"Ω={best_omega['omega']:.1f} K={best_omega['khra_amp']:.3f} G={best_omega['gixx_amp']:.4f}")

    mode_arr = np.array(list(mode_counts.values()))
    out.append(f"  Mode count range: {mode_arr.min()} – {mode_arr.max()}")

    magic_matches = sum(1 for n in mode_counts.values() if n in MAGIC_NUMBERS)
    out.append(f"  Omega slices matching a magic number: {magic_matches}/{len(mode_counts)}")

    out.append(f"\n  Nuclear magic numbers for reference: {MAGIC_NUMBERS}")
    out.append("")

    # Print to stdout
    report = "\n".join(out)
    print(report)

    # Save to file
    results_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                               "results")
    os.makedirs(results_dir, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_path = os.path.join(results_dir, f"nuclear_magic_analysis_{timestamp}.txt")
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(report)
    print(f"\nSaved to: {output_path}")


if __name__ == "__main__":
    main()
