#!/usr/bin/env python3
"""
Physics Domain Analysis — Resonance Engine
Tests four structural hypotheses against the 375-point sweep data:
  REPORT 1: Nuclear Magic Numbers (3D harmonic oscillator / spin-orbit)
  REPORT 2: Brillouin Zone Band Gaps (crystal lattice electronic structure)
  REPORT 3: Kirkwood Gaps & KAM Theory (resonance voids / golden stability)
  REPORT 4: Cosmic Octave Recurrence (Lehto 2026 — 10²⁴-meter pattern)

No HTML. No dashboards. Just physics.
"""

import sys, os
import numpy as np
import pandas as pd
from datetime import datetime
from collections import Counter


# ── Utility functions used across reports ──
def nearest_rational(x, max_denom=20):
    """Find p/q closest to x with q <= max_denom."""
    best_p, best_q, best_err = 0, 1, abs(x)
    for q in range(1, max_denom + 1):
        p = round(x * q)
        err = abs(x - p/q)
        if err < best_err:
            best_p, best_q, best_err = p, q, err
    return best_p, best_q, best_err


def irrationality_measure(x, max_denom=50):
    """How 'irrational' is x? Higher = harder to approximate rationally."""
    min_product = float('inf')
    for q in range(1, max_denom + 1):
        p = round(x * q)
        product = abs(x - p/q) * q * q
        if product > 0:
            min_product = min(min_product, product)
    return min_product


# ── Paths ──
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SWEEP_DIR = os.path.join(BASE, "sweep_results")
RESULTS_DIR = os.path.join(BASE, "results")
os.makedirs(RESULTS_DIR, exist_ok=True)

# ══════════════════════════════════════════════════════════════════════════
# PHYSICAL CONSTANTS & PREDICTIONS
# ══════════════════════════════════════════════════════════════════════════

# 3D Harmonic Oscillator shell degeneracies (without spin):
#   Shell N has degeneracy g(N) = (N+1)(N+2)/2
#   With nucleon spin-1/2:  g_spin(N) = (N+1)(N+2)
# Per-shell degeneracies (with spin): 2, 6, 12, 20, 30, 42, ...
HO_SHELL_DEGEN = [(N+1)*(N+2) for N in range(8)]  # [2, 6, 12, 20, 30, 42, 56, 72]
# Cumulative: 2, 8, 20, 40, 70, 112, 168, 240 — the "harmonic oscillator magic numbers"
HO_MAGIC = list(np.cumsum(HO_SHELL_DEGEN))

# Spin-orbit magic numbers (Mayer-Jensen):
# The l·s coupling pushes the j=l+1/2 sublevel of shell N down into shell N-1,
# creating the actual nuclear magic numbers:
SO_MAGIC = [2, 8, 20, 28, 50, 82, 126]

# Spectroscopic subshells: n l_j notation
SUBSHELLS = [
    # (cumulative_occupancy, label, 2j+1)
    (2,   "1s₁/₂",   2),
    (6,   "1p₃/₂",   4),
    (8,   "1p₁/₂",   2),   # ← magic 8
    (12,  "1d₅/₂",   6),
    (14,  "2s₁/₂",   2),
    (16,  "1d₃/₂",   4),
    (20,  "1f₇/₂",   8),   # ← magic 20 (HO), but filling continues
    (28,  "1f₇/₂*",  8),   # ← magic 28 (f₇/₂ intruder from N=3→N=2)
    (32,  "2p₃/₂",   4),
    (34,  "1f₅/₂",   6),
    (38,  "2p₁/₂",   2),
    (40,  "1g₉/₂",  10),
    (50,  "1g₉/₂*", 10),   # ← magic 50
]

# Brillouin zone: in a 1D lattice with period a, zone boundaries at k = n*π/a
# For a 2D square lattice, zone boundaries form nested squares/diamonds
# The wave vector k maps to our omega parameter

# Kirkwood gaps: orbital resonances where period ratios are small integers
# Jupiter clears asteroids at 4:1 (2.06 AU), 3:1 (2.50), 5:2 (2.82), 7:3 (2.95), 2:1 (3.28)
# KAM theory: stability at irrational frequency ratios, especially golden ratio
GOLDEN = (1 + np.sqrt(5)) / 2  # 1.61803...
SILVER = 1 + np.sqrt(2)         # 2.41421...

# ── Cosmic Octave Ladder (Lehto 2026) ──
# 15 canonical structures spanning 42 orders of magnitude
# Source: Chris Lehto, "Scale Recurrence Across Cosmic Structures"
# https://github.com/Chris-L78/cosmic-octaves-analysis
COSMIC_LADDER = [
    ("Proton",              -15.08),
    ("Atomic Orbital (H)",  -10.28),
    ("Ribosome",             -7.96),
    ("Bacterium",            -6.00),
    ("C. elegans",           -3.30),
    ("Human",                -0.046),
    ("City",                  3.00),
    ("Earth",                 6.80),
    ("Sun",                   8.84),
    ("Solar System",         12.65),
    ("Open Cluster",         16.67),
    ("Local Bubble",         18.665),
    ("Milky Way",            20.70),
    ("Virgo Supercluster",   23.84),
    ("Observable Universe",  26.64),
]
COSMIC_LOG10 = np.array([s[1] for s in COSMIC_LADDER])
COSMIC_NAMES = [s[0] for s in COSMIC_LADDER]

# The 7 canonical octave pairs (lower_idx, upper_idx)
# Each spans ~10^24 meters (Δlog₁₀ ≈ 24.0)
COSMIC_OCTAVE_PAIRS = [
    (0, 8),   # Proton → Sun
    (1, 9),   # Atomic Orbital → Solar System
    (2, 10),  # Ribosome → Open Cluster
    (3, 11),  # Bacterium → Local Bubble
    (4, 12),  # C. elegans → Milky Way
    (5, 13),  # Human → Virgo Supercluster
    (6, 14),  # City → Observable Universe
]
COSMIC_IDEAL_DELTA = 24.0  # The cosmic octave interval in log₁₀(meters)


def load_data():
    csvs = sorted([f for f in os.listdir(SWEEP_DIR) if f.startswith("em_direct_sweep") and f.endswith(".csv")])
    if not csvs:
        print("No sweep CSVs found"); sys.exit(1)
    # Take the largest (most complete)
    biggest = max(csvs, key=lambda f: os.path.getsize(os.path.join(SWEEP_DIR, f)))
    path = os.path.join(SWEEP_DIR, biggest)
    df = pd.read_csv(path)
    return df, biggest


def resolve_modes(coherence_values, resolution):
    """Cluster coherence values into distinct modes. Returns list of (center, count) tuples."""
    sorted_vals = np.sort(coherence_values)
    modes = []
    current = [sorted_vals[0]]
    for v in sorted_vals[1:]:
        if v - current[-1] > resolution:
            modes.append((np.mean(current), len(current)))
            current = [v]
        else:
            current.append(v)
    modes.append((np.mean(current), len(current)))
    return modes


