#!/usr/bin/env python3
"""Statistical analysis of asymmetry thresholds (no scipy)"""

import json
import glob
import math
from collections import Counter

# Read all status files
files = glob.glob('/mnt/d/fractal-brain/beast-build/sweep_results/run_*_status.json')

data = []
for f in files:
    try:
        with open(f) as fp:
            d = json.load(fp)
            if 'asymmetry' in d and 'coherence' in d:
                data.append({
                    'asymmetry': d['asymmetry'],
                    'coherence': d['coherence'],
                    'cycle': d.get('cycle', 0)
                })
    except:
        pass

if not data:
    print("No data found")
    exit()

asym = [d['asymmetry'] for d in data]
coh = [d['coherence'] for d in data]
n = len(asym)

print("="*60)
print("STATISTICAL ANALYSIS OF ASYMMETRY THRESHOLDS")
print("="*60)
print(f"\nSample size: {n}")

# Basic statistics
mean = sum(asym) / n
variance = sum((x - mean)**2 for x in asym) / n
std_dev = math.sqrt(variance)
sorted_asym = sorted(asym)
median = sorted_asym[n//2] if n % 2 else (sorted_asym[n//2-1] + sorted_asym[n//2]) / 2
min_val = min(asym)
max_val = max(asym)
q25 = sorted_asym[n//4]
q75 = sorted_asym[3*n//4]

print("\n" + "="*60)
print("DESCRIPTIVE STATISTICS")
print("="*60)
print(f"Mean: {mean:.6f}")
print(f"Median: {median:.6f}")
print(f"Std Dev: {std_dev:.6f}")
print(f"Variance: {variance:.6f}")
print(f"Range: {min_val:.6f} - {max_val:.6f}")
print(f"IQR: {q25:.6f} - {q75:.6f}")

# Histogram
print("\n" + "="*60)
print("DISTRIBUTION (20 bins)")
print("="*60)
bin_width = (max_val - min_val) / 20
bins = [min_val + i * bin_width for i in range(21)]
hist = [0] * 20
for x in asym:
    for i in range(20):
        if bins[i] <= x < bins[i+1]:
            hist[i] += 1
            break
    if x >= bins[20]:
        hist[19] += 1

max_hist = max(hist) if max(hist) > 0 else 1
for i, h in enumerate(hist):
    bar = '*' * int(50 * h / max_hist)
    print(f"{bins[i]:.3f}-{bins[i+1]:.3f}: {h:3d} {bar}")

# Find peaks in histogram
print("\n" + "="*60)
print("DETECTED PEAKS (clusters)")
print("="*60)
peaks = []
for i in range(1, 19):
    if hist[i] > hist[i-1] and hist[i] > hist[i+1] and hist[i] > 5:
        peak_center = (bins[i] + bins[i+1]) / 2
        peaks.append((peak_center, hist[i]))

peaks.sort()
for i, (p, h) in enumerate(peaks):
    print(f"Peak {i+1}: {p:.4f} (count: {h})")

# Phi analysis
print("\n" + "="*60)
print("GOLDEN RATIO (φ = 1.618034) ANALYSIS")
print("="*60)
phi = 1.6180339887

if len(peaks) >= 2:
    print("\nRatios between peaks:")
    for i in range(len(peaks)-1):
        for j in range(i+1, len(peaks)):
            ratio = peaks[j][0] / peaks[i][0]
            diff_phi = abs(ratio - phi)
            diff_phi2 = abs(ratio - phi**2)
            print(f"  {peaks[j][0]:.4f} / {peaks[i][0]:.4f} = {ratio:.6f}")
            if diff_phi < 0.05:
                print(f"    *** MATCHES φ (error: {diff_phi:.4f}) ***")
            if diff_phi2 < 0.05:
                print(f"    *** MATCHES φ² (error: {diff_phi2:.4f}) ***")

# Check for phi in cluster spacing
if len(peaks) >= 2:
    print("\nAdditive spacing (arithmetic progression):")
    for i in range(1, len(peaks)):
        spacing = peaks[i][0] - peaks[i-1][0]
        print(f"  Peak {i} - Peak {i-1}: {spacing:.4f}")

# Correlation with coherence
print("\n" + "="*60)
print("ASYMMETRY vs COHERENCE")
print("="*60)
mean_coh = sum(coh) / n
mean_asym = mean
covariance = sum((a - mean_asym) * (c - mean_coh) for a, c in zip(asym, coh)) / n
var_coh = sum((c - mean_coh)**2 for c in coh) / n
if var_coh > 0:
    correlation = covariance / math.sqrt(variance * var_coh)
    print(f"Correlation coefficient: {correlation:.6f}")
    if abs(correlation) > 0.5:
        print(f"Relationship: {'Strong negative' if correlation < 0 else 'Strong positive'}")
    else:
        print("Relationship: Weak or none")

# Entropy
print("\n" + "="*60)
print("INFORMATION ENTROPY")
print("="*60)
total = sum(hist)
entropy = 0
for h in hist:
    if h > 0:
        p = h / total
        entropy -= p * math.log2(p)
max_entropy = math.log2(20)
print(f"Shannon entropy: {entropy:.4f} bits")
print(f"Max possible: {max_entropy:.4f} bits")
print(f"Normalized: {entropy/max_entropy:.4f}")
print(f"Distribution: {'ORDERED/CLUSTERED' if entropy/max_entropy < 0.7 else 'UNIFORM/RANDOM'}")

# Look for power law
print("\n" + "="*60)
print("POWER LAW CHECK")
print("="*60)
if len(peaks) >= 2:
    print("Testing if peaks follow power law (x^n):")
    for n in [0.5, 1, 1.5, 2, phi-1, phi-2]:
        predicted = [peaks[0][0] * (i+1)**n for i in range(len(peaks))]
        errors = [abs(p[0] - pred) for p, pred in zip(peaks, predicted)]
        max_err = max(errors) if errors else 999
        print(f"  n={n:.4f}: max error = {max_err:.4f}")

print("\n" + "="*60)
print("ANALYSIS COMPLETE")
print("="*60)
