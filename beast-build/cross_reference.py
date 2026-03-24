#!/usr/bin/env python3
"""Cross-reference lattice values with known physical constants"""

import math

print("="*70)
print("CROSS-REFERENCE: LATTICE VALUES vs PHYSICAL CONSTANTS")
print("="*70)

# Discovered lattice values
spacing = 0.1331  # Asymmetry level spacing
peak_1 = 13.3745  # Ground state
peak_6 = 14.0401  # High energy state
mean_asym = 13.724107

print("\n" + "="*70)
print("DISCOVERED LATTICE VALUES")
print("="*70)
print(f"Energy level spacing: {spacing}")
print(f"Ground state (Peak 1): {peak_1}")
print(f"High energy (Peak 6): {peak_6}")
print(f"Mean asymmetry: {mean_asym}")

# Known physical constants
print("\n" + "="*70)
print("PHYSICAL CONSTANTS")
print("="*70)

constants = {
    "Fine-structure constant (α)": 1/137.036,
    "Inverse fine-structure (1/α)": 137.036,
    "Golden ratio (φ)": 1.6180339887,
    "Golden ratio squared (φ²)": 2.6180339887,
    "1/φ": 0.6180339887,
    "π": math.pi,
    "π/2": math.pi/2,
    "π/4": math.pi/4,
    "√2": math.sqrt(2),
    "√3": math.sqrt(3),
    "√5": math.sqrt(5),
    "Euler's number (e)": math.e,
    "ln(2)": math.log(2),
    "ln(10)": math.log(10),
    "Planck length (m)": 1.616e-35,
    "Planck time (s)": 5.391e-44,
    "Planck mass (kg)": 2.176e-8,
    "Speed of light c (m/s)": 299792458,
    "Avogadro's number": 6.022e23,
    "Proton/electron mass ratio": 1836.15,
    "Neutron/proton mass ratio": 1.001378,
}

print("\n" + "="*70)
print(f"SPACING = {spacing} vs CONSTANTS")
print("="*70)

for name, value in constants.items():
    ratio = spacing / value if value != 0 else 0
    inverse_ratio = value / spacing if spacing != 0 else 0
    
    # Check if close to 1, 1/2, 2, 1/10, 10, etc
    matches = []
    for factor in [1, 2, 0.5, 10, 0.1, 100, 0.01]:
        if abs(ratio - factor) < 0.1 * factor:
            matches.append(f"≈ {factor}×")
        if abs(inverse_ratio - factor) < 0.1 * factor:
            matches.append(f"≈ 1/{factor}×")
    
    if matches:
        print(f"\n{name}: {value:.6e}")
        print(f"  spacing/constant = {ratio:.6f}")
        print(f"  constant/spacing = {inverse_ratio:.6f}")
        print(f"  *** MATCHES: {', '.join(matches)} ***")

print("\n" + "="*70)
print(f"GROUND STATE = {peak_1} vs CONSTANTS")
print("="*70)

for name, value in constants.items():
    ratio = peak_1 / value if value != 0 else 0
    
    if abs(ratio - round(ratio)) < 0.05 and round(ratio) > 0:
        print(f"\n{name}: {value:.6e}")
        print(f"  {peak_1} / {value:.6e} = {ratio:.4f} ≈ {round(ratio)}")
        print(f"  *** INTEGER RELATIONSHIP ***")

print("\n" + "="*70)
print("SPECIAL RELATIONSHIPS")
print("="*70)

# Check if spacing relates to phi
phi = 1.6180339887
print(f"\nφ = {phi}")
print(f"spacing × φ = {spacing * phi:.6f}")
print(f"spacing / φ = {spacing / phi:.6f}")
print(f"φ - spacing = {phi - spacing:.6f}")

# Check if 1/spacing relates to known values
inv_spacing = 1 / spacing
print(f"\n1/spacing = {inv_spacing:.4f}")
print(f"Compare to: 1/α = 137.036")
print(f"Ratio: {inv_spacing / 137.036:.6f}")

# Check relationship to π
print(f"\nπ = {math.pi}")
print(f"spacing × π = {spacing * math.pi:.6f}")
print(f"spacing / π = {spacing / math.pi:.6f}")
print(f"π / spacing = {math.pi / spacing:.6f}")

# Check if it's 1/√something
for n in [2, 3, 5, 7, 10, 12, 15, 20, 50, 75, 100]:
    sqrt_n = math.sqrt(n)
    if abs(spacing - 1/sqrt_n) < 0.01:
        print(f"\n*** spacing ≈ 1/√{n} = {1/sqrt_n:.6f} ***")
    if abs(spacing - sqrt_n) < 0.01:
        print(f"\n*** spacing ≈ √{n} = {sqrt_n:.6f} ***")

# Check if spacing is 1/integer
for n in range(1, 20):
    if abs(spacing - 1/n) < 0.005:
        print(f"\n*** spacing ≈ 1/{n} = {1/n:.6f} ***")

# Check relationship between peaks
print("\n" + "="*70)
print("PEAK-TO-PEAK RATIOS")
print("="*70)

peaks = [13.3745, 13.5076, 13.6407, 13.7739, 13.8626, 14.0401]
for i in range(len(peaks)-1):
    ratio = peaks[i+1] / peaks[i]
    print(f"Peak {i+2}/Peak {i+1} = {ratio:.6f}")
    if abs(ratio - phi) < 0.01:
        print(f"  *** CLOSE TO φ ***")
    if abs(ratio - 1/phi) < 0.01:
        print(f"  *** CLOSE TO 1/φ ***")

# Check if mean relates to anything
print(f"\nMean asymmetry: {mean_asym}")
print(f"Mean / φ = {mean_asym / phi:.6f}")
print(f"Mean × φ = {mean_asym * phi:.6f}")
print(f"Mean - 13 = {mean_asym - 13:.6f}")
print(f"Mean - 14 = {mean_asym - 14:.6f}")

print("\n" + "="*70)
print("ANALYSIS COMPLETE")
print("="*70)