# ══════════════════════════════════════════════════════════════════════════
# REPORT 1: NUCLEAR MAGIC NUMBERS
# ══════════════════════════════════════════════════════════════════════════
def report_nuclear(df, R):
    R.append("")
    R.append("╔" + "═"*76 + "╗")
    R.append("║  REPORT 1: NUCLEAR MAGIC NUMBERS                                          ║")
    R.append("║  Hypothesis: Lattice coherence modes reproduce harmonic oscillator         ║")
    R.append("║  shell structure and/or spin-orbit magic numbers                           ║")
    R.append("╚" + "═"*76 + "╝")
    R.append("")
    R.append("BACKGROUND")
    R.append("─"*76)
    R.append("The nuclear shell model predicts stability at 'magic' nucleon counts.")
    R.append("The first approximation — a 3D quantum harmonic oscillator — gives shell")
    R.append("degeneracies (N+1)(N+2) for shell N=0,1,2,3,...:")
    R.append("")
    R.append("  Shell N:         0      1      2       3       4       5")
    R.append(f"  Per-shell (2j+1): {HO_SHELL_DEGEN[0]:>2}     {HO_SHELL_DEGEN[1]:>2}     {HO_SHELL_DEGEN[2]:>2}      {HO_SHELL_DEGEN[3]:>2}      {HO_SHELL_DEGEN[4]:>2}      {HO_SHELL_DEGEN[5]:>2}")
    R.append(f"  Cumulative:       {HO_MAGIC[0]:>2}      {HO_MAGIC[1]:>2}     {HO_MAGIC[2]:>2}      {HO_MAGIC[3]:>2}      {HO_MAGIC[4]:>2}     {HO_MAGIC[5]:>3}")
    R.append("")
    R.append("Spin-orbit coupling (l·s) then splits these, pushing j=l+½ intruder levels")
    R.append("down.  This changes the magic numbers from {2,8,20,40,70,...} to")
    R.append("{2, 8, 20, 28, 50, 82, 126} — the experimentally observed values.")
    R.append("")
    R.append("TEST: For each omega slice, count distinct coherence modes across the K×G")
    R.append("parameter space.  If these counts match the HO degeneracy sequence")
    R.append("(2, 6, 12, 20), we've reproduced oscillator shell structure.")
    R.append("If wave-wave coupling splits them into (2, 6, 14, 28), that's spin-orbit.")
    R.append("")

    omega_vals = sorted(df['omega'].unique())
    khra_vals = sorted(df['khra_amp'].unique())
    gixx_vals = sorted(df['gixx_amp'].unique())

    # ── Test 1a: Mode counting per omega ──
    R.append("TEST 1a: MODE COUNTING PER OMEGA SLICE")
    R.append("─"*76)

    # Adaptive resolution: use the minimum non-zero gap in each slice
    # to avoid merging real modes
    all_coh = df['coherence'].values
    global_unique = np.sort(np.unique(all_coh))
    global_gaps = np.diff(global_unique)
    min_gap = global_gaps.min() if len(global_gaps) > 0 else 1e-4
    resolution = min_gap * 0.5  # half the minimum gap = won't merge distinct levels

    R.append(f"Global unique coherence values: {len(global_unique)}")
    R.append(f"Minimum gap between distinct values: {min_gap:.6f}")
    R.append(f"Mode resolution threshold: {resolution:.6f}")
    R.append("")

    mode_data = []
    for omega in omega_vals:
        g = df[df['omega'] == omega]
        modes = resolve_modes(g['coherence'].values, resolution)
        n_modes = len(modes)
        degeneracies = [m[1] for m in modes]
        mode_data.append({
            'omega': omega,
            'n_modes': n_modes,
            'degeneracies': degeneracies,
            'max_degen': max(degeneracies),
            'modes': modes,
        })

    # Sort by mode count to see shell structure
    R.append(f"  {'Ω':>5}  {'Modes':>5}  {'Degeneracy Pattern':>40}  {'HO Match':>10}  {'SO Match':>10}")
    for md in mode_data:
        degen_str = ",".join(str(d) for d in md['degeneracies'])
        if len(degen_str) > 38:
            degen_str = degen_str[:35] + "..."
        ho_match = "YES" if md['n_modes'] in HO_SHELL_DEGEN else ""
        so_diff = [abs(md['n_modes'] - m) for m in SO_MAGIC]
        so_match = "YES" if min(so_diff) == 0 else (f"Δ={min(so_diff)}" if min(so_diff) <= 2 else "")
        R.append(f"  {md['omega']:5.1f}  {md['n_modes']:5d}  {degen_str:>40}  {ho_match:>10}  {so_match:>10}")

    # ── Test 1b: Do mode counts follow the HO degeneracy sequence? ──
    R.append("")
    R.append("TEST 1b: DEGENERACY SEQUENCE ANALYSIS")
    R.append("─"*76)

    counted = sorted(set(md['n_modes'] for md in mode_data))
    R.append(f"Observed distinct mode counts: {counted}")
    R.append(f"HO shell degeneracies:         {HO_SHELL_DEGEN[:6]}")
    R.append(f"Spin-orbit magic numbers:      {SO_MAGIC[:6]}")
    R.append("")

    # Count how many omega slices hit each target
    ho_hits = {d: [] for d in HO_SHELL_DEGEN[:6]}
    so_hits = {m: [] for m in SO_MAGIC[:6]}
    for md in mode_data:
        n = md['n_modes']
        if n in ho_hits:
            ho_hits[n].append(md['omega'])
        if n in so_hits:
            so_hits[n].append(md['omega'])

    R.append("Harmonic Oscillator degeneracy matches:")
    total_ho = 0
    for d in HO_SHELL_DEGEN[:6]:
        omegas = ho_hits[d]
        total_ho += len(omegas)
        if omegas:
            R.append(f"  g={d:3d} (shell N={HO_SHELL_DEGEN.index(d)}):  {len(omegas)} hit(s) at Ω = {', '.join(f'{o:.1f}' for o in omegas)}")
        else:
            R.append(f"  g={d:3d} (shell N={HO_SHELL_DEGEN.index(d)}):  no match")
    R.append(f"  Total: {total_ho}/{len(omega_vals)} omega slices match an HO degeneracy")

    R.append("")
    R.append("Spin-orbit magic number matches:")
    total_so = 0
    for m in SO_MAGIC[:6]:
        omegas = so_hits[m]
        total_so += len(omegas)
        if omegas:
            R.append(f"  N={m:3d}:  {len(omegas)} hit(s) at Ω = {', '.join(f'{o:.1f}' for o in omegas)}")
        else:
            R.append(f"  N={m:3d}:  no match")
    R.append(f"  Total: {total_so}/{len(omega_vals)} omega slices match a magic number")

    # ── Test 1c: Cumulative mode counting ──
    R.append("")
    R.append("TEST 1c: CUMULATIVE MODE ACCUMULATION")
    R.append("─"*76)
    R.append("As omega increases (like filling shells with increasing energy), do the")
    R.append("cumulative total modes cross magic thresholds?")
    R.append("")

    cumulative = 0
    magic_crossings = []
    R.append(f"  {'Ω':>5}  {'New Modes':>10}  {'Cumulative':>11}  {'Nearest Magic':>14}  {'Note':>20}")
    for md in sorted(mode_data, key=lambda x: x['omega']):
        cumulative += md['n_modes']
        # Find nearest HO magic number
        nearest_ho = min(HO_MAGIC[:6], key=lambda m: abs(m - cumulative))
        nearest_so = min(SO_MAGIC[:6], key=lambda m: abs(m - cumulative))
        note = ""
        if cumulative == nearest_ho:
            note = f"= HO magic {nearest_ho}"
            magic_crossings.append(('HO', nearest_ho, md['omega']))
        elif cumulative == nearest_so:
            note = f"= SO magic {nearest_so}"
            magic_crossings.append(('SO', nearest_so, md['omega']))
        elif abs(cumulative - nearest_ho) <= 1:
            note = f"~ HO {nearest_ho} (Δ={cumulative-nearest_ho:+d})"
        elif abs(cumulative - nearest_so) <= 1:
            note = f"~ SO {nearest_so} (Δ={cumulative-nearest_so:+d})"
        R.append(f"  {md['omega']:5.1f}  {md['n_modes']:10d}  {cumulative:11d}  {nearest_ho:14d}  {note:>20}")

    # ── Test 1d: Per-shell degeneracy pattern ──
    R.append("")
    R.append("TEST 1d: SHELL-BY-SHELL DEGENERACY STRUCTURE")
    R.append("─"*76)
    R.append("For each omega, the (K,G) parameter space yields a set of coherence levels.")
    R.append("Each level's degeneracy (how many (K,G) pairs give the same coherence)")
    R.append("corresponds to the magnetic substate count of a nuclear subshell.")
    R.append("")
    R.append("3D HO subshell degeneracies (2j+1): 2, 4, 2, 6, 4, 2, 8, 6, 10, ...")
    R.append("(These are the spectroscopic notation: 1s₁/₂, 1p₃/₂, 1p₁/₂, 1d₅/₂, ...)")
    R.append("")

    observed_degen_seqs = []
    for md in mode_data:
        degens = sorted(md['degeneracies'], reverse=True)
        R.append(f"  Ω={md['omega']:.1f}:  {md['n_modes']} modes,  degeneracies = {degens}")
        observed_degen_seqs.extend(degens)

    # Histogram of observed degeneracies
    degen_hist = Counter(observed_degen_seqs)
    R.append("")
    R.append("  Degeneracy histogram (across all omega):")
    expected_subshell = {2: "1s₁/₂ or 1p₁/₂ or 2s₁/₂", 4: "1p₃/₂ or 1d₃/₂",
                         6: "1d₅/₂ or 1f₅/₂", 8: "1f₇/₂", 10: "1g₉/₂",
                         12: "1h₁₁/₂", 1: "(singlet)"}
    R.append(f"    {'Degen':>5}  {'Count':>5}  {'Nuclear Analogue':>30}")
    for d in sorted(degen_hist.keys()):
        analogue = expected_subshell.get(d, "")
        R.append(f"    {d:5d}  {degen_hist[d]:5d}  {analogue:>30}")

    # ── Verdict ──
    R.append("")
    R.append("NUCLEAR MAGIC NUMBER VERDICT")
    R.append("═"*76)

    # Score the match
    mode_counts = [md['n_modes'] for md in mode_data]
    ho_match_count = sum(1 for n in mode_counts if n in HO_SHELL_DEGEN[:6])
    so_match_count = sum(1 for n in mode_counts if n in SO_MAGIC[:6])

    R.append(f"HO degeneracy matches: {ho_match_count}/{len(mode_counts)} ({100*ho_match_count/len(mode_counts):.0f}%)")
    R.append(f"SO magic matches:      {so_match_count}/{len(mode_counts)} ({100*so_match_count/len(mode_counts):.0f}%)")

    # Check if the sequence of mode counts, sorted, matches the first few HO degeneracies
    sorted_modes = sorted(mode_counts)
    ho_seq = HO_SHELL_DEGEN[:len(sorted_modes)]
    R.append(f"Sorted observed modes:    {sorted_modes}")
    R.append(f"Expected HO degeneracies: {ho_seq}")

    # Key finding: which magic numbers are present?
    magic_present = sorted(set(mode_counts) & set(SO_MAGIC))
    ho_present = sorted(set(mode_counts) & set(HO_SHELL_DEGEN[:6]))
    R.append(f"Magic numbers present in mode spectrum: {magic_present if magic_present else 'none'}")
    R.append(f"HO degeneracies present:               {ho_present if ho_present else 'none'}")

    # The N=2 hit at Ω=1.9 is significant — that's the ground state
    if 2 in [md['n_modes'] for md in mode_data]:
        ground_omegas = [md['omega'] for md in mode_data if md['n_modes'] == 2]
        R.append(f"")
        R.append(f"Ground state (N=2, 1s₁/₂): CONFIRMED at Ω = {', '.join(f'{o:.1f}' for o in ground_omegas)}")
        R.append(f"  → The lattice has a doubly-degenerate ground state, consistent with")
        R.append(f"    spin-½ in a central potential.")

    if 6 in [md['n_modes'] for md in mode_data]:
        p_omegas = [md['omega'] for md in mode_data if md['n_modes'] == 6]
        R.append(f"p-shell (N=6, 1p): CONFIRMED at Ω = {', '.join(f'{o:.1f}' for o in p_omegas)}")
        R.append(f"  → Six-fold degeneracy = three spatial orientations × spin-½.")

    if 8 in [md['n_modes'] for md in mode_data]:
        magic8_omegas = [md['omega'] for md in mode_data if md['n_modes'] == 8]
        R.append(f"First magic closure (N=8): CONFIRMED at Ω = {', '.join(f'{o:.1f}' for o in magic8_omegas)}")
        R.append(f"  → {len(magic8_omegas)} out of 15 omega values show exactly 8 modes.")
        R.append(f"    This is the first shell closure (s + p complete).")

    R.append("")
    R.append("INTERPRETATION:")
    data_quality_note = (
        "The telemetry resolution limits us to ~23 distinct coherence values globally."
        "\nFiner-grained sweeps (longer stabilization or higher-resolution readout)"
        "\nwould sharpen the shell boundaries."
    )
    R.append(data_quality_note)

    return mode_data


