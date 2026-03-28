#!/usr/bin/env python3
"""
Comprehensive Data Analysis & Report Generator
Analyzes the 375-point EM parameter sweep and produces:
  1. Full statistical summary (text)
  2. Interactive HTML visualization dashboard
"""

import os
import sys
import numpy as np
import pandas as pd
from datetime import datetime
from collections import Counter
import json

# ── Config ──────────────────────────────────────────────────────────
MAGIC_NUMBERS = [2, 8, 20, 28, 50, 82, 126]
SWEEP_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "sweep_results")
RESULTS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "results")
os.makedirs(RESULTS_DIR, exist_ok=True)


def load_data(csv_path=None):
    if csv_path is None:
        csvs = sorted([f for f in os.listdir(SWEEP_DIR) if f.startswith("em_direct_sweep") and f.endswith(".csv")])
        if not csvs:
            print("No sweep CSVs found"); sys.exit(1)
        csv_path = os.path.join(SWEEP_DIR, csvs[-1])
        print(f"Auto-selected: {csvs[-1]}")
    df = pd.read_csv(csv_path)
    print(f"Loaded {len(df)} points")
    return df, os.path.basename(csv_path)


# ═══════════════════════════════════════════════════════════════════
# PART 1: Comprehensive Text Report
# ═══════════════════════════════════════════════════════════════════
def generate_text_report(df, source_name):
    R = []
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    R.append("=" * 78)
    R.append("       COMPREHENSIVE PARAMETER SWEEP ANALYSIS — RESONANCE ENGINE")
    R.append("=" * 78)
    R.append(f"Source:     {source_name}")
    R.append(f"Generated:  {ts}")
    R.append(f"Points:     {len(df)}")
    R.append(f"Duration:   {df['timestamp'].iloc[0]} → {df['timestamp'].iloc[-1]}")
    R.append("")

    # ── Section 1: Global Statistics ──
    R.append("─" * 78)
    R.append("1. GLOBAL STATISTICS")
    R.append("─" * 78)
    numeric_cols = ['omega', 'khra_amp', 'gixx_amp', 'coherence', 'asymmetry',
                    'vorticity_mean', 'gpu_temp_c', 'gpu_power_w', 'cycle']
    R.append(f"  {'Column':<18} {'Min':>12} {'Max':>12} {'Mean':>12} {'Std':>12} {'Median':>12}")
    for col in numeric_cols:
        v = df[col]
        R.append(f"  {col:<18} {v.min():>12.6f} {v.max():>12.6f} {v.mean():>12.6f} {v.std():>12.6f} {v.median():>12.6f}")

    # ── Section 2: Parameter Space Coverage ──
    R.append("")
    R.append("─" * 78)
    R.append("2. PARAMETER SPACE COVERAGE")
    R.append("─" * 78)
    omega_vals = sorted(df['omega'].unique())
    khra_vals = sorted(df['khra_amp'].unique())
    gixx_vals = sorted(df['gixx_amp'].unique())
    R.append(f"  Omega:    {len(omega_vals)} values: {[round(x,1) for x in omega_vals]}")
    R.append(f"  Khra_amp: {len(khra_vals)} values: {[round(x,3) for x in khra_vals]}")
    R.append(f"  Gixx_amp: {len(gixx_vals)} values: {[round(x,4) for x in gixx_vals]}")
    R.append(f"  Grid:     {len(omega_vals)} × {len(khra_vals)} × {len(gixx_vals)} = {len(omega_vals)*len(khra_vals)*len(gixx_vals)} (actual: {len(df)})")

    # ── Section 3: Coherence Analysis ──
    R.append("")
    R.append("─" * 78)
    R.append("3. COHERENCE ANALYSIS")
    R.append("─" * 78)

    # Top 10 coherence values
    top10 = df.nlargest(10, 'coherence')
    R.append("  Top 10 coherence measurements:")
    R.append(f"    {'Rank':>4}  {'Ω':>5}  {'K':>6}  {'G':>7}  {'Coh':>10}  {'Asym':>8}  {'Vort':>10}")
    for rank, (_, row) in enumerate(top10.iterrows(), 1):
        R.append(f"    {rank:4d}  {row['omega']:5.1f}  {row['khra_amp']:6.3f}  {row['gixx_amp']:7.4f}  "
                 f"{row['coherence']:10.6f}  {row['asymmetry']:8.4f}  {row['vorticity_mean']:10.6f}")

    # Bottom 10
    bot10 = df.nsmallest(10, 'coherence')
    R.append("\n  Bottom 10 coherence measurements:")
    R.append(f"    {'Rank':>4}  {'Ω':>5}  {'K':>6}  {'G':>7}  {'Coh':>10}  {'Asym':>8}  {'Vort':>10}")
    for rank, (_, row) in enumerate(bot10.iterrows(), 1):
        R.append(f"    {rank:4d}  {row['omega']:5.1f}  {row['khra_amp']:6.3f}  {row['gixx_amp']:7.4f}  "
                 f"{row['coherence']:10.6f}  {row['asymmetry']:8.4f}  {row['vorticity_mean']:10.6f}")

    # ── Section 4: Per-Omega Breakdown ──
    R.append("")
    R.append("─" * 78)
    R.append("4. PER-OMEGA BREAKDOWN")
    R.append("─" * 78)
    R.append(f"  {'Ω':>5}  {'Coh_min':>10}  {'Coh_max':>10}  {'Coh_mean':>10}  {'Coh_std':>10}  "
             f"{'Asym_mean':>10}  {'Vort_mean':>10}  {'Best K':>7}  {'Best G':>8}")
    for omega in omega_vals:
        g = df[df['omega'] == omega]
        best = g.loc[g['coherence'].idxmax()]
        R.append(f"  {omega:5.1f}  {g['coherence'].min():10.6f}  {g['coherence'].max():10.6f}  "
                 f"{g['coherence'].mean():10.6f}  {g['coherence'].std():10.6f}  "
                 f"{g['asymmetry'].mean():10.4f}  {g['vorticity_mean'].mean():10.6f}  "
                 f"{best['khra_amp']:7.3f}  {best['gixx_amp']:8.4f}")

    # ── Section 5: Per-Khra Breakdown ──
    R.append("")
    R.append("─" * 78)
    R.append("5. PER-KHRA BREAKDOWN")
    R.append("─" * 78)
    R.append(f"  {'K':>6}  {'Coh_min':>10}  {'Coh_max':>10}  {'Coh_mean':>10}  {'Coh_std':>10}  {'Best Ω':>6}  {'Best G':>8}")
    for khra in khra_vals:
        g = df[df['khra_amp'] == khra]
        best = g.loc[g['coherence'].idxmax()]
        R.append(f"  {khra:6.3f}  {g['coherence'].min():10.6f}  {g['coherence'].max():10.6f}  "
                 f"{g['coherence'].mean():10.6f}  {g['coherence'].std():10.6f}  "
                 f"{best['omega']:6.1f}  {best['gixx_amp']:8.4f}")

    # ── Section 6: Per-Gixx Breakdown ──
    R.append("")
    R.append("─" * 78)
    R.append("6. PER-GIXX BREAKDOWN")
    R.append("─" * 78)
    R.append(f"  {'G':>7}  {'Coh_min':>10}  {'Coh_max':>10}  {'Coh_mean':>10}  {'Coh_std':>10}  {'Best Ω':>6}  {'Best K':>7}")
    for gixx in gixx_vals:
        g = df[df['gixx_amp'] == gixx]
        best = g.loc[g['coherence'].idxmax()]
        R.append(f"  {gixx:7.4f}  {g['coherence'].min():10.6f}  {g['coherence'].max():10.6f}  "
                 f"{g['coherence'].mean():10.6f}  {g['coherence'].std():10.6f}  "
                 f"{best['omega']:6.1f}  {best['khra_amp']:7.3f}")

    # ── Section 7: Correlation Matrix ──
    R.append("")
    R.append("─" * 78)
    R.append("7. CORRELATION MATRIX")
    R.append("─" * 78)
    corr_cols = ['omega', 'khra_amp', 'gixx_amp', 'coherence', 'asymmetry', 'vorticity_mean']
    corr = df[corr_cols].corr()
    R.append(f"  {'':>14}" + "".join(f"{c:>14}" for c in corr_cols))
    for row_name in corr_cols:
        vals = "".join(f"{corr.loc[row_name, c]:14.4f}" for c in corr_cols)
        R.append(f"  {row_name:>14}{vals}")

    # ── Section 8: Coherence Sensitivity ──
    R.append("")
    R.append("─" * 78)
    R.append("8. PARAMETER SENSITIVITY (effect on coherence)")
    R.append("─" * 78)

    # Omega sensitivity: variance of mean coherence across omega
    omega_means = df.groupby('omega')['coherence'].mean()
    khra_means = df.groupby('khra_amp')['coherence'].mean()
    gixx_means = df.groupby('gixx_amp')['coherence'].mean()

    omega_range = omega_means.max() - omega_means.min()
    khra_range = khra_means.max() - khra_means.min()
    gixx_range = gixx_means.max() - gixx_means.min()
    total_range = omega_range + khra_range + gixx_range

    R.append(f"  Omega effect:    range={omega_range:.6f}  ({100*omega_range/total_range:.1f}% of total)")
    R.append(f"  Khra effect:     range={khra_range:.6f}  ({100*khra_range/total_range:.1f}% of total)")
    R.append(f"  Gixx effect:     range={gixx_range:.6f}  ({100*gixx_range/total_range:.1f}% of total)")
    R.append(f"  Most influential: {'omega' if omega_range >= max(khra_range, gixx_range) else 'khra_amp' if khra_range >= gixx_range else 'gixx_amp'}")

    # Per-omega sensitivity to khra and gixx
    R.append(f"\n  Per-omega sensitivity (coherence std when varying K,G):")
    R.append(f"    {'Ω':>5}  {'Std(coh)':>10}  {'Sensitivity':>12}")
    for omega in omega_vals:
        g = df[df['omega'] == omega]
        s = g['coherence'].std()
        bar = "█" * int(s * 10000)
        R.append(f"    {omega:5.1f}  {s:10.6f}  {bar}")

    # ── Section 9: Thermal & Power Profile ──
    R.append("")
    R.append("─" * 78)
    R.append("9. THERMAL & POWER PROFILE")
    R.append("─" * 78)
    R.append(f"  GPU Temperature:")
    R.append(f"    Min: {df['gpu_temp_c'].min():.0f}°C  Max: {df['gpu_temp_c'].max():.0f}°C  Mean: {df['gpu_temp_c'].mean():.1f}°C")
    R.append(f"    Points above 60°C: {(df['gpu_temp_c'] > 60).sum()} ({100*(df['gpu_temp_c'] > 60).mean():.1f}%)")

    R.append(f"  GPU Power:")
    R.append(f"    Min: {df['gpu_power_w'].min():.1f}W  Max: {df['gpu_power_w'].max():.1f}W  Mean: {df['gpu_power_w'].mean():.1f}W")
    R.append(f"    High power (>250W): {(df['gpu_power_w'] > 250).sum()} ({100*(df['gpu_power_w'] > 250).mean():.1f}%)")
    R.append(f"    Idle (<100W):       {(df['gpu_power_w'] < 100).sum()} ({100*(df['gpu_power_w'] < 100).mean():.1f}%)")

    # Temperature by omega
    R.append(f"\n  Temperature by omega:")
    R.append(f"    {'Ω':>5}  {'Temp_mean':>10}  {'Power_mean':>11}")
    for omega in omega_vals:
        g = df[df['omega'] == omega]
        R.append(f"    {omega:5.1f}  {g['gpu_temp_c'].mean():10.1f}  {g['gpu_power_w'].mean():11.1f}")

    # ── Section 10: Asymmetry & Vorticity Analysis ──
    R.append("")
    R.append("─" * 78)
    R.append("10. ASYMMETRY & VORTICITY ANALYSIS")
    R.append("─" * 78)

    R.append(f"  Asymmetry:  min={df['asymmetry'].min():.4f}  max={df['asymmetry'].max():.4f}  mean={df['asymmetry'].mean():.4f}")
    R.append(f"  Vorticity:  min={df['vorticity_mean'].min():.6f}  max={df['vorticity_mean'].max():.6f}  mean={df['vorticity_mean'].mean():.6f}")

    # Best asymmetry (lowest = most symmetric)
    best_sym = df.nsmallest(5, 'asymmetry')
    R.append(f"\n  Most symmetric configurations (lowest asymmetry):")
    for _, row in best_sym.iterrows():
        R.append(f"    Ω={row['omega']:.1f} K={row['khra_amp']:.3f} G={row['gixx_amp']:.4f}  "
                 f"Asym={row['asymmetry']:.4f}  Coh={row['coherence']:.6f}")

    # Highest vorticity
    high_vort = df.nlargest(5, 'vorticity_mean')
    R.append(f"\n  Highest vorticity configurations:")
    for _, row in high_vort.iterrows():
        R.append(f"    Ω={row['omega']:.1f} K={row['khra_amp']:.3f} G={row['gixx_amp']:.4f}  "
                 f"Vort={row['vorticity_mean']:.6f}  Coh={row['coherence']:.6f}")

    # Coherence-Asymmetry relationship
    coh_asym_corr = df['coherence'].corr(df['asymmetry'])
    coh_vort_corr = df['coherence'].corr(df['vorticity_mean'])
    asym_vort_corr = df['asymmetry'].corr(df['vorticity_mean'])
    R.append(f"\n  Cross-correlations:")
    R.append(f"    Coherence ↔ Asymmetry:  {coh_asym_corr:+.4f}")
    R.append(f"    Coherence ↔ Vorticity:  {coh_vort_corr:+.4f}")
    R.append(f"    Asymmetry ↔ Vorticity:  {asym_vort_corr:+.4f}")

    # ── Section 11: Optimal Operating Regions ──
    R.append("")
    R.append("─" * 78)
    R.append("11. OPTIMAL OPERATING REGIONS")
    R.append("─" * 78)

    # Multi-objective: high coherence + low asymmetry
    df_copy = df.copy()
    df_copy['score'] = (df_copy['coherence'] - df_copy['coherence'].min()) / (df_copy['coherence'].max() - df_copy['coherence'].min()) - \
                       0.5 * (df_copy['asymmetry'] - df_copy['asymmetry'].min()) / (df_copy['asymmetry'].max() - df_copy['asymmetry'].min())

    best_multi = df_copy.nlargest(10, 'score')
    R.append(f"  Top 10 by composite score (high coherence + low asymmetry):")
    R.append(f"    {'Ω':>5}  {'K':>6}  {'G':>7}  {'Coh':>10}  {'Asym':>8}  {'Vort':>10}  {'Score':>8}")
    for _, row in best_multi.iterrows():
        R.append(f"    {row['omega']:5.1f}  {row['khra_amp']:6.3f}  {row['gixx_amp']:7.4f}  "
                 f"{row['coherence']:10.6f}  {row['asymmetry']:8.4f}  {row['vorticity_mean']:10.6f}  {row['score']:8.4f}")

    # Recommend optimal settings
    best_overall = best_multi.iloc[0]
    R.append(f"\n  ★ RECOMMENDED OPERATING POINT:")
    R.append(f"    Ω = {best_overall['omega']:.1f}")
    R.append(f"    khra_amp = {best_overall['khra_amp']:.3f}")
    R.append(f"    gixx_amp = {best_overall['gixx_amp']:.4f}")
    R.append(f"    Expected coherence: {best_overall['coherence']:.6f}")
    R.append(f"    Expected asymmetry: {best_overall['asymmetry']:.4f}")

    # ── Section 12: Data Quality Assessment ──
    R.append("")
    R.append("─" * 78)
    R.append("12. DATA QUALITY ASSESSMENT")
    R.append("─" * 78)

    # Check for duplicate telemetry (stale reads)
    # Count consecutive identical coherence values
    coh_vals = df['coherence'].values
    stale_runs = []
    run_len = 1
    for i in range(1, len(coh_vals)):
        if coh_vals[i] == coh_vals[i-1]:
            run_len += 1
        else:
            if run_len > 1:
                stale_runs.append(run_len)
            run_len = 1
    if run_len > 1:
        stale_runs.append(run_len)

    total_stale = sum(stale_runs)
    R.append(f"  Consecutive identical readings: {len(stale_runs)} runs")
    R.append(f"  Total stale points: {total_stale}/{len(df)} ({100*total_stale/len(df):.1f}%)")
    if stale_runs:
        R.append(f"  Longest stale run: {max(stale_runs)} points")
        R.append(f"  Mean stale run length: {np.mean(stale_runs):.1f}")

    # Unique coherence values
    n_unique = df['coherence'].nunique()
    R.append(f"  Unique coherence values: {n_unique}/{len(df)} ({100*n_unique/len(df):.1f}%)")

    # Check cycle progression
    cycles = df['cycle'].values
    cycle_gaps = np.diff(cycles)
    R.append(f"\n  Cycle progression:")
    R.append(f"    Start cycle: {int(cycles[0])}")
    R.append(f"    End cycle:   {int(cycles[-1])}")
    R.append(f"    Total cycles: {int(cycles[-1] - cycles[0])}")
    R.append(f"    Mean gap: {cycle_gaps.mean():.0f} cycles/point")
    R.append(f"    Backwards jumps: {(cycle_gaps < 0).sum()}")

    R.append("")
    R.append("=" * 78)
    R.append("END OF REPORT")
    R.append("=" * 78)

    return "\n".join(R)


