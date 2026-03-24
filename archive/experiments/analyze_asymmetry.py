#!/usr/bin/env python3
"""Analyze asymmetry data for phase transition thresholds"""

import json
import glob
from collections import Counter

# Read all status files
files = glob.glob('/mnt/d/fractal-brain/beast-build/sweep_results/run_*_status.json')

asymmetries = []
for f in files:
    try:
        with open(f) as fp:
            data = json.load(fp)
            asym = data.get('asymmetry')
            if asym and 10 < asym < 20:  # Filter real values
                asymmetries.append(asym)
    except:
        pass

asymmetries.sort()

print(f"Total samples: {len(asymmetries)}")
print(f"Range: {min(asymmetries):.4f} to {max(asymmetries):.4f}")
print()

# Find gaps (phase transitions)
print("=== GAPS (potential phase transitions) ===")
for i in range(1, len(asymmetries)):
    diff = asymmetries[i] - asymmetries[i-1]
    if diff > 0.05:  # Threshold for gap
        print(f"Gap: {asymmetries[i-1]:.4f} -> {asymmetries[i]:.4f} (diff: {diff:.4f})")

print()

# Cluster analysis
print("=== CLUSTERS ===")
rounded = [round(a, 1) for a in asymmetries]
counts = Counter(rounded)
for val, count in sorted(counts.items()):
    print(f"Asymmetry ~{val}: {count} samples")

print()

# Look for phi-related thresholds
phi = 1.6180339887
print(f"=== PHI-RELATED THRESHOLDS ===")
print(f"phi = {phi}")
print(f"phi^2 = {phi**2:.4f}")
print(f"1/phi = {1/phi:.4f}")
print(f"phi/10 = {phi/10:.4f}")

# Check if asymmetry clusters around phi multiples
for base in [13.0, 13.5, 14.0]:
    phi_multiple = base * phi / 10
    print(f"\nBase {base} * phi/10 = {phi_multiple:.4f}")
    close = [a for a in asymmetries if abs(a - phi_multiple) < 0.1]
    if close:
        print(f"  Matches: {len(close)} samples near {phi_multiple:.4f}")