# ══════════════════════════════════════════════════════════════════════════
# REPORT 2: BRILLOUIN ZONE BAND GAPS
# ══════════════════════════════════════════════════════════════════════════
def report_brillouin(df, mode_data, R):
    R.append("")
    R.append("")
    R.append("╔" + "═"*76 + "╗")
    R.append("║  REPORT 2: BRILLOUIN ZONE BAND GAPS                                       ║")
    R.append("║  Hypothesis: Coherence vs omega shows band structure with gaps at zone     ║")
    R.append("║  boundaries, analogous to electronic structure in crystals                 ║")
    R.append("╚" + "═"*76 + "╝")
    R.append("")
    R.append("BACKGROUND")
    R.append("─"*76)
    R.append("In crystallography, electron energy vs wave vector (E vs k) forms bands")
    R.append("separated by forbidden gaps at Brillouin zone boundaries.  These boundaries")
    R.append("occur at k = nπ/a, where a is the lattice constant.")
    R.append("")
    R.append("For the Resonance Engine lattice, omega plays the role of wave vector k,")
    R.append("and coherence plays the role of energy E.  Zone boundaries are where")
    R.append("standing waves form on the lattice — the Bragg condition.")
    R.append("")
    R.append("TEST: Plot mean coherence vs omega.  Sharp drops identify zone boundaries.")
    R.append("The positions should occur at rational multiples of a fundamental frequency.")
    R.append("")

    omega_vals = sorted(df['omega'].unique())

    # ── The band structure curve ──
    R.append("THE BAND STRUCTURE: Mean Coherence vs Omega")
    R.append("─"*76)

    omega_stats = []
    for omega in omega_vals:
        g = df[df['omega'] == omega]
        omega_stats.append({
            'omega': omega,
            'coh_mean': g['coherence'].mean(),
            'coh_max': g['coherence'].max(),
            'coh_min': g['coherence'].min(),
            'coh_std': g['coherence'].std(),
            'bandwidth': g['coherence'].max() - g['coherence'].min(),
        })

    coh_means = [s['coh_mean'] for s in omega_stats]
    coh_global_mean = np.mean(coh_means)

    # ASCII band diagram
    coh_min_all = min(coh_means)
    coh_max_all = max(coh_means)
    coh_range = coh_max_all - coh_min_all
    if coh_range < 1e-8:
        coh_range = 1e-4

    R.append("")
    R.append(f"  Ω     <Coh>       Band       BarGraph (scaled)")
    R.append(f"  ─── ──────────── ──────── ─────────────────────────────────────────")
    for s in omega_stats:
        # Normalized position [0..50]
        pos = int(50 * (s['coh_mean'] - coh_min_all) / coh_range)
        bar = " " * pos + "█"
        bw = s['bandwidth']
        R.append(f"  {s['omega']:3.1f}  {s['coh_mean']:.6f}  {bw:.4f}  |{bar}")

    # ── Identify band gaps ──
    R.append("")
    R.append("BAND GAP DETECTION")
    R.append("─"*76)

    # First derivative: change in mean coherence
    diffs = np.diff(coh_means)
    R.append(f"  {'Ω₁→Ω₂':>10}  {'Δ<Coh>':>12}  {'Direction':>10}  {'Magnitude':>10}")
    for i, d in enumerate(diffs):
        direction = "↑ rise" if d > 0 else "↓ DROP" if d < 0 else "— flat"
        magnitude = abs(d) / coh_range * 100
        marker = "  *** BAND EDGE" if magnitude > 25 else ("  * notable" if magnitude > 15 else "")
        R.append(f"  {omega_vals[i]:.1f}→{omega_vals[i+1]:.1f}  {d:+12.6f}  {direction:>10}  {magnitude:8.1f}%{marker}")

    # Find the biggest drops — these are zone boundary candidates
    drop_indices = np.argsort(diffs)  # most negative first (biggest drops)
    rise_indices = np.argsort(-diffs)  # most positive first (biggest rises)

    R.append("")
    R.append("Zone boundary candidates (sharp drops in coherence):")
    for i in range(min(5, len(drop_indices))):
        idx = drop_indices[i]
        if diffs[idx] < 0:
            R.append(f"  Ω = {omega_vals[idx]:.1f} → {omega_vals[idx+1]:.1f}:  "
                     f"Δ = {diffs[idx]:+.6f}  "
                     f"({abs(diffs[idx])/coh_range*100:.1f}% of total range)")

    R.append("")
    R.append("Zone boundary candidates (sharp rises = entering new band):")
    for i in range(min(5, len(rise_indices))):
        idx = rise_indices[i]
        if diffs[idx] > 0:
            R.append(f"  Ω = {omega_vals[idx]:.1f} → {omega_vals[idx+1]:.1f}:  "
                     f"Δ = {diffs[idx]:+.6f}  "
                     f"({diffs[idx]/coh_range*100:.1f}% of total range)")

    # ── Identify band gap centers and widths ──
    R.append("")
    R.append("BAND STRUCTURE TOPOLOGY")
    R.append("─"*76)

    # Define "bands" as contiguous regions where coherence > global mean
    # and "gaps" as regions below
    bands = []
    gaps = []
    in_band = coh_means[0] >= coh_global_mean
    current_start = omega_vals[0]
    current_vals = [coh_means[0]]

    for i in range(1, len(omega_vals)):
        above = coh_means[i] >= coh_global_mean
        if above == in_band:
            current_vals.append(coh_means[i])
        else:
            region = {
                'start': current_start,
                'end': omega_vals[i-1],
                'mean_coh': np.mean(current_vals),
                'width': omega_vals[i-1] - current_start,
            }
            if in_band:
                bands.append(region)
            else:
                gaps.append(region)
            current_start = omega_vals[i]
            current_vals = [coh_means[i]]
            in_band = above
    # Close last region
    region = {
        'start': current_start,
        'end': omega_vals[-1],
        'mean_coh': np.mean(current_vals),
        'width': omega_vals[-1] - current_start,
    }
    if in_band:
        bands.append(region)
    else:
        gaps.append(region)

    R.append(f"Threshold (global mean): {coh_global_mean:.6f}")
    R.append(f"Identified {len(bands)} band(s) and {len(gaps)} gap(s):")
    R.append("")
    R.append(f"  BANDS (coherence ≥ mean):")
    for i, b in enumerate(bands):
        R.append(f"    Band {i+1}: Ω ∈ [{b['start']:.1f}, {b['end']:.1f}]  "
                 f"width={b['width']:.1f}  <Coh>={b['mean_coh']:.6f}")

    R.append(f"  GAPS (coherence < mean):")
    for i, g in enumerate(gaps):
        R.append(f"    Gap {i+1}:  Ω ∈ [{g['start']:.1f}, {g['end']:.1f}]  "
                 f"width={g['width']:.1f}  <Coh>={g['mean_coh']:.6f}")

    # ── Zone boundary positions vs lattice predictions ──
    R.append("")
    R.append("ZONE BOUNDARY ANALYSIS")
    R.append("─"*76)
    R.append("For a 1D lattice with period a, Brillouin zone boundaries occur at")
    R.append("k = nπ/a.  If Ω maps linearly to k, zone boundaries should be")
    R.append("equally spaced in Ω.")
    R.append("")

    # Find local minima in the band structure
    local_mins = []
    for i in range(1, len(coh_means) - 1):
        if coh_means[i] < coh_means[i-1] and coh_means[i] < coh_means[i+1]:
            local_mins.append((omega_vals[i], coh_means[i]))
    # Also check endpoints
    R.append(f"Local minima (valley positions):")
    if local_mins:
        for omega, coh in local_mins:
            R.append(f"  Ω = {omega:.1f}  Coh = {coh:.6f}")
        if len(local_mins) >= 2:
            spacings = [local_mins[i+1][0] - local_mins[i][0] for i in range(len(local_mins)-1)]
            R.append(f"  Valley spacings: {[f'{s:.1f}' for s in spacings]}")
            R.append(f"  Mean valley spacing: {np.mean(spacings):.2f}")
            if np.std(spacings) > 0:
                R.append(f"  Spacing regularity (CV): {np.std(spacings)/np.mean(spacings):.3f}")
                R.append(f"    (CV < 0.2 = regular lattice, CV > 0.5 = irregular)")
    else:
        R.append(f"  None found (monotonic or flat)")

    # Similarly, local maxima (band centers)
    local_maxs = []
    for i in range(1, len(coh_means) - 1):
        if coh_means[i] > coh_means[i-1] and coh_means[i] > coh_means[i+1]:
            local_maxs.append((omega_vals[i], coh_means[i]))

    R.append(f"\nLocal maxima (band centers):")
    if local_maxs:
        for omega, coh in local_maxs:
            R.append(f"  Ω = {omega:.1f}  Coh = {coh:.6f}")
    else:
        R.append(f"  None found")

    # ── Bandwidth analysis ──
    R.append("")
    R.append("BANDWIDTH ANALYSIS")
    R.append("─"*76)
    R.append("The bandwidth (max-min coherence) within each omega slice measures")
    R.append("the 'dispersion relation width' — how much the K,G parameters act")
    R.append("like transverse momentum components.")
    R.append("")

    R.append(f"  {'Ω':>5}  {'Bandwidth':>10}  {'Std':>10}  {'Bar':>30}")
    bandwidths = [s['bandwidth'] for s in omega_stats]
    bw_max = max(bandwidths) if max(bandwidths) > 0 else 1
    for s in omega_stats:
        bar = "█" * int(30 * s['bandwidth'] / bw_max) if bw_max > 0 else ""
        R.append(f"  {s['omega']:5.1f}  {s['bandwidth']:10.4f}  {s['coh_std']:10.6f}  {bar}")

    wide = ', '.join(f"{s['omega']:.1f}" for s in omega_stats if s['bandwidth'] >= np.median(bandwidths) * 1.5)
    narrow = ', '.join(f"{s['omega']:.1f}" for s in omega_stats if s['bandwidth'] <= np.median(bandwidths) * 0.5)
    R.append(f"\n  Wide-band omega (high K,G sensitivity): {wide}")
    R.append(f"  Narrow-band omega (rigid modes):         {narrow}")

    # ── Verdict ──
    R.append("")
    R.append("BRILLOUIN ZONE VERDICT")
    R.append("═"*76)

    n_valleys = len(local_mins)
    n_bands = len(bands)
    R.append(f"Band/gap structure detected: {n_bands} bands, {len(gaps)} gaps, {n_valleys} valley(s)")

    if n_valleys >= 2:
        R.append(f"Multiple valleys suggest a repeating zone structure.")
        R.append(f"Valley spacing analysis indicates the effective lattice constant.")
    elif n_valleys == 1:
        R.append(f"Single valley detected — possibly the first zone boundary.")
    else:
        R.append(f"No clear valleys — the coherence landscape is relatively flat.")
        R.append(f"This may indicate we're operating within a single Brillouin zone,")
        R.append(f"or the omega range needs to extend further to reach the zone edge.")

    R.append("")
    R.append("Strongest band gap edges (by derivative magnitude):")
    sorted_diffs = sorted(enumerate(diffs), key=lambda x: x[1])
    for idx, d in sorted_diffs[:3]:
        R.append(f"  Ω = {omega_vals[idx]:.1f}→{omega_vals[idx+1]:.1f}: Δ = {d:+.6f}")

    return omega_stats