# ═══════════════════════════════════════════════════════════════════
# PART 2: Interactive HTML Dashboard
# ═══════════════════════════════════════════════════════════════════
def generate_html_report(df, source_name):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    omega_vals = sorted(df['omega'].unique())
    khra_vals = sorted(df['khra_amp'].unique())
    gixx_vals = sorted(df['gixx_amp'].unique())

    # Prepare data for JS
    # 1. Per-omega stats
    omega_stats = []
    for omega in omega_vals:
        g = df[df['omega'] == omega]
        best = g.loc[g['coherence'].idxmax()]
        omega_stats.append({
            'omega': omega,
            'coh_min': round(g['coherence'].min(), 6),
            'coh_max': round(g['coherence'].max(), 6),
            'coh_mean': round(g['coherence'].mean(), 6),
            'coh_std': round(g['coherence'].std(), 6),
            'asym_mean': round(g['asymmetry'].mean(), 4),
            'vort_mean': round(g['vorticity_mean'].mean(), 6),
            'temp_mean': round(g['gpu_temp_c'].mean(), 1),
            'power_mean': round(g['gpu_power_w'].mean(), 1),
            'best_k': round(best['khra_amp'], 3),
            'best_g': round(best['gixx_amp'], 4),
        })

    # 2. Heatmap data: omega × khra → max coherence (across gixx)
    heatmap_ok = []
    for omega in omega_vals:
        row = []
        for khra in khra_vals:
            g = df[(df['omega'] == omega) & (df['khra_amp'] == khra)]
            row.append(round(g['coherence'].max(), 6))
        heatmap_ok.append(row)

    # 3. Heatmap: omega × gixx → max coherence (across khra)
    heatmap_og = []
    for omega in omega_vals:
        row = []
        for gixx in gixx_vals:
            g = df[(df['omega'] == omega) & (df['gixx_amp'] == gixx)]
            row.append(round(g['coherence'].max(), 6))
        heatmap_og.append(row)

    # 4. All data points for scatter
    scatter_data = []
    for _, row in df.iterrows():
        scatter_data.append({
            'o': round(row['omega'], 1),
            'k': round(row['khra_amp'], 3),
            'g': round(row['gixx_amp'], 4),
            'c': round(row['coherence'], 6),
            'a': round(row['asymmetry'], 4),
            'v': round(row['vorticity_mean'], 6),
            't': int(row['gpu_temp_c']),
            'p': round(row['gpu_power_w'], 1),
        })

    # 5. Coherence distribution histogram
    coh_vals = df['coherence'].values
    hist_bins = 30
    hist_counts, hist_edges = np.histogram(coh_vals, bins=hist_bins)
    hist_centers = [round(0.5*(hist_edges[i] + hist_edges[i+1]), 6) for i in range(hist_bins)]

    # 6. Top configurations
    top20 = df.nlargest(20, 'coherence')
    top_configs = []
    for _, row in top20.iterrows():
        top_configs.append({
            'omega': round(row['omega'], 1),
            'khra': round(row['khra_amp'], 3),
            'gixx': round(row['gixx_amp'], 4),
            'coh': round(row['coherence'], 6),
            'asym': round(row['asymmetry'], 4),
            'vort': round(row['vorticity_mean'], 6),
        })

    # 7. Nuclear magic analysis data
    resolution = df['coherence'].std() * 0.1
    if resolution < 1e-6:
        resolution = 1e-4
    mode_counts = {}
    for omega in omega_vals:
        g = df[df['omega'] == omega]
        coh_sorted = np.sort(g['coherence'].values)
        modes = [coh_sorted[0]]
        for c in coh_sorted[1:]:
            if c - modes[-1] > resolution:
                modes.append(c)
        mode_counts[round(omega, 1)] = len(modes)

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Resonance Engine — Sweep Analysis Dashboard</title>
<style>
:root {{
    --bg: #0a0e17;
    --card: #111827;
    --border: #1f2937;
    --text: #e5e7eb;
    --dim: #9ca3af;
    --accent: #60a5fa;
    --gold: #fbbf24;
    --green: #34d399;
    --red: #f87171;
    --purple: #a78bfa;
}}
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{ background: var(--bg); color: var(--text); font-family: 'Segoe UI', system-ui, sans-serif; padding: 20px; }}
h1 {{ text-align: center; font-size: 1.8em; margin: 20px 0 5px; color: var(--accent); }}
.subtitle {{ text-align: center; color: var(--dim); margin-bottom: 30px; font-size: 0.9em; }}
.grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(450px, 1fr)); gap: 20px; margin-bottom: 20px; }}
.card {{ background: var(--card); border: 1px solid var(--border); border-radius: 12px; padding: 20px; }}
.card h2 {{ color: var(--gold); font-size: 1.1em; margin-bottom: 15px; border-bottom: 1px solid var(--border); padding-bottom: 8px; }}
.stat-grid {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; }}
.stat {{ background: var(--bg); padding: 12px; border-radius: 8px; text-align: center; }}
.stat .label {{ color: var(--dim); font-size: 0.75em; margin-bottom: 4px; }}
.stat .value {{ font-size: 1.4em; font-weight: bold; color: var(--accent); }}
.stat .value.gold {{ color: var(--gold); }}
.stat .value.green {{ color: var(--green); }}
canvas {{ width: 100% !important; height: auto !important; }}
table {{ width: 100%; border-collapse: collapse; font-size: 0.85em; }}
th {{ background: var(--bg); padding: 8px 6px; text-align: right; color: var(--gold); position: sticky; top: 0; }}
td {{ padding: 6px; text-align: right; border-bottom: 1px solid var(--border); }}
tr:hover td {{ background: rgba(96,165,250,0.08); }}
.highlight {{ color: var(--green); font-weight: bold; }}
.heatmap-container {{ overflow-x: auto; }}
.heatmap {{ border-collapse: collapse; margin: 0 auto; }}
.heatmap td {{ width: 60px; height: 32px; text-align: center; font-size: 0.75em; font-weight: bold; border: 1px solid var(--bg); }}
.heatmap th {{ padding: 4px 8px; font-size: 0.8em; color: var(--dim); }}
.magic-bar {{ display: flex; align-items: center; gap: 8px; margin: 4px 0; }}
.magic-bar .bar {{ height: 20px; background: var(--accent); border-radius: 4px; transition: width 0.3s; }}
.magic-bar .label {{ font-size: 0.8em; color: var(--dim); min-width: 40px; }}
.magic-bar .count {{ font-size: 0.8em; min-width: 20px; }}
.magic-hit {{ background: var(--gold) !important; color: #000 !important; }}
.full-width {{ grid-column: 1 / -1; }}
.recommend {{ background: linear-gradient(135deg, #1a2744, #1a3a2a); border: 2px solid var(--green); }}
.recommend h2 {{ color: var(--green); }}
.tab-bar {{ display: flex; gap: 4px; margin-bottom: 12px; }}
.tab {{ padding: 6px 14px; border-radius: 6px 6px 0 0; cursor: pointer; background: var(--bg); color: var(--dim); border: 1px solid var(--border); border-bottom: none; font-size: 0.85em; }}
.tab.active {{ background: var(--card); color: var(--accent); }}
.tab-content {{ display: none; }}
.tab-content.active {{ display: block; }}
</style>
</head>
<body>
<h1>⚛ Resonance Engine — Parameter Sweep Dashboard</h1>
<div class="subtitle">{source_name} &bull; {len(df)} points &bull; {ts}</div>

<!-- Key Metrics -->
<div class="grid">
<div class="card full-width">
<h2>Key Metrics</h2>
<div class="stat-grid">
  <div class="stat"><div class="label">Peak Coherence</div><div class="value gold">{df['coherence'].max():.6f}</div></div>
  <div class="stat"><div class="label">Mean Coherence</div><div class="value">{df['coherence'].mean():.6f}</div></div>
  <div class="stat"><div class="label">Coherence Range</div><div class="value">{df['coherence'].max()-df['coherence'].min():.6f}</div></div>
  <div class="stat"><div class="label">Best Omega</div><div class="value green">{top_configs[0]['omega']:.1f}</div></div>
  <div class="stat"><div class="label">Points</div><div class="value">{len(df)}</div></div>
  <div class="stat"><div class="label">Magic Matches</div><div class="value gold">{sum(1 for n in mode_counts.values() if n in MAGIC_NUMBERS)}/15</div></div>
</div>
</div>
</div>

<div class="grid">

<!-- Coherence vs Omega -->
<div class="card">
<h2>Coherence vs Omega</h2>
<canvas id="chartOmega" height="280"></canvas>
</div>

<!-- Coherence Distribution -->
<div class="card">
<h2>Coherence Distribution</h2>
<canvas id="chartHist" height="280"></canvas>
</div>

<!-- Heatmap: Omega × Khra -->
<div class="card">
<h2>Heatmap: Ω × Khra → Peak Coherence</h2>
<div class="heatmap-container" id="heatmapOK"></div>
</div>

<!-- Heatmap: Omega × Gixx -->
<div class="card">
<h2>Heatmap: Ω × Gixx → Peak Coherence</h2>
<div class="heatmap-container" id="heatmapOG"></div>
</div>

<!-- Nuclear Magic Modes -->
<div class="card">
<h2>Mode Count vs Nuclear Magic Numbers</h2>
<canvas id="chartMagic" height="280"></canvas>
<div id="magicBars" style="margin-top:12px;"></div>
</div>

<!-- Asymmetry & Vorticity -->
<div class="card">
<h2>Asymmetry & Vorticity vs Omega</h2>
<canvas id="chartAsymVort" height="280"></canvas>
</div>

<!-- Thermal Profile -->
<div class="card">
<h2>Thermal & Power Profile</h2>
<canvas id="chartThermal" height="280"></canvas>
</div>

<!-- Recommended Config -->
<div class="card recommend">
<h2>★ Recommended Operating Point</h2>
<div class="stat-grid" style="margin-top:10px;">
  <div class="stat"><div class="label">Omega (Ω)</div><div class="value green">{top_configs[0]['omega']:.1f}</div></div>
  <div class="stat"><div class="label">Khra Amp</div><div class="value green">{top_configs[0]['khra']:.3f}</div></div>
  <div class="stat"><div class="label">Gixx Amp</div><div class="value green">{top_configs[0]['gixx']:.4f}</div></div>
</div>
<div class="stat-grid" style="margin-top:10px;">
  <div class="stat"><div class="label">Coherence</div><div class="value gold">{top_configs[0]['coh']:.6f}</div></div>
  <div class="stat"><div class="label">Asymmetry</div><div class="value">{top_configs[0]['asym']:.4f}</div></div>
  <div class="stat"><div class="label">Vorticity</div><div class="value">{top_configs[0]['vort']:.6f}</div></div>
</div>
</div>

</div>

<!-- Top Configurations Table -->
<div class="grid">
<div class="card full-width">
<h2>Top 20 Configurations</h2>
<table>
<thead><tr><th>#</th><th>Ω</th><th>K</th><th>G</th><th>Coherence</th><th>Asymmetry</th><th>Vorticity</th></tr></thead>
<tbody id="topTable"></tbody>
</table>
</div>
</div>

<!-- Per-Omega Detail Table -->
<div class="grid">
<div class="card full-width">
<h2>Per-Omega Summary</h2>
<table>
<thead><tr><th>Ω</th><th>Coh Min</th><th>Coh Max</th><th>Coh Mean</th><th>Coh Std</th><th>Asym Mean</th><th>Vort Mean</th><th>Best K</th><th>Best G</th></tr></thead>
<tbody id="omegaTable"></tbody>
</table>
</div>
</div>

<script>
// ── Data ──
const omegaStats = {json.dumps(omega_stats)};
const heatmapOK = {json.dumps(heatmap_ok)};
const heatmapOG = {json.dumps(heatmap_og)};
const topConfigs = {json.dumps(top_configs)};
const modeCounts = {json.dumps(mode_counts)};
const histCenters = {json.dumps(hist_centers)};
const histCounts = {json.dumps(hist_counts.tolist())};
const omegaLabels = {json.dumps([round(o,1) for o in omega_vals])};
const khraLabels = {json.dumps([round(k,3) for k in khra_vals])};
const gixxLabels = {json.dumps([round(g,4) for g in gixx_vals])};
const magicNumbers = {json.dumps(MAGIC_NUMBERS[:6])};

// ── Minimal Canvas Chart Library ──
function drawChart(canvasId, config) {{
    const canvas = document.getElementById(canvasId);
    const ctx = canvas.getContext('2d');
    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    ctx.scale(dpr, dpr);
    const W = rect.width, H = rect.height;
    const pad = {{top: 20, right: 20, bottom: 40, left: 70}};
    const pW = W - pad.left - pad.right;
    const pH = H - pad.top - pad.bottom;

    // Background
    ctx.fillStyle = '#0a0e17';
    ctx.fillRect(0, 0, W, H);

    // Find data bounds
    let allY = [];
    config.datasets.forEach(ds => ds.data.forEach(v => allY.push(v)));
    let yMin = config.yMin !== undefined ? config.yMin : Math.min(...allY);
    let yMax = config.yMax !== undefined ? config.yMax : Math.max(...allY);
    if (yMin === yMax) {{ yMin -= 0.0001; yMax += 0.0001; }}
    const yRange = yMax - yMin;

    // Grid lines
    ctx.strokeStyle = '#1f2937';
    ctx.lineWidth = 1;
    for (let i = 0; i <= 5; i++) {{
        const y = pad.top + pH - (i/5) * pH;
        ctx.beginPath(); ctx.moveTo(pad.left, y); ctx.lineTo(W - pad.right, y); ctx.stroke();
        ctx.fillStyle = '#9ca3af';
        ctx.font = '11px monospace';
        ctx.textAlign = 'right';
        ctx.fillText((yMin + (i/5) * yRange).toFixed(config.yDecimals || 4), pad.left - 6, y + 4);
    }}

    // X labels
    ctx.textAlign = 'center';
    ctx.fillStyle = '#9ca3af';
    config.labels.forEach((lbl, i) => {{
        const x = pad.left + (i / (config.labels.length - 1)) * pW;
        ctx.fillText(lbl, x, H - pad.bottom + 18);
    }});

    // Axis labels
    if (config.xLabel) {{
        ctx.fillText(config.xLabel, pad.left + pW/2, H - 4);
    }}

    // Datasets
    config.datasets.forEach(ds => {{
        ctx.strokeStyle = ds.color || '#60a5fa';
        ctx.lineWidth = ds.lineWidth || 2;
        ctx.beginPath();
        ds.data.forEach((v, i) => {{
            const x = pad.left + (i / (ds.data.length - 1)) * pW;
            const y = pad.top + pH - ((v - yMin) / yRange) * pH;
            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }});
        ctx.stroke();

        // Points
        if (ds.points !== false) {{
            ctx.fillStyle = ds.color || '#60a5fa';
            ds.data.forEach((v, i) => {{
                const x = pad.left + (i / (ds.data.length - 1)) * pW;
                const y = pad.top + pH - ((v - yMin) / yRange) * pH;
                ctx.beginPath(); ctx.arc(x, y, 4, 0, Math.PI * 2); ctx.fill();
            }});
        }}

        // Label
        if (ds.label) {{
            ctx.fillStyle = ds.color || '#60a5fa';
            ctx.textAlign = 'left';
            ctx.font = '11px sans-serif';
            const lastY = pad.top + pH - ((ds.data[ds.data.length-1] - yMin) / yRange) * pH;
            ctx.fillText(ds.label, W - pad.right + 4, lastY + 4);
        }}
    }});

    // Magic number horizontal lines
    if (config.magicLines) {{
        ctx.setLineDash([4, 4]);
        ctx.strokeStyle = '#fbbf2480';
        ctx.lineWidth = 1;
        magicNumbers.forEach(mn => {{
            if (mn >= yMin && mn <= yMax) {{
                const y = pad.top + pH - ((mn - yMin) / yRange) * pH;
                ctx.beginPath(); ctx.moveTo(pad.left, y); ctx.lineTo(W-pad.right, y); ctx.stroke();
                ctx.fillStyle = '#fbbf24';
                ctx.textAlign = 'right';
                ctx.fillText(mn, pad.left - 4, y + 4);
            }}
        }});
        ctx.setLineDash([]);
    }}
}}

function drawBarChart(canvasId, labels, data, color, yLabel) {{
    const canvas = document.getElementById(canvasId);
    const ctx = canvas.getContext('2d');
    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    ctx.scale(dpr, dpr);
    const W = rect.width, H = rect.height;
    const pad = {{top: 20, right: 20, bottom: 40, left: 60}};
    const pW = W - pad.left - pad.right;
    const pH = H - pad.top - pad.bottom;

    ctx.fillStyle = '#0a0e17';
    ctx.fillRect(0, 0, W, H);

    const maxVal = Math.max(...data) * 1.1;
    const barW = pW / data.length * 0.7;
    const gap = pW / data.length * 0.3;

    data.forEach((v, i) => {{
        const x = pad.left + (i / data.length) * pW + gap/2;
        const barH = (v / maxVal) * pH;
        const y = pad.top + pH - barH;
        ctx.fillStyle = color || '#60a5fa';
        ctx.fillRect(x, y, barW, barH);
        ctx.fillStyle = '#9ca3af';
        ctx.font = '10px monospace';
        ctx.textAlign = 'center';
        ctx.fillText(labels[i], x + barW/2, H - pad.bottom + 16);
    }});

    // Y axis
    for (let i = 0; i <= 4; i++) {{
        const y = pad.top + pH - (i/4) * pH;
        ctx.strokeStyle = '#1f2937';
        ctx.beginPath(); ctx.moveTo(pad.left, y); ctx.lineTo(W-pad.right, y); ctx.stroke();
        ctx.fillStyle = '#9ca3af';
        ctx.textAlign = 'right';
        ctx.font = '11px monospace';
        ctx.fillText((maxVal * i / 4).toFixed(0), pad.left - 6, y + 4);
    }}
}}

// ── Render Charts ──
window.addEventListener('load', () => {{
    // Coherence vs Omega
    drawChart('chartOmega', {{
        labels: omegaLabels,
        xLabel: 'Omega (Ω)',
        yDecimals: 4,
        datasets: [
            {{ data: omegaStats.map(s => s.coh_max), color: '#fbbf24', label: 'Max', lineWidth: 2 }},
            {{ data: omegaStats.map(s => s.coh_mean), color: '#60a5fa', label: 'Mean', lineWidth: 2 }},
            {{ data: omegaStats.map(s => s.coh_min), color: '#f87171', label: 'Min', lineWidth: 1 }},
        ]
    }});

    // Histogram
    drawBarChart('chartHist', histCenters.map(c => c.toFixed(4)), histCounts, '#60a5fa');

    // Mode counts with magic lines
    drawChart('chartMagic', {{
        labels: omegaLabels,
        xLabel: 'Omega (Ω)',
        yDecimals: 0,
        yMin: 0,
        yMax: 30,
        magicLines: true,
        datasets: [
            {{ data: omegaLabels.map(o => modeCounts[o]), color: '#34d399', label: 'Modes', lineWidth: 2 }},
        ]
    }});

    // Asymmetry & Vorticity
    drawChart('chartAsymVort', {{
        labels: omegaLabels,
        xLabel: 'Omega (Ω)',
        yDecimals: 2,
        datasets: [
            {{ data: omegaStats.map(s => s.asym_mean), color: '#a78bfa', label: 'Asymmetry' }},
        ]
    }});

    // Thermal
    drawChart('chartThermal', {{
        labels: omegaLabels,
        xLabel: 'Omega (Ω)',
        yDecimals: 0,
        datasets: [
            {{ data: omegaStats.map(s => s.temp_mean), color: '#f87171', label: 'Temp °C' }},
            {{ data: omegaStats.map(s => s.power_mean / 5), color: '#fbbf24', label: 'Power/5' }},
        ]
    }});

    // Heatmaps
    renderHeatmap('heatmapOK', heatmapOK, omegaLabels, khraLabels, 'Ω', 'K');
    renderHeatmap('heatmapOG', heatmapOG, omegaLabels, gixxLabels, 'Ω', 'G');

    // Tables
    renderTopTable();
    renderOmegaTable();
}});

function renderHeatmap(containerId, data, rowLabels, colLabels, rowName, colName) {{
    const container = document.getElementById(containerId);
    const allVals = data.flat();
    const vMin = Math.min(...allVals);
    const vMax = Math.max(...allVals);
    const range = vMax - vMin || 0.0001;

    let html = '<table class="heatmap"><tr><th>' + rowName + '\\\\' + colName + '</th>';
    colLabels.forEach(c => html += '<th>' + c + '</th>');
    html += '</tr>';

    data.forEach((row, i) => {{
        html += '<tr><th>' + rowLabels[i] + '</th>';
        row.forEach(v => {{
            const t = (v - vMin) / range;
            const r = Math.round(30 + 50 * (1-t));
            const g = Math.round(80 + 160 * t);
            const b = Math.round(120 + 130 * t);
            html += '<td style="background:rgb(' + r + ',' + g + ',' + b + ');color:' + (t > 0.5 ? '#000' : '#fff') + '">' + v.toFixed(4) + '</td>';
        }});
        html += '</tr>';
    }});
    html += '</table>';
    container.innerHTML = html;
}}

function renderTopTable() {{
    const tbody = document.getElementById('topTable');
    topConfigs.forEach((c, i) => {{
        tbody.innerHTML += '<tr><td>' + (i+1) + '</td><td>' + c.omega + '</td><td>' + c.khra + '</td><td>' + c.gixx + '</td><td class="highlight">' + c.coh.toFixed(6) + '</td><td>' + c.asym + '</td><td>' + c.vort + '</td></tr>';
    }});
}}

function renderOmegaTable() {{
    const tbody = document.getElementById('omegaTable');
    omegaStats.forEach(s => {{
        tbody.innerHTML += '<tr><td>' + s.omega + '</td><td>' + s.coh_min.toFixed(6) + '</td><td>' + s.coh_max.toFixed(6) + '</td><td>' + s.coh_mean.toFixed(6) + '</td><td>' + s.coh_std.toFixed(6) + '</td><td>' + s.asym_mean + '</td><td>' + s.vort_mean + '</td><td>' + s.best_k + '</td><td>' + s.best_g + '</td></tr>';
    }});
}}
</script>
</body>
</html>"""
    return html


# ═══════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════
def main():
    csv_path = sys.argv[1] if len(sys.argv) > 1 else None
    df, source = load_data(csv_path)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    # Generate text report
    print("Generating text report...")
    text_report = generate_text_report(df, source)
    text_path = os.path.join(RESULTS_DIR, f"sweep_analysis_{timestamp}.txt")
    with open(text_path, 'w', encoding='utf-8') as f:
        f.write(text_report)
    print(f"  Saved: {text_path}")

    # Generate HTML dashboard
    print("Generating HTML dashboard...")
    html_report = generate_html_report(df, source)
    html_path = os.path.join(RESULTS_DIR, f"sweep_dashboard_{timestamp}.html")
    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(html_report)
    print(f"  Saved: {html_path}")

    # Print summary to stdout
    print("\n" + text_report)


if __name__ == "__main__":
    main()
