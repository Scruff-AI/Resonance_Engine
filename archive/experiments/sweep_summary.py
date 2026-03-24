#!/usr/bin/env python3
import json, glob, statistics

files = glob.glob('/mnt/d/fractal-brain/beast-build/sweep_results/run_*_status.json')
data = []
for f in files:
    try:
        with open(f) as fp:
            d = json.load(fp)
            if 'asymmetry' in d and 'coherence' in d:
                data.append({'asymmetry': d['asymmetry'], 'coherence': d['coherence']})
    except:
        pass

if not data:
    print("No data")
    exit()

asym = [d['asymmetry'] for d in data]
coh = [d['coherence'] for d in data]

print("="*60)
print("SWEEP DATA SUMMARY")
print("="*60)
print(f"Total samples: {len(data)}")
print(f"\nAsymmetry:")
print(f"  Range: {min(asym):.4f} - {max(asym):.4f}")
print(f"  Mean: {statistics.mean(asym):.4f}")
print(f"  Median: {statistics.median(asym):.4f}")
print(f"\nCoherence:")
print(f"  Range: {min(coh):.4f} - {max(coh):.4f}")
print(f"  Mean: {statistics.mean(coh):.4f}")
print(f"  Median: {statistics.median(coh):.4f}")

print(f"\nDistribution by asymmetry bands:")
for threshold in [13.2, 13.4, 13.6, 13.8, 14.0, 14.2, 14.4]:
    count = sum(1 for a in asym if threshold <= a < threshold + 0.2)
    pct = 100 * count / len(asym)
    print(f"  {threshold:.1f}-{threshold+0.2:.1f}: {count:4d} samples ({pct:.1f}%)")

# Find peaks
print(f"\nTop 10 asymmetry values:")
sorted_asym = sorted(asym, reverse=True)
for i, a in enumerate(sorted_asym[:10]):
    print(f"  {i+1}. {a:.4f}")

print(f"\nCorrelation (asymmetry vs coherence):")
if len(asym) > 1:
    mean_a = statistics.mean(asym)
    mean_c = statistics.mean(coh)
    cov = sum((a - mean_a) * (c - mean_c) for a, c in zip(asym, coh)) / len(asym)
    var_a = statistics.variance(asym) if len(asym) > 1 else 0
    var_c = statistics.variance(coh) if len(coh) > 1 else 0
    if var_a > 0 and var_c > 0:
        corr = cov / (var_a * var_c) ** 0.5
        print(f"  Pearson r: {corr:.4f}")