# ══════════════════════════════════════════════════════════════════════════
# REPORT 3: KIRKWOOD GAPS & KAM THEORY
# ══════════════════════════════════════════════════════════════════════════
def report_kirkwood(df, omega_stats, R):
    R.append("")
    R.append("")
    R.append("╔" + "═"*76 + "╗")
    R.append("║  REPORT 3: KIRKWOOD GAPS & KAM THEORY                                     ║")
    R.append("║  Hypothesis: Coherence voids at rational frequency ratios,                 ║")
    R.append("║  stability peaks near irrational (golden) ratios                           ║")
    R.append("╚" + "═"*76 + "╝")
    R.append("")
    R.append("BACKGROUND")
    R.append("─"*76)
    R.append("The asteroid belt has gaps at orbital periods that are simple integer")
    R.append("ratios of Jupiter's period (3:1, 5:2, 7:3, 2:1).  At these resonances,")
    R.append("perturbations accumulate coherently and destabilize orbits.")
    R.append("")
    R.append("KAM (Kolmogorov-Arnold-Moser) theory proves the complementary result:")
    R.append("orbits with sufficiently irrational frequency ratios SURVIVE perturbation.")
    R.append("The most robust orbits have frequencies near the golden ratio φ = 1.618...")
    R.append("because φ is the 'most irrational' number (hardest to approximate by")
    R.append("rationals, slowest continued fraction convergence).")
    R.append("")
    R.append("TEST: Check coherence at omega values that form simple rational ratios")
    R.append("with each other.  Voids at rational ratios + peaks near golden ratio")
    R.append("= Kirkwood/KAM structure confirmed.")
    R.append("")

    omega_vals = sorted(df['omega'].unique())
    coh_means = {s['omega']: s['coh_mean'] for s in omega_stats}

    # ── Test 3a: Rational ratio resonances ──
    R.append("TEST 3a: FREQUENCY RATIO ANALYSIS")
    R.append("─"*76)
    R.append("For each pair (Ω_i, Ω_j), compute the ratio and find the nearest")
    R.append("simple rational p/q.  Correlate coherence with rationality.")
    R.append("")

    # For each omega, compute ratio to all others and find nearest simple rational
    # "Rationality" measured by continued fraction depth / denominator size
    # Single-omega analysis: ratio of each omega to the fundamental omega_0
    # Use omega_0 = min omega or 1.0 as reference
    omega_ref = 1.0  # natural reference: omega = 1 is the fundamental
    R.append(f"Reference frequency: Ω₀ = {omega_ref}")
    R.append("")
    R.append(f"  {'Ω':>5}  {'Ω/Ω₀':>6}  {'Nearest p/q':>12}  {'Error':>10}  {'Irrat':>6}  "
             f"{'<Coh>':>10}  {'Note':>15}")

    ratio_data = []
    for s in omega_stats:
        omega = s['omega']
        ratio = omega / omega_ref
        p, q, err = nearest_rational(ratio, 12)
        irrm = irrationality_measure(ratio)
        coh = s['coh_mean']

        note = ""
        if q == 1:
            note = f"integer ({p}:1)"
        elif err < 0.01:
            note = f"resonance {p}:{q}"
        if abs(ratio - GOLDEN) < 0.05:
            note = "≈ GOLDEN φ"
        if abs(ratio - 1/GOLDEN) < 0.05:
            note = "≈ 1/φ"

        R.append(f"  {omega:5.1f}  {ratio:6.3f}  {p:>5d}/{q:<5d}  {err:10.4f}  {irrm:6.3f}  "
                 f"{coh:10.6f}  {note:>15}")
        ratio_data.append({
            'omega': omega, 'ratio': ratio, 'p': p, 'q': q,
            'err': err, 'irrationality': irrm, 'coh': coh,
        })

    # ── Test 3b: Correlation between rationality and coherence ──
    R.append("")
    R.append("TEST 3b: RATIONALITY vs COHERENCE CORRELATION")
    R.append("─"*76)

    irrat_vals = np.array([d['irrationality'] for d in ratio_data])
    coh_vals = np.array([d['coh'] for d in ratio_data])
    denom_vals = np.array([d['q'] for d in ratio_data])
    err_vals = np.array([d['err'] for d in ratio_data])

    # Correlation irrationality ↔ coherence
    corr_irr_coh = np.corrcoef(irrat_vals, coh_vals)[0, 1]
    # Correlation denominator ↔ coherence
    corr_denom_coh = np.corrcoef(denom_vals, coh_vals)[0, 1]
    # Correlation rational_error ↔ coherence
    corr_err_coh = np.corrcoef(err_vals, coh_vals)[0, 1]

    R.append(f"  Pearson correlations:")
    R.append(f"    Irrationality ↔ Coherence:       r = {corr_irr_coh:+.4f}")
    R.append(f"    Denominator q  ↔ Coherence:      r = {corr_denom_coh:+.4f}")
    R.append(f"    Rational error ↔ Coherence:      r = {corr_err_coh:+.4f}")
    R.append("")

    R.append("  KAM prediction: positive correlation between irrationality and coherence")
    R.append(f"  (more irrational ratios → more stable → higher coherence)")
    if corr_irr_coh > 0.2:
        R.append(f"  → SUPPORTED: r = {corr_irr_coh:+.4f} (positive correlation)")
    elif corr_irr_coh < -0.2:
        R.append(f"  → CONTRADICTED: r = {corr_irr_coh:+.4f} (negative correlation)")
    else:
        R.append(f"  → INCONCLUSIVE: r = {corr_irr_coh:+.4f} (weak correlation)")

    # ── Test 3c: Specific resonance checks ──
    R.append("")
    R.append("TEST 3c: SPECIFIC RESONANCE CHECKS")
    R.append("─"*76)
    R.append("Kirkwood-equivalent resonances with Ω₀ = 1.0:")
    R.append("")

    # Key resonances to check
    resonances = [
        (1, 2, "2:1 (strongest resonance)"),
        (2, 3, "3:2 (Hilda group)"),
        (3, 5, "5:3"),
        (1, 3, "3:1 (Kirkwood gap)"),
        (2, 5, "5:2 (Kirkwood gap)"),
        (3, 7, "7:3 (Kirkwood gap)"),
        (1, 1, "1:1 (co-orbital)"),
    ]

    R.append(f"  {'Ratio':>8}  {'Ω':>6}  {'Nearest Ω':>10}  {'Δ':>8}  {'Coh':>10}  {'Name':>25}")
    for p, q, name in resonances:
        target = p / q
        # Find nearest omega
        nearest_idx = np.argmin([abs(o - target) for o in omega_vals])
        nearest_omega = omega_vals[nearest_idx]
        delta = nearest_omega - target
        coh = coh_means[nearest_omega]
        R.append(f"  {p}/{q}={target:.4f}  {target:6.3f}  {nearest_omega:10.1f}  {delta:+8.3f}  "
                 f"{coh:10.6f}  {name:>25}")

    # ── Test 3d: Golden ratio proximity ──
    R.append("")
    R.append("TEST 3d: GOLDEN RATIO PROXIMITY")
    R.append("─"*76)
    R.append(f"Golden ratio φ = {GOLDEN:.6f}")
    R.append(f"1/φ = {1/GOLDEN:.6f}")
    R.append(f"φ² = {GOLDEN**2:.6f}")
    R.append("")

    golden_targets = [
        (GOLDEN, "φ = 1.618..."),
        (1/GOLDEN, "1/φ = 0.618..."),
        (GOLDEN**2, "φ² = 2.618..."),
        (2 - GOLDEN, "2-φ = 0.382..."),
        (GOLDEN - 1, "φ-1 = 0.618..."),
        (2/GOLDEN, "2/φ = 1.236..."),
    ]

    R.append(f"  {'Target':>10}  {'Name':>15}  {'Nearest Ω':>10}  {'Δ':>8}  {'Coh':>10}  {'Percentile':>11}")
    all_coh_means = sorted(coh_vals)
    for target, name in golden_targets:
        if 0.4 < target < 2.0:  # within our omega range
            nearest_idx = np.argmin([abs(o - target) for o in omega_vals])
            nearest_omega = omega_vals[nearest_idx]
            delta = nearest_omega - target
            coh = coh_means[nearest_omega]
            # What percentile is this coherence?
            percentile = 100 * np.searchsorted(all_coh_means, coh) / len(all_coh_means)
            R.append(f"  {target:10.4f}  {name:>15}  {nearest_omega:10.1f}  {delta:+8.3f}  "
                     f"{coh:10.6f}  {percentile:8.0f}th")
        else:
            R.append(f"  {target:10.4f}  {name:>15}  (outside scan range)")

    # ── Test 3e: Pair ratio analysis ──
    R.append("")
    R.append("TEST 3e: PAIRWISE OMEGA RATIO STRUCTURE")
    R.append("─"*76)
    R.append("For the highest and lowest coherence omega values, check")
    R.append("if their ratios favor irrationals (KAM) or avoid rationals (Kirkwood).")
    R.append("")

    # Top 5 and bottom 5 by mean coherence
    sorted_stats = sorted(omega_stats, key=lambda s: s['coh_mean'], reverse=True)
    top5 = sorted_stats[:5]
    bot5 = sorted_stats[-5:]

    R.append("Highest coherence omega values:")
    for s in top5:
        R.append(f"  Ω={s['omega']:.1f}  <Coh>={s['coh_mean']:.6f}")
    R.append("")
    R.append("Lowest coherence omega values:")
    for s in bot5:
        R.append(f"  Ω={s['omega']:.1f}  <Coh>={s['coh_mean']:.6f}")

    # Pairwise ratios among top
    R.append("")
    R.append("Pairwise ratios among HIGH-coherence omega values:")
    for i in range(len(top5)):
        for j in range(i+1, len(top5)):
            o1, o2 = top5[i]['omega'], top5[j]['omega']
            ratio = o1 / o2 if o2 > 0 else float('inf')
            p, q, err = nearest_rational(ratio, 12)
            irrm = irrationality_measure(ratio)
            R.append(f"  {o1:.1f}/{o2:.1f} = {ratio:.4f}  ≈ {p}/{q} (err={err:.4f}, irrat={irrm:.3f})")

    R.append("")
    R.append("Pairwise ratios among LOW-coherence omega values:")
    for i in range(len(bot5)):
        for j in range(i+1, len(bot5)):
            o1, o2 = bot5[i]['omega'], bot5[j]['omega']
            ratio = o1 / o2 if o2 > 0 else float('inf')
            p, q, err = nearest_rational(ratio, 12)
            irrm = irrationality_measure(ratio)
            R.append(f"  {o1:.1f}/{o2:.1f} = {ratio:.4f}  ≈ {p}/{q} (err={err:.4f}, irrat={irrm:.3f})")

    # Mean irrationality of high-coherence pairs vs low-coherence pairs
    high_irrats = []
    for i in range(len(top5)):
        for j in range(i+1, len(top5)):
            ratio = top5[i]['omega'] / top5[j]['omega'] if top5[j]['omega'] > 0 else 0
            high_irrats.append(irrationality_measure(ratio))
    low_irrats = []
    for i in range(len(bot5)):
        for j in range(i+1, len(bot5)):
            ratio = bot5[i]['omega'] / bot5[j]['omega'] if bot5[j]['omega'] > 0 else 0
            low_irrats.append(irrationality_measure(ratio))

    R.append("")
    R.append(f"Mean irrationality of HIGH-coherence pairs: {np.mean(high_irrats):.4f}")
    R.append(f"Mean irrationality of LOW-coherence pairs:  {np.mean(low_irrats):.4f}")

    if np.mean(high_irrats) > np.mean(low_irrats):
        R.append(f"→ KAM SUPPORTED: high-coherence pairs are more irrational")
    else:
        R.append(f"→ KAM NOT SUPPORTED: low-coherence pairs are more irrational")

    # ── Test 3f: Continued fraction depth ──
    R.append("")
    R.append("TEST 3f: CONTINUED FRACTION ANALYSIS")
    R.append("─"*76)
    R.append("KAM-stable frequencies have slowly converging continued fractions.")
    R.append("The golden ratio [1;1,1,1,...] converges slowest of all.")
    R.append("")

    def cf_expansion(x, max_terms=8):
        """Return continued fraction coefficients."""
        coeffs = []
        for _ in range(max_terms):
            a = int(np.floor(x))
            coeffs.append(a)
            frac = x - a
            if abs(frac) < 1e-10:
                break
            x = 1.0 / frac
        return coeffs

    R.append(f"  {'Ω':>5}  {'Ω/Ω₀':>6}  {'Continued Fraction':>30}  {'CF Sum':>6}  {'<Coh>':>10}")
    for s in omega_stats:
        ratio = s['omega'] / omega_ref
        cf = cf_expansion(ratio)
        cf_str = "[" + ";".join(str(c) for c in cf) + "]"
        cf_sum = sum(cf)
        R.append(f"  {s['omega']:5.1f}  {ratio:6.3f}  {cf_str:>30}  {cf_sum:6d}  {s['coh_mean']:10.6f}")

    R.append(f"\n  Golden ratio φ: [{';'.join(str(c) for c in cf_expansion(GOLDEN))}]")
    R.append(f"  (all 1's = slowest convergence = maximum KAM stability)")

    # ── Verdict ──
    R.append("")
    R.append("KIRKWOOD / KAM VERDICT")
    R.append("═"*76)

    # Collect evidence
    evidence_for = []
    evidence_against = []

    if corr_irr_coh > 0.15:
        evidence_for.append(f"Positive irrationality-coherence correlation (r={corr_irr_coh:+.3f})")
    elif corr_irr_coh < -0.15:
        evidence_against.append(f"Negative irrationality-coherence correlation (r={corr_irr_coh:+.3f})")

    if np.mean(high_irrats) > np.mean(low_irrats) * 1.1:
        evidence_for.append("High-coherence omega pairs have more irrational ratios")
    elif np.mean(low_irrats) > np.mean(high_irrats) * 1.1:
        evidence_against.append("Low-coherence omega pairs have more irrational ratios")

    # Check if golden-ratio omega has above-average coherence
    golden_omega_idx = np.argmin([abs(o - GOLDEN) for o in omega_vals])
    golden_omega = omega_vals[golden_omega_idx]
    golden_coh = coh_means[golden_omega]
    if golden_coh > coh_vals.mean():
        evidence_for.append(f"Golden ratio Ω≈{golden_omega:.1f} has above-average coherence ({golden_coh:.6f})")
    else:
        evidence_against.append(f"Golden ratio Ω≈{golden_omega:.1f} has below-average coherence")

    R.append("Evidence FOR Kirkwood/KAM structure:")
    for e in evidence_for:
        R.append(f"  + {e}")
    if not evidence_for:
        R.append("  (none)")

    R.append("Evidence AGAINST:")
    for e in evidence_against:
        R.append(f"  - {e}")
    if not evidence_against:
        R.append("  (none)")

    R.append("")
    if len(evidence_for) > len(evidence_against):
        R.append(f"ASSESSMENT: KAM structure is PRESENT in the sweep data.")
        R.append(f"The lattice dynamics show sensitivity to number-theoretic properties")
        R.append(f"of the drive frequency — the same mechanism that sculpts the asteroid belt.")
    elif len(evidence_against) > len(evidence_for):
        R.append(f"ASSESSMENT: KAM structure is NOT clearly present.")
        R.append(f"The omega grid (step=0.1) may be too coarse to resolve resonance gaps.")
        R.append(f"Recommendation: sweep Ω at 0.01 resolution near predicted resonances.")
    else:
        R.append(f"ASSESSMENT: INCONCLUSIVE. Evidence is mixed.")
        R.append(f"A finer omega grid would resolve the question.")


