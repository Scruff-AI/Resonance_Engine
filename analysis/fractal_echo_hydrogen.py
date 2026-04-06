#!/usr/bin/env python3
"""
Fractal Echo Analysis - Find hydrogen-like series in sweep data
Look for phi-harmonic ratios and energy level patterns
"""
import csv
import math

PHI = 1.618033988749895

def load_sweep_data():
    """Load sweep data, skipping duplicate headers."""
    data = []
    with open('/mnt/d/Resonance_Engine/beast-build/sweep_results.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row['value'] == 'value':  # Skip dup headers
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

def find_coherence_peaks(omega_data):
    """Find omega values where coherence peaks (energy levels)."""
    peaks = []
    for i, d in enumerate(omega_data):
        if d['coh_mean'] > 0.731:  # Above collapse threshold
            # Check if local maximum
            prev_coh = omega_data[i-1]['coh_mean'] if i > 0 else 0
            next_coh = omega_data[i+1]['coh_mean'] if i < len(omega_data)-1 else 0
            if d['coh_mean'] >= prev_coh and d['coh_mean'] >= next_coh:
                peaks.append(d)
    return peaks

def check_phi_harmonics(values):
    """Check for phi-harmonic (1.618) relationships."""
    matches = []
    for i, v1 in enumerate(values):
        for v2 in values[i+1:]:
            ratio = v2 / v1 if v1 > 0 else 0
            # Check phi, phi^2, 1/phi
            for target in [PHI, PHI**2, 1/PHI, 2*PHI]:
                if abs(ratio - target) < 0.05:
                    matches.append((v1, v2, ratio, target))
    return matches

def hydrogen_energy_ratio(n1, n2):
    """Calculate hydrogen energy ratio for transition n2 -> n1."""
    return abs(1/n1**2 - 1/n2**2)

def main():
    print("=" * 70)
    print("FRACTAL ECHO ANALYSIS - HYDROGEN SERIES HUNT")
    print("=" * 70)
    
    data = load_sweep_data()
    print(f"\nLoaded {len(data)} sweep records")
    
    # Omega sweep analysis
    omega_data = [d for d in data if d['parameter'] == 'omega']
    omega_data.sort(key=lambda x: x['value'])
    
    print(f"\nOmega sweep: {len(omega_data)} points")
    print("-" * 70)
    
    # Show all omega points with coherence
    print("\nFull Omega Sweep (looking for energy levels):")
    for d in omega_data:
        marker = " ***" if d['coh_mean'] > 0.731 else ""
        print(f"  Omega {d['value']:.2f}: Coh={d['coh_mean']:.4f}{marker}")
    
    # Find coherence peaks (energy level candidates)
    peaks = find_coherence_peaks(omega_data)
    
    print("\n" + "=" * 70)
    print("COHERENCE PEAKS (Energy Level Candidates)")
    print("=" * 70)
    
    if not peaks:
        print("\nNo clear peaks found. Using top coherence values...")
        omega_data.sort(key=lambda x: x['coh_mean'], reverse=True)
        peaks = omega_data[:5]
    
    peak_omegas = []
    for p in peaks:
        print(f"  Omega {p['value']:.4f}: Coh={p['coh_mean']:.4f}, Asym={p['asym_mean']:.4f}")
        peak_omegas.append(p['value'])
    
    # Check phi-harmonic relationships
    print("\n" + "=" * 70)
    print("PHI-HARMONIC RELATIONSHIPS (1.618)")
    print("=" * 70)
    
    phi_matches = check_phi_harmonics(peak_omegas)
    if phi_matches:
        for v1, v2, ratio, target in phi_matches:
            print(f"  {v1:.4f} -> {v2:.4f}: ratio={ratio:.4f} (target: {target:.4f})")
    else:
        print("  No phi-harmonic matches found in peaks")
    
    # Check all omega values for phi relationships
    all_omegas = [d['value'] for d in omega_data]
    print("\n  Checking all omega values...")
    phi_matches = check_phi_harmonics(all_omegas)
    if phi_matches:
        print(f"  Found {len(phi_matches)} phi-harmonic pairs:")
        for v1, v2, ratio, target in phi_matches[:10]:
            print(f"    {v1:.4f} -> {v2:.4f}: ratio={ratio:.4f}")
    
    # Hydrogen series check
    print("\n" + "=" * 70)
    print("HYDROGEN ENERGY SERIES CHECK")
    print("=" * 70)
    
    hydrogen_ratios = {
        'Lyman-α (2→1)': hydrogen_energy_ratio(1, 2),
        'Lyman-β (3→1)': hydrogen_energy_ratio(1, 3),
        'Balmer-α (3→2)': hydrogen_energy_ratio(2, 3),
        'Balmer-β (4→2)': hydrogen_energy_ratio(2, 4),
        'Paschen-α (4→3)': hydrogen_energy_ratio(3, 4),
    }
    
    print("\nHydrogen transition ratios:")
    for name, ratio in hydrogen_ratios.items():
        print(f"  {name}: {ratio:.6f}")
    
    # Check if coherence differences match hydrogen
    print("\n  Checking coherence differences...")
    coh_values = [d['coh_mean'] for d in omega_data]
    for i in range(len(coh_values)-1):
        for j in range(i+1, len(coh_values)):
            diff = abs(coh_values[j] - coh_values[i])
            for name, h_ratio in hydrogen_ratios.items():
                if abs(diff - h_ratio) < 0.01:
                    print(f"    Match: Coh diff {diff:.6f} ≈ {name} ({h_ratio:.6f})")
    
    print("\n" + "=" * 70)
    print("INTERPRETATION")
    print("=" * 70)
    print("""
If the lattice shows phi-harmonic or hydrogen-like ratios,
the energy quantization is geometric/harmonic, not arbitrary.

The fractal echo would appear as self-similar ratios across scales.
""")

if __name__ == '__main__':
    main()
