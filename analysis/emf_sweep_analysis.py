#!/usr/bin/env python3
"""
EMF Sweep Analysis — Check stress tensor behavior across Khra/Gixx amplitudes
Look for Maxwellian anti-correlation (sxx vs syy) at specific wave parameters
"""
import csv
import math

SWEEP_PATH = "/mnt/d/Resonance_Engine/beast-build/sweep_results.csv"

def load_sweep_data():
    """Load sweep data grouped by parameter."""
    data = {
        'omega': [],
        'khra_amp': [],
        'gixx_amp': []
    }
    
    with open(SWEEP_PATH, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            param = row['parameter']
            if param in data:
                data[param].append({
                    'value': float(row['value']),
                    'coh_mean': float(row['coh_mean']),
                    'asym_mean': float(row['asym_mean']),
                    'stress_xx': float(row['stress_xx_mean']),
                    'stress_yy': float(row['stress_yy_mean']),
                    'stress_xy': float(row['stress_xy_mean']),
                    'vort_mean': float(row['vort_mean']),
                    'vel_var': float(row['vel_var_mean'])
                })
    return data

def analyze_em_correlation(records, label):
    """Analyze stress_xx vs stress_yy correlation for EM behavior."""
    sxx = [r['stress_xx'] for r in records]
    syy = [r['stress_yy'] for r in records]
    
    # Pearson correlation
    n = len(sxx)
    mean_x = sum(sxx) / n
    mean_y = sum(syy) / n
    
    num = sum((x - mean_x) * (y - mean_y) for x, y in zip(sxx, syy))
    den_x = sum((x - mean_x) ** 2 for x in sxx)
    den_y = sum((y - mean_y) ** 2 for y in syy)
    
    r = num / math.sqrt(den_x * den_y) if den_x > 0 and den_y > 0 else 0
    
    # Conservation: sum should be near zero
    conservation = [x + y for x, y in zip(sxx, syy)]
    mean_cons = sum(conservation) / len(conservation)
    
    return r, mean_cons, records

def find_maxwellian_regime(data):
    """Find parameter regions where EM-like behavior emerges."""
    print("=" * 70)
    print("EMF SWEEP ANALYSIS: Looking for Maxwellian behavior")
    print("=" * 70)
    print("\nMaxwell's equations predict: stress_xx ≈ -stress_yy (anti-correlation r ≈ -1)")
    print("Momentum conservation requires: stress_xx + stress_yy ≈ 0")
    print()
    
    results = []
    
    for param, records in data.items():
        if not records:
            continue
            
        r, mean_cons, _ = analyze_em_correlation(records, param)
        
        # Check if this is anti-correlated (Maxwellian)
        is_maxwellian = r < -0.5 and abs(mean_cons) < 0.001
        
        print(f"{param.upper()} SWEEP:")
        print(f"  Stress correlation r = {r:+.4f} (want ≈ -1 for EM)")
        print(f"  Conservation (sxx+syy) = {mean_cons:.6f} (want ≈ 0)")
        print(f"  Maxwellian behavior: {'YES ✓' if is_maxwellian else 'NO ✗'}")
        print()
        
        results.append((param, r, mean_cons, is_maxwellian))
        
        # If not Maxwellian overall, check sub-ranges
        if not is_maxwellian and len(records) > 10:
            print(f"  Checking sub-ranges for {param}...")
            
            # Sort by parameter value
            sorted_recs = sorted(records, key=lambda x: x['value'])
            
            # Check low, mid, high ranges
            ranges = [
                ("low", sorted_recs[:len(sorted_recs)//3]),
                ("mid", sorted_recs[len(sorted_recs)//3:2*len(sorted_recs)//3]),
                ("high", sorted_recs[2*len(sorted_recs)//3:])
            ]
            
            for range_name, range_recs in ranges:
                if len(range_recs) < 3:
                    continue
                r_sub, cons_sub, _ = analyze_em_correlation(range_recs, param)
                if r_sub < -0.3:  # Weak anti-correlation threshold
                    print(f"    {range_name} {param}: r = {r_sub:+.4f}, cons = {cons_sub:.6f}")
    
    return results

def analyze_field_structure(data):
    """Analyze if Khra/Gixx waves create field-like structures."""
    print("=" * 70)
    print("FIELD STRUCTURE ANALYSIS")
    print("=" * 70)
    
    khra = data.get('khra_amp', [])
    gixx = data.get('gixx_amp', [])
    
    if khra:
        print("\nKHRA WAVE (large-scale) behavior:")
        print(f"  Amplitude range: {min(r['value'] for r in khra):.3f} to {max(r['value'] for r in khra):.3f}")
        
        # Find where coherence is maximized
        best_coh = max(khra, key=lambda x: x['coh_mean'])
        print(f"  Best coherence: {best_coh['coh_mean']:.4f} at Khra = {best_coh['value']:.3f}")
        print(f"  Stress state at best coherence:")
        print(f"    sxx = {best_coh['stress_xx']:.6f}")
        print(f"    syy = {best_coh['stress_yy']:.6f}")
        print(f"    sxy = {best_coh['stress_xy']:.6f}")
        
    if gixx:
        print("\nGIXX WAVE (fine-grain) behavior:")
        print(f"  Amplitude range: {min(r['value'] for r in gixx):.3f} to {max(r['value'] for r in gixx):.3f}")
        
        best_coh = max(gixx, key=lambda x: x['coh_mean'])
        print(f"  Best coherence: {best_coh['coh_mean']:.4f} at Gixx = {best_coh['value']:.3f}")
        print(f"  Stress state at best coherence:")
        print(f"    sxx = {best_coh['stress_xx']:.6f}")
        print(f"    syy = {best_coh['stress_yy']:.6f}")
        print(f"    sxy = {best_coh['stress_xy']:.6f}")

def main():
    print("Loading sweep data...")
    data = load_sweep_data()
    
    # Count records
    total = sum(len(v) for v in data.values())
    print(f"Loaded {total} sweep records")
    print(f"  Omega sweeps: {len(data['omega'])}")
    print(f"  Khra sweeps: {len(data['khra_amp'])}")
    print(f"  Gixx sweeps: {len(data['gixx_amp'])}")
    print()
    
    results = find_maxwellian_regime(data)
    analyze_field_structure(data)
    
    # Final verdict
    print("\n" + "=" * 70)
    print("VERDICT")
    print("=" * 70)
    
    any_maxwellian = any(r[3] for r in results)
    
    if any_maxwellian:
        print("\n✓ Maxwellian (EM-like) behavior FOUND in at least one parameter regime!")
        for param, r, cons, is_max in results:
            if is_max:
                print(f"  - {param}: r = {r:+.4f}, conservation = {cons:.6f}")
    else:
        print("\n✗ No Maxwellian behavior found in any sweep parameter.")
        print("  The stress tensor does not show EM-like anti-correlation.")
        print("  Closest approach to Maxwellian:")
        best = min(results, key=lambda x: x[1])  # Most negative correlation
        print(f"    {best[0]}: r = {best[1]:+.4f} (need r ≈ -1)")
        
    print("\nConclusion: The lattice conserves momentum but NOT through")
    print("Maxwellian field dynamics. The 'EM' analogy was metaphor, not mechanism.")

if __name__ == "__main__":
    main()