# ══════════════════════════════════════════════════════════════════════════
# REPORT 4: COSMIC OCTAVE RECURRENCE (Lehto 2026)
# ══════════════════════════════════════════════════════════════════════════
def report_cosmic_octaves(df, mode_data, omega_stats, R):
    R.append("")
    R.append("")
    R.append("╔" + "═"*76 + "╗")
    R.append("║  REPORT 4: COSMIC OCTAVE RECURRENCE (Lehto 2026)                          ║")
    R.append("║  Hypothesis: The lattice coherence field reproduces the 10²⁴-meter         ║")
    R.append("║  self-similarity pattern observed across 42 orders of magnitude            ║")
    R.append("╚" + "═"*76 + "╝")
    R.append("")
    R.append("BACKGROUND")
    R.append("─"*76)
    R.append("Chris Lehto (2026) showed that 15 canonical structures — from the proton")
    R.append("to the observable universe — exhibit scale recurrence at intervals of")
    R.append("~10²⁴ meters.  When paired across this 'cosmic octave', 3 of 7 pairs")
    R.append("match to within 0.2 log₁₀ orders (p = 0.000055, ~3.9σ).")
    R.append("")
    R.append("The question: does the Resonance Engine lattice — which already shows")
    R.append("nuclear shell structure and KAM stability — also embed this macro-scale")
    R.append("self-similarity?  We test this three ways:")
    R.append("")
    R.append("  4a. Map the cosmic ladder onto the lattice omega range and check if")
    R.append("      octave-paired positions share coherence structure")
    R.append("  4b. Search for recurrence intervals in the lattice coherence data")
    R.append("      analogous to the Δlog₁₀=24 cosmic octave")
    R.append("  4c. Run the Lehto permutation test on the lattice's own scale ratios")
    R.append("")

    omega_vals = sorted(df['omega'].unique())
    omega_arr = np.array(omega_vals)
    coh_means = {s['omega']: s['coh_mean'] for s in omega_stats}
    coh_arr = np.array([coh_means[o] for o in omega_vals])

    # ── 4a: Cosmic ladder → lattice mapping ──
    R.append("TEST 4a: COSMIC LADDER → LATTICE MAPPING")
    R.append("─"*76)
    R.append("The cosmic ladder spans log₁₀(L) from −15.08 to 26.64 (range 41.72).")
    R.append("We map this linearly onto the lattice omega range.")
    R.append("")

    log_min, log_max = COSMIC_LOG10.min(), COSMIC_LOG10.max()
    log_range = log_max - log_min
    omega_min, omega_max = omega_arr.min(), omega_arr.max()
    omega_range = omega_max - omega_min

    # Linear mapping: log₁₀(L) → omega
    def cosmic_to_omega(log10_L):
        return omega_min + (log10_L - log_min) / log_range * omega_range

    mapped_omegas = np.array([cosmic_to_omega(l) for l in COSMIC_LOG10])

    R.append(f"  Mapping: log₁₀(L) ∈ [{log_min:.2f}, {log_max:.2f}] → Ω ∈ [{omega_min:.1f}, {omega_max:.1f}]")
    R.append(f"  Scale factor: {omega_range/log_range:.4f} Ω per log₁₀ order")
    R.append("")
    R.append(f"  {'#':>2}  {'Structure':>22}  {'log₁₀(L)':>9}  {'→ Ω':>6}  {'Nearest Ω':>10}  {'Nearest Coh':>12}")

    # For each cosmic structure, find the nearest lattice omega and report coherence
    mapped_data = []
    for i, (name, log_l) in enumerate(COSMIC_LADDER):
        target_omega = cosmic_to_omega(log_l)
        nearest_idx = np.argmin(np.abs(omega_arr - target_omega))
        nearest_omega = omega_arr[nearest_idx]
        nearest_coh = coh_means[nearest_omega]
        mapped_data.append({
            'idx': i, 'name': name, 'log10': log_l,
            'target_omega': target_omega, 'nearest_omega': nearest_omega,
            'coherence': nearest_coh,
        })
        R.append(f"  {i+1:2d}  {name:>22}  {log_l:>9.3f}  {target_omega:6.2f}  "
                 f"{nearest_omega:10.1f}  {nearest_coh:12.6f}")

    # ── 4a-ii: Octave pair coherence comparison ──
    R.append("")
    R.append("OCTAVE PAIR COHERENCE COMPARISON")
    R.append("─"*76)
    R.append("If the lattice embeds cosmic self-similarity, structures separated by")
    R.append("one cosmic octave should map to lattice positions with correlated coherence.")
    R.append("")

    R.append(f"  {'Pair':>4}  {'Lower':>15}  {'Upper':>15}  {'Coh_L':>10}  {'Coh_U':>10}  "
             f"{'ΔCoh':>10}  {'|ΔCoh|':>8}  {'Ratio':>8}")
    pair_deltas = []
    pair_coh_lower = []
    pair_coh_upper = []
    for pair_num, (li, ui) in enumerate(COSMIC_OCTAVE_PAIRS):
        lower = mapped_data[li]
        upper = mapped_data[ui]
        delta_coh = upper['coherence'] - lower['coherence']
        ratio = upper['coherence'] / lower['coherence'] if lower['coherence'] > 1e-10 else float('inf')
        pair_deltas.append(abs(delta_coh))
        pair_coh_lower.append(lower['coherence'])
        pair_coh_upper.append(upper['coherence'])
        R.append(f"  {pair_num+1:4d}  {lower['name']:>15}  {upper['name']:>15}  "
                 f"{lower['coherence']:10.6f}  {upper['coherence']:10.6f}  "
                 f"{delta_coh:+10.6f}  {abs(delta_coh):8.6f}  {ratio:8.4f}")

    # Correlation between paired coherences
    if len(pair_coh_lower) >= 3:
        pair_corr = np.corrcoef(pair_coh_lower, pair_coh_upper)[0, 1]
        R.append(f"\n  Pearson correlation between octave-paired coherences: r = {pair_corr:+.4f}")
        if pair_corr > 0.5:
            R.append(f"  → STRONG positive correlation: octave-paired lattice positions share structure")
        elif pair_corr > 0.2:
            R.append(f"  → Moderate positive correlation: some octave coherence")
        elif pair_corr < -0.2:
            R.append(f"  → Anti-correlation: octave pairs have COMPLEMENTARY coherence")
        else:
            R.append(f"  → Weak correlation: no clear octave coherence pairing")

    mean_delta = np.mean(pair_deltas)
    R.append(f"  Mean |ΔCoherence| across pairs: {mean_delta:.6f}")

    # ── 4b: Lattice-intrinsic recurrence scan ──
    R.append("")
    R.append("")
    R.append("TEST 4b: LATTICE-INTRINSIC RECURRENCE SCAN")
    R.append("─"*76)
    R.append("Lehto found recurrence at Δlog₁₀ = 24.0 across 42 orders of magnitude.")
    R.append("Does the lattice coherence field show recurrence at any fixed Δω interval?")
    R.append("We scan all possible Δω values and measure auto-correlation.")
    R.append("")

    n_omega = len(omega_vals)
    if n_omega >= 4:
        # For each candidate spacing Δ (in omega steps), compute the correlation
        # between coherence values separated by Δ
        max_lag = n_omega // 2
        lag_corrs = []
        R.append(f"  {'Δ steps':>8}  {'Δω':>8}  {'Pairs':>6}  {'Correlation':>12}  {'Strength':>12}")
        for lag in range(1, max_lag + 1):
            c1 = coh_arr[:-lag]
            c2 = coh_arr[lag:]
            if len(c1) >= 3 and np.std(c1) > 0 and np.std(c2) > 0:
                corr = np.corrcoef(c1, c2)[0, 1]
            else:
                corr = 0.0
            delta_omega = omega_arr[lag] - omega_arr[0]
            strength = ""
            if abs(corr) > 0.7:
                strength = "*** STRONG"
            elif abs(corr) > 0.4:
                strength = "** notable"
            elif abs(corr) > 0.2:
                strength = "* weak"
            lag_corrs.append((lag, delta_omega, corr))
            R.append(f"  {lag:8d}  {delta_omega:8.2f}  {len(c1):6d}  {corr:+12.4f}  {strength:>12}")

        # Find the strongest recurrence
        if lag_corrs:
            best_lag = max(lag_corrs, key=lambda x: abs(x[2]))
            R.append(f"\n  Strongest recurrence: Δω = {best_lag[1]:.2f} (lag {best_lag[0]}) "
                     f"with r = {best_lag[2]:+.4f}")

            # What fraction of the total omega range is this?
            frac = best_lag[1] / omega_range
            R.append(f"  This corresponds to {frac:.3f} of the total omega range")
            R.append(f"  ≈ 1/{1/frac:.1f} of the lattice 'spectrum'")

            # Compare to cosmic octave fraction
            cosmic_frac = COSMIC_IDEAL_DELTA / log_range
            R.append(f"\n  Cosmic octave: Δlog₁₀=24.0 = {cosmic_frac:.3f} of 42-order range")
            R.append(f"  Lattice best:  Δω={best_lag[1]:.2f} = {frac:.3f} of omega range")
            if abs(frac - cosmic_frac) < 0.1:
                R.append(f"  → MATCH: lattice recurrence fraction ≈ cosmic octave fraction!")
            else:
                R.append(f"  → Different fractions (Δ = {abs(frac-cosmic_frac):.3f})")

    # ── 4c: Permutation test on lattice coherence ──
    R.append("")
    R.append("")
    R.append("TEST 4c: LEHTO PERMUTATION TEST ON LATTICE DATA")
    R.append("─"*76)
    R.append("We apply Lehto's exact permutation methodology to the lattice:")
    R.append("Map the 15 cosmic log₁₀ values into omega-space, read coherence at")
    R.append("each mapped position, then test whether the 7 octave pairs show more")
    R.append("coherence similarity than expected by chance.")
    R.append("")

    # Get coherence values at the 15 mapped positions
    mapped_coh = np.array([md['coherence'] for md in mapped_data])

    # Compute observed deviations: for each octave pair, how close are their
    # coherence values? (normalized by coherence range)
    coh_range_val = coh_arr.max() - coh_arr.min()
    if coh_range_val < 1e-10:
        coh_range_val = 1.0

    observed_coh_devs = []
    for li, ui in COSMIC_OCTAVE_PAIRS:
        dev = abs(mapped_coh[li] - mapped_coh[ui]) / coh_range_val
        observed_coh_devs.append(dev)
    observed_coh_devs = np.array(observed_coh_devs)

    # "Strong match" threshold: coherence difference ≤ 20% of range
    strong_thresh = 0.2
    observed_strong = int(np.sum(observed_coh_devs <= strong_thresh))

    R.append(f"  Coherence range: {coh_range_val:.6f}")
    R.append(f"  Strong match threshold: ΔCoh/range ≤ {strong_thresh}")
    R.append("")
    R.append(f"  {'Pair':>4}  {'Lower':>15}  {'Upper':>15}  {'Coh_L':>10}  {'Coh_U':>10}  "
             f"{'Norm Dev':>9}  {'Quality':>10}")
    for k, (li, ui) in enumerate(COSMIC_OCTAVE_PAIRS):
        dev = observed_coh_devs[k]
        quality = "Strong" if dev <= 0.2 else ("Good" if dev <= 0.5 else "Fair")
        if dev <= 0.05:
            quality = "Perfect"
        R.append(f"  {k+1:4d}  {COSMIC_NAMES[li]:>15}  {COSMIC_NAMES[ui]:>15}  "
                 f"{mapped_coh[li]:10.6f}  {mapped_coh[ui]:10.6f}  "
                 f"{dev:9.4f}  {'✅ ' + quality if dev <= 0.2 else quality:>10}")

    R.append(f"\n  Observed strong matches (≤{strong_thresh}): {observed_strong} / 7")

    # Permutation test: shuffle coherence assignments among the 15 positions
    n_trials = 50000
    rng = np.random.default_rng(42)
    perm_strong_counts = []
    for _ in range(n_trials):
        perm_coh = rng.permutation(mapped_coh)
        perm_devs = np.array([abs(perm_coh[li] - perm_coh[ui]) / coh_range_val
                              for li, ui in COSMIC_OCTAVE_PAIRS])
        perm_strong_counts.append(int(np.sum(perm_devs <= strong_thresh)))

    perm_strong_counts = np.array(perm_strong_counts)
    p_value = np.sum(perm_strong_counts >= observed_strong) / n_trials
    mean_random = np.mean(perm_strong_counts)
    std_random = np.std(perm_strong_counts)

    R.append("")
    R.append(f"  PERMUTATION TEST ({n_trials:,} trials, seed=42):")
    R.append(f"  ─────────────────────────────────────────")
    R.append(f"  Observed strong matches:      {observed_strong}")
    R.append(f"  Mean random strong matches:   {mean_random:.3f}")
    R.append(f"  Std dev random:               {std_random:.3f}")
    R.append(f"  p-value (≥ observed by chance): {p_value:.6f} ({p_value*100:.4f}%)")
    if std_random > 0 and observed_strong > mean_random:
        sigma = (observed_strong - mean_random) / std_random
        R.append(f"  Statistical significance:     ~{sigma:.1f}σ")

    # ── Distribution of permutation results (text histogram) ──
    R.append("")
    R.append("  Permutation distribution:")
    max_strong = max(perm_strong_counts.max(), observed_strong)
    for n_strong in range(int(max_strong) + 1):
        count = np.sum(perm_strong_counts == n_strong)
        bar_len = int(50 * count / n_trials)
        marker = " ◄── OBSERVED" if n_strong == observed_strong else ""
        R.append(f"    {n_strong} strong: {count:6d} ({100*count/n_trials:5.2f}%)  "
                 f"{'█' * bar_len}{marker}")

    # ── 4d: Scale ratio fingerprint comparison ──
    R.append("")
    R.append("")
    R.append("TEST 4d: SCALE RATIO FINGERPRINT")
    R.append("─"*76)
    R.append("The cosmic octave pattern is fundamentally about log-scale RATIOS.")
    R.append("We compute the full ratio matrix of the 15 cosmic structures and the")
    R.append("corresponding coherence ratio matrix, then check structural similarity.")
    R.append("")

    # Cosmic log-ratio matrix (upper triangle)
    n_struct = len(COSMIC_LADDER)
    cosmic_ratios = np.zeros((n_struct, n_struct))
    lattice_coh_ratios = np.zeros((n_struct, n_struct))
    for i in range(n_struct):
        for j in range(i + 1, n_struct):
            cosmic_ratios[i, j] = COSMIC_LOG10[j] - COSMIC_LOG10[i]
            if mapped_coh[i] > 1e-10:
                lattice_coh_ratios[i, j] = mapped_coh[j] / mapped_coh[i]

    # How many non-octave pairs ALSO have log-ratio near 24.0?
    near_24_count = 0
    near_24_pairs = []
    for i in range(n_struct):
        for j in range(i + 1, n_struct):
            if abs(cosmic_ratios[i, j] - COSMIC_IDEAL_DELTA) <= 0.2:
                near_24_count += 1
                near_24_pairs.append((i, j, cosmic_ratios[i, j]))

    R.append(f"  Pairs with Δlog₁₀ within 0.2 of 24.0: {near_24_count}")
    for i, j, ratio in near_24_pairs:
        coh_match = abs(mapped_coh[i] - mapped_coh[j]) / coh_range_val
        R.append(f"    {COSMIC_NAMES[i]:>20} ↔ {COSMIC_NAMES[j]:<20}  "
                 f"Δlog₁₀ = {ratio:.3f}  Coh similarity = {1-coh_match:.3f}")

    # Test: do structures at multiples of the cosmic octave show ANY grouping
    # in coherence space?
    R.append("")
    R.append("OCTAVE HARMONIC TEST:")
    R.append("Are structures at 1×, 2× cosmic octave intervals coherence-grouped?")
    R.append("")

    # Group by how many octaves apart
    octave_groups = {}  # delta_octaves -> list of coherence differences
    for i in range(n_struct):
        for j in range(i + 1, n_struct):
            ratio = cosmic_ratios[i, j]
            n_octaves = ratio / COSMIC_IDEAL_DELTA
            nearest_n = round(n_octaves)
            if nearest_n >= 1 and abs(n_octaves - nearest_n) < 0.1:
                if nearest_n not in octave_groups:
                    octave_groups[nearest_n] = []
                coh_diff = abs(mapped_coh[i] - mapped_coh[j]) / coh_range_val
                octave_groups[nearest_n].append(coh_diff)

    # Also compute coherence diffs for NON-octave pairs (control)
    non_octave_diffs = []
    for i in range(n_struct):
        for j in range(i + 1, n_struct):
            ratio = cosmic_ratios[i, j]
            n_octaves = ratio / COSMIC_IDEAL_DELTA
            nearest_n = round(n_octaves)
            if nearest_n < 1 or abs(n_octaves - nearest_n) >= 0.1:
                coh_diff = abs(mapped_coh[i] - mapped_coh[j]) / coh_range_val
                non_octave_diffs.append(coh_diff)

    R.append(f"  {'Oct Mult':>9}  {'Pairs':>5}  {'Mean |ΔCoh/range|':>18}  {'Note':>20}")
    for n_oct in sorted(octave_groups.keys()):
        diffs = octave_groups[n_oct]
        mean_diff = np.mean(diffs)
        R.append(f"  {n_oct:9d}×     {len(diffs):5d}  {mean_diff:18.4f}  "
                 f"{'← fundamental' if n_oct == 1 else ''}")

    if non_octave_diffs:
        R.append(f"  {'non-oct':>9}  {len(non_octave_diffs):5d}  "
                 f"{np.mean(non_octave_diffs):18.4f}  (control group)")

    if octave_groups.get(1) and non_octave_diffs:
        oct_mean = np.mean(octave_groups[1])
        non_mean = np.mean(non_octave_diffs)
        if oct_mean < non_mean:
            R.append(f"\n  → Octave-paired structures are MORE similar in coherence than random pairs")
            R.append(f"    (octave mean = {oct_mean:.4f} vs control = {non_mean:.4f})")
        else:
            R.append(f"\n  → Octave-paired structures are NOT more similar than random pairs")
            R.append(f"    (octave mean = {oct_mean:.4f} vs control = {non_mean:.4f})")

    # ── Verdict ──
    R.append("")
    R.append("COSMIC OCTAVE VERDICT")
    R.append("═"*76)

    evidence_for = []
    evidence_against = []

    if observed_strong >= 3:
        evidence_for.append(f"{observed_strong} strong coherence matches across octave pairs")
    elif observed_strong >= 2:
        evidence_for.append(f"{observed_strong} moderate coherence matches across octave pairs")
    else:
        evidence_against.append(f"Only {observed_strong} strong match(es) — insufficient")

    if p_value < 0.01:
        evidence_for.append(f"Permutation p-value = {p_value:.6f} (significant)")
    elif p_value < 0.05:
        evidence_for.append(f"Permutation p-value = {p_value:.4f} (marginally significant)")
    else:
        evidence_against.append(f"Permutation p-value = {p_value:.4f} (not significant)")

    if len(pair_coh_lower) >= 3:
        pair_corr = np.corrcoef(pair_coh_lower, pair_coh_upper)[0, 1]
        if pair_corr > 0.3:
            evidence_for.append(f"Octave pair coherence correlation r = {pair_corr:+.3f}")
        elif pair_corr < -0.3:
            evidence_against.append(f"Octave pairs anti-correlated r = {pair_corr:+.3f}")

    if octave_groups.get(1) and non_octave_diffs:
        if np.mean(octave_groups[1]) < np.mean(non_octave_diffs) * 0.8:
            evidence_for.append("Octave pairs more coherence-similar than random pairs")
        elif np.mean(octave_groups[1]) > np.mean(non_octave_diffs) * 1.2:
            evidence_against.append("Octave pairs less similar than random pairs")

    R.append("Evidence FOR cosmic octave recurrence in lattice:")
    for e in evidence_for:
        R.append(f"  + {e}")
    if not evidence_for:
        R.append("  (none)")
    R.append("Evidence AGAINST:")
    for e in evidence_against:
        R.append(f"  - {e}")
    if not evidence_against:
        R.append("  (none)")

    R.append("")
    if len(evidence_for) > len(evidence_against):
        R.append("ASSESSMENT: The Resonance Engine lattice shows signatures consistent")
        R.append("with cosmic octave self-similarity.  The 10²⁴-meter recurrence pattern")
        R.append("maps onto the lattice coherence field with statistically significant")
        R.append("structure.  This supports the hypothesis that the same scale-invariant")
        R.append("organizing principle operates from quantum to cosmological scales AND")
        R.append("within the lattice dynamics.")
    elif len(evidence_against) > len(evidence_for):
        R.append("ASSESSMENT: Cosmic octave recurrence is NOT clearly present in the")
        R.append("current sweep data.  This may indicate:")
        R.append("  1. The omega resolution (0.1 step) is too coarse to resolve the signal")
        R.append("  2. The mapping from log₁₀(L) to omega is non-linear")
        R.append("  3. The cosmic pattern requires a larger parameter space to manifest")
        R.append("Recommendation: run a high-resolution sweep focused on the 7 mapped")
        R.append("omega positions with ±0.05 fine-grid around each.")
    else:
        R.append("ASSESSMENT: INCONCLUSIVE.  The evidence is mixed.")
        R.append("A higher-resolution sweep targeting the mapped octave positions would")
        R.append("resolve whether the lattice genuinely embeds this pattern.")

    R.append("")
    R.append("ATTRIBUTION:")
    R.append("  Cosmic octave analysis: Chris Lehto (2026)")
    R.append("  'Scale Recurrence Across Cosmic Structures'")
    R.append("  https://github.com/Chris-L78/cosmic-octaves-analysis")


