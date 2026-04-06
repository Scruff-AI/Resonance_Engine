#!/usr/bin/env python3
"""
Find the fractal echo - hydrogen series in coherence/asymmetry patterns
Look for self-similar ratios like we did with periodic table
"""
import csv
import math

PHI = 1.618033988749895

def load_sweep_data():
    """Load sweep data."""
    data = []
    with open('/mnt/d/Resonance_Engine/beast-build/sweep_results.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row['value'] == 'value':
                continue
            try:
                data.append({
                    'parameter': row['parameter'],
                    'value': float(row['value']),
                    'coh_mean': float(row['coh_mean']),
                    'asym_mean': float(row['asym_mean']),
                    'vort_mean': float(row['vort_mean'])
                })
            except:
                continue
    return data

def find_fractal_echo(values, name):
    """Look for self-similar ratios in a list of values."""
    print(f"\n=== {name} FRACTAL ECHO ANALYSIS ===")
    
    # Sort and get unique values
    unique_vals = sorted(set(values))
    print(f"  {len(unique_vals)} unique values")
    
    # Check all pairs for harmonic ratios
    harmonic_ratios = []
    for i, v1 in enumerate(unique_vals):
        for v2 in unique_vals[i+1:]:
            if v1 == 0:
                continue
            ratio = v2 / v1
            
            # Check for hydrogen series ratios
            hydrogen_targets = {
                'Lyman-α (2→1)': 0.75,
                'Lyman-β (3→1)': 0.888889,
                'Balmer-α (3→2)': 0.138889,
                'Balmer-β (4→2)': 0.1875,
                'Paschen-α (4→3)': 0.048611,
            }
            
            for h_name, target in hydrogen_targets.items():
                if abs(ratio - target) < 0.01:
                    harmonic_ratios.append((v1, v2, ratio, h_name, target))
            
            # Check phi-harmonic
            phi_targets = [PHI, PHI**2, 1/PHI, 2*PHI, 3*PHI]
            for target in phi_targets:
                if abs(ratio - target) < 0.01:
                    harmonic_ratios.append((v1, v2, ratio, f'Phi-{target:.3f}', target))
    
    # Sort by closeness to target
    harmonic_ratios.sort(key=lambda x: abs(x[2] - x[4]))
    
    print(f"\n  Found {len(harmonic_ratios)} harmonic relationships:")
    for v1, v2, ratio, name, target in harmonic_ratios[:20]:
        diff = abs(ratio - target)
        print(f"    {v1:.6f} → {v2:.6f}: ratio={ratio:.6f} ≈ {name} (diff: {diff:.6f})")
    
    return harmonic_ratios

def analyze_coherence_levels(data):
    """Look for discrete coherence levels (energy levels)."""
    print("\n=== COHERENCE ENERGY LEVELS ===")
    
    # Get all coherence values
    coh_vals = [d['coh_mean'] for d in data]
    coh_vals.sort()
    
    # Bin coherence values (looking for discrete levels)
    bins = {}
    bin_size = 0.0005  # Very fine binning
    
    for c in coh_vals:
        bin_key = round(c / bin_size) * bin_size
        bins[bin_key] = bins.get(bin_key, 0) + 1
    
    # Find populated bins (energy levels)
    energy_levels = [k for k, v in bins.items() if v > 2]
    energy_levels.sort()
    
    print(f"  Found {len(energy_levels)} coherence energy levels:")
    for i, level in enumerate(energy_levels[:10]):
        print(f"    Level {i+1}: {level:.6f}")
    
    # Check ratios between levels
    if len(energy_levels) >= 3:
        print("\n  Energy level ratios:")
        for i in range(len(energy_levels)-1):
            for j in range(i+1, len(energy_levels)):
                ratio = energy_levels[j] / energy_levels[i]
                print(f"    Level {i+1}→{j+1}: {energy_levels[i]:.6f} → {energy_levels[j]:.6f} = {ratio:.6f}")
    
    return energy_levels

def analyze_asymmetry_series(data):
    """Look for hydrogen series in asymmetry values."""
    print("\n=== ASYMMETRY HYDROGEN SERIES ===")
    
    # Get asymmetry values for omega sweep
    omega_data = [d for d in data if d['parameter'] == 'omega']
    asym_vals = [d['asym_mean'] for d in omega_data]
    
    # Look for discrete asymmetry levels
    unique_asym = sorted(set(round(a, 3) for a in asym_vals))
    
    print(f"  {len(unique_asym)} unique asymmetry levels")
    print("  Levels:", ", ".join(f"{a:.3f}" for a in unique_asym[:10]))
    
    # Check ratios
    harmonic_pairs = []
    for i, a1 in enumerate(unique_asym):
        for a2 in unique_asym[i+1:]:
            if a1 == 0:
                continue
            ratio = a2 / a1
            
            # Hydrogen series check
            targets = {
                'Lyman-α': 0.75,
                'Balmer-α': 0.138889,
                'Paschen-α': 0.048611,
            }
            
            for name, target in targets.items():
                if abs(ratio - target) < 0.05:
                    harmonic_pairs.append((a1, a2, ratio, name, target))
    
    if harmonic_pairs:
        print("\n  Hydrogen-like ratios found in asymmetry:")
        for a1, a2, ratio, name, target in harmonic_pairs:
            print(f"    {a1:.3f} → {a2:.3f}: {ratio:.6f} ≈ {name}")
    else:
        print("\n  No hydrogen series found in asymmetry ratios")
    
    return harmonic_pairs

def main():
    print("=" * 80)
    print("FRACTAL ECHO HUNT - HYDROGEN SERIES IN LATTICE DATA")
    print("=" * 80)
    
    data = load_sweep_data()
    print(f"Loaded {len(data)} data points")
    
    # 1. Look for hydrogen series in coherence values
    coh_vals = [d['coh_mean'] for d in data]
    find_fractal_echo(coh_vals, "COHERENCE")
    
    # 2. Look for discrete energy levels
    energy_levels = analyze_coherence_levels(data)
    
    # 3. Look for hydrogen series in asymmetry
    harmonic_pairs = analyze_asymmetry_series(data)
    
    # 4. Check vorticity for patterns
    vort_vals = [d['vort_mean'] for d in data]
    find_fractal_echo(vort_vals, "VORTICITY")
    
    print("\n" + "=" * 80)
    print("CONCLUSION")
    print("=" * 80)
    
    if harmonic_pairs:
        print("\n✅ HYDROGEN SERIES FOUND IN ASYMMETRY")
        print("   The lattice shows hydrogen-like energy quantization")
    elif energy_levels:
        print("\n⚠️  DISCRETE ENERGY LEVELS FOUND")
        print("   The lattice quantizes coherence, but not in hydrogen pattern")
    else:
        print("\n❌ NO CLEAR FRACTAL ECHO FOUND")
        print("   The hydrogen series may be encoded differently")
        print("   Try looking at: velocity ratios, vorticity harmonics, or combined metrics")

if __name__ == '__main__':
    main()