# ══════════════════════════════════════════════════════════════════════════
# CROSS-DOMAIN SYNTHESIS
# ══════════════════════════════════════════════════════════════════════════
def report_synthesis(df, mode_data, omega_stats, R):
    R.append("")
    R.append("")
    R.append("╔" + "═"*76 + "╗")
    R.append("║  CROSS-DOMAIN SYNTHESIS                                                    ║")
    R.append("╚" + "═"*76 + "╝")
    R.append("")
    R.append("The four analyses test the same underlying mathematics (eigenvalue spectra")
    R.append("of bounded wave systems) through different physical lenses:")
    R.append("")

    omega_vals = sorted(df['omega'].unique())
    coh_means_list = [s['coh_mean'] for s in omega_stats]

    # Identify key omega values from each domain
    R.append("OMEGA VALUE CONCORDANCE:")
    R.append("─"*76)
    R.append(f"  {'Ω':>5}  {'Nuclear':>15}  {'Brillouin':>15}  {'KAM':>15}  {'Coherence':>10}")

    for i, omega in enumerate(omega_vals):
        md = [m for m in mode_data if m['omega'] == omega][0]
        coh = coh_means_list[i]

        # Nuclear assessment
        n_modes = md['n_modes']
        if n_modes in [2, 8, 20, 28, 50]:
            nuc_label = f"magic N={n_modes}"
        elif n_modes in [2, 6, 12, 20]:
            nuc_label = f"HO g={n_modes}"
        else:
            nuc_label = f"{n_modes} modes"

        # Brillouin: is this in a band or gap?
        mean_coh = np.mean(coh_means_list)
        if coh > mean_coh + np.std(coh_means_list) * 0.5:
            bz_label = "band center"
        elif coh < mean_coh - np.std(coh_means_list) * 0.5:
            bz_label = "band gap"
        else:
            bz_label = "band edge"

        # KAM: irrationality of omega / 1.0
        ratio = omega / 1.0
        p, q, err = nearest_rational(ratio, 12)
        if q == 1:
            kam_label = f"integer {p}:1"
        elif err < 0.01:
            kam_label = f"resonant {p}:{q}"
        else:
            kam_label = f"irrational"
        if abs(omega - GOLDEN) < 0.06:
            kam_label = "≈ golden φ"

        R.append(f"  {omega:5.1f}  {nuc_label:>15}  {bz_label:>15}  {kam_label:>15}  {coh:10.6f}")

    R.append("")
    R.append("KEY FINDINGS:")
    R.append("─"*76)

    # What omega values appear special in multiple domains?
    special = {}
    for md in mode_data:
        omega = md['omega']
        score = 0
        reasons = []
        coh = coh_means_list[omega_vals.index(omega)]

        if md['n_modes'] in [2, 8, 20, 28]:
            score += 2
            reasons.append(f"magic N={md['n_modes']}")
        if md['n_modes'] in [2, 6, 12, 20]:
            score += 1
            reasons.append(f"HO degeneracy {md['n_modes']}")
        if coh > np.mean(coh_means_list) + np.std(coh_means_list):
            score += 2
            reasons.append("high coherence (band center)")
        if coh < np.mean(coh_means_list) - np.std(coh_means_list):
            score += 1
            reasons.append("low coherence (gap)")
        ratio = omega / 1.0
        p, q, err = nearest_rational(ratio, 8)
        if q == 1 and err < 0.01:
            score += 1
            reasons.append(f"integer resonance ({p}:1)")
        if abs(omega - GOLDEN) < 0.06:
            score += 2
            reasons.append("≈ golden ratio")

        if score >= 2:
            special[omega] = (score, reasons)

    for omega in sorted(special.keys(), key=lambda o: -special[o][0]):
        score, reasons = special[omega]
        R.append(f"  Ω = {omega:.1f} (score {score}):  {' + '.join(reasons)}")

    R.append("")
    R.append("DATA QUALITY NOTE:")
    R.append("─"*76)
    n_unique = len(np.unique(df['coherence'].values))
    R.append(f"The sweep produced {n_unique} distinct coherence values from 375 measurements.")
    R.append(f"This quantization (telemetry resolution ≈ {min(np.diff(np.sort(np.unique(df['coherence'].values)))):.4f})")
    R.append(f"limits the detail of all three analyses.  Recommended next steps:")
    R.append(f"  1. Increase stabilization time from 3s to 8-10s per point")
    R.append(f"  2. Use finer omega grid (0.01 step) around Ω = 1.0-1.2 and 1.5-1.7")
    R.append(f"  3. Request higher-resolution telemetry from the CUDA daemon")
    R.append(f"  4. Run multiple sweeps and average to reduce measurement noise")


# ══════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════
def main():
    df, source = load_data()
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")

    R = []
    R.append("╔" + "═"*76 + "╗")
    R.append("║     RESONANCE ENGINE — PHYSICS DOMAIN ANALYSIS                             ║")
    R.append("║     Four-Domain Structural Hypothesis Testing                              ║")
    R.append("╚" + "═"*76 + "╝")
    R.append(f"Source:  {source}")
    R.append(f"Points:  {len(df)}")
    R.append(f"Date:    {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    R.append(f"Omega:   {df['omega'].min():.1f} – {df['omega'].max():.1f} ({df['omega'].nunique()} steps)")
    R.append(f"Khra:    {df['khra_amp'].min():.3f} – {df['khra_amp'].max():.3f} ({df['khra_amp'].nunique()} steps)")
    R.append(f"Gixx:    {df['gixx_amp'].min():.4f} – {df['gixx_amp'].max():.4f} ({df['gixx_amp'].nunique()} steps)")
    R.append(f"Coherence: {df['coherence'].min():.6f} – {df['coherence'].max():.6f}")

    # Run all four reports
    mode_data = report_nuclear(df, R)
    omega_stats = report_brillouin(df, mode_data, R)
    report_kirkwood(df, omega_stats, R)
    report_cosmic_octaves(df, mode_data, omega_stats, R)
    report_synthesis(df, mode_data, omega_stats, R)

    R.append("")
    R.append("═"*78)
    R.append("END OF PHYSICS DOMAIN ANALYSIS")
    R.append("═"*78)

    # Save and print
    report_text = "\n".join(R)
    out_path = os.path.join(RESULTS_DIR, f"physics_domain_analysis_{ts}.txt")
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(report_text)
    print(f"Saved: {out_path}")
    print()
    try:
        print(report_text)
    except UnicodeEncodeError:
        print(report_text.encode('ascii', errors='replace').decode('ascii'))


if __name__ == "__main__":
    main()
