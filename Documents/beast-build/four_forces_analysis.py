#!/usr/bin/env python3
"""
Four Forces Correlation Analysis
Test Navigator's claims against telemetry data.
"""
import json
import math
import sys

TELEMETRY_PATH = "/mnt/d/Resonance_Engine/beast-build/telemetry.jsonl"
SAMPLE_SIZE = 50000  # Analyze last N records for speed

def load_telemetry(n=SAMPLE_SIZE):
    """Load last n telemetry records."""
    records = []
    with open(TELEMETRY_PATH, 'r') as f:
        for line in f:
            records.append(json.loads(line.strip()))
    return records[-n:]

def pearsonr(x, y):
    """Calculate Pearson correlation coefficient."""
    n = len(x)
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    
    num = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    den_x = sum((xi - mean_x) ** 2 for xi in x)
    den_y = sum((yi - mean_y) ** 2 for yi in y)
    
    if den_x == 0 or den_y == 0:
        return 0, 1
    
    r = num / math.sqrt(den_x * den_y)
    
    # Approximate p-value (rough estimate for large n)
    if abs(r) >= 1:
        p = 0
    else:
        t = r * math.sqrt((n - 2) / (1 - r * r))
        # For large n, approximate p as very small if |r| > 0.1
        p = 0 if abs(r) > 0.1 else 1
    
    return r, p

def mean(arr):
    return sum(arr) / len(arr)

def std(arr):
    m = mean(arr)
    return math.sqrt(sum((x - m) ** 2 for x in arr) / len(arr))

def percentile(arr, p):
    sorted_arr = sorted(arr)
    k = (len(sorted_arr) - 1) * p / 100
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return sorted_arr[int(k)]
    return sorted_arr[int(f)] * (c - k) + sorted_arr[int(c)] * (k - f)

def analyze_gravity(data):
    """
    Test: Gravity \u2014 velocity follows density curvature
    Claim: v \u221d \u2207(\u2207\u00b2\u03c1)
    Proxy: vel_mean should correlate with coherence (as proxy for density structure)
    """
    vel = [d['vel_mean'] for d in data]
    coh = [d['coherence'] for d in data]
    
    # Correlation
    r, p = pearsonr(vel, coh)
    
    print("=" * 60)
    print("GRAVITY: Geodesic Motion Test")
    print("=" * 60)
    print(f"Claim: velocity follows density curvature")
    print(f"Proxy test: vel_mean vs coherence")
    print(f"  Correlation r = {r:.4f}")
    print(f"  Significant: {'YES' if abs(r) > 0.1 else 'NO'}")
    print(f"  Effect size: {'Strong' if abs(r) > 0.5 else 'Moderate' if abs(r) > 0.3 else 'Weak'}")
    return r, p

def analyze_em(data):
    """
    Test: Electromagnetism \u2014 stress tensor conserves momentum
    Claim: \u2202_\u03bc \u03c3^\u03bc\u03bd = 0 \u2192 stress_xx \u2248 -stress_yy
    """
    sxx = [d['stress_xx'] for d in data]
    syy = [d['stress_yy'] for d in data]
    sxy = [d['stress_xy'] for d in data]
    
    # Conservation test: sxx + syy should be near zero
    conservation = [x + y for x, y in zip(sxx, syy)]
    mean_cons = mean(conservation)
    std_cons = std(conservation)
    
    # Anti-correlation test
    r, p = pearsonr(sxx, syy)
    
    print("\n" + "=" * 60)
    print("ELECTROMAGNETISM: Momentum Conservation Test")
    print("=" * 60)
    print(f"Claim: stress_xx \u2248 -stress_yy (momentum conservation)")
    print(f"  stress_xx mean: {mean(sxx):.6f}")
    print(f"  stress_yy mean: {mean(syy):.6f}")
    print(f"  sxx + syy mean: {mean_cons:.6f} (should be ~0)")
    print(f"  sxx + syy std:  {std_cons:.6f}")
    print(f"  Anti-correlation r = {r:.4f}")
    print(f"  Conservation holds: {'YES' if abs(mean_cons) < 0.0001 else 'PARTIAL' if abs(mean_cons) < 0.001 else 'NO'}")
    return r, p, mean_cons

def analyze_strong(data):
    """
    Test: Strong Force \u2014 confinement at Gixx wavelength (8 cells)
    Claim: Strong coupling at short range, freedom at long range
    Proxy: Coherence vs Gixx amplitude correlation
    """
    coh = [d['coherence'] for d in data]
    gixx = [d['gixx_amp'] for d in data]
    
    r, p = pearsonr(coh, gixx)
    
    # Also check if high coherence requires non-zero gixx
    p75 = percentile(coh, 75)
    high_coh_count = sum(1 for c in coh if c > p75)
    high_coh_with_gixx = sum(1 for c, g in zip(coh, gixx) if c > p75 and g >= 0.005)
    confinement_ratio = high_coh_with_gixx / high_coh_count if high_coh_count > 0 else 0
    
    print("\n" + "=" * 60)
    print("STRONG FORCE: Confinement Test")
    print("=" * 60)
    print(f"Claim: Gixx wave (\u03bb=8) creates confinement")
    print(f"  Coherence vs Gixx amplitude r = {r:.4f}")
    print(f"  High coherence requires Gixx > 0.005: {confinement_ratio*100:.1f}% of cases")
    print(f"  Confinement signature: {'PRESENT' if confinement_ratio > 0.7 else 'WEAK' if confinement_ratio > 0.5 else 'ABSENT'}")
    return r, p, confinement_ratio

def analyze_weak(data):
    """
    Test: Weak Force \u2014 parity violation via asymmetry
    Claim: Asymmetry measures left-right imbalance (chevron handedness)
    """
    asym = [d['asymmetry'] for d in data]
    
    # Check if asymmetry is systematically non-zero
    asym_mean = mean(asym)
    asym_std = std(asym)
    # Rough t-test: if mean > 3*std/sqrt(n), it's significant
    n = len(asym)
    sem = asym_std / math.sqrt(n)
    t_stat = asym_mean / sem if sem > 0 else 0
    p_val = 0 if abs(t_stat) > 3 else 1  # Rough approximation
    
    # Check correlation with omega (should affect parity violation)
    omega = [d['omega'] for d in data]
    r, p = pearsonr(asym, omega)
    
    print("\n" + "=" * 60)
    print("WEAK FORCE: Parity Violation Test")
    print("=" * 60)
    print(f"Claim: Asymmetry measures spontaneous parity violation")
    print(f"  Asymmetry mean: {asym_mean:.4f}")
    print(f"  Asymmetry std:  {asym_std:.4f}")
    print(f"  t-statistic: {t_stat:.2f}")
    print(f"  Systematically non-zero: {'YES' if abs(t_stat) > 3 else 'NO'}")
    print(f"  Asymmetry vs Omega r = {r:.4f} (tunable violation)")
    print(f"  Parity violation: {'CONFIRMED' if abs(t_stat) > 3 else 'ABSENT'}")
    return t_stat, p_val, r

def main():
    print("Loading telemetry...")
    data = load_telemetry()
    print(f"Loaded {len(data)} records")
    
    # Run all four tests
    gravity_r, gravity_p = analyze_gravity(data)
    em_r, em_p, em_cons = analyze_em(data)
    strong_r, strong_p, strong_conf = analyze_strong(data)
    weak_t, weak_p, weak_r = analyze_weak(data)
    
    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY: Navigator's Claims vs Data")
    print("=" * 60)
    
    forces = [
        ("Gravity", abs(gravity_r) > 0.3),
        ("EM", abs(em_r) > 0.5 and abs(em_cons) < 0.001),
        ("Strong", strong_conf > 0.7),
        ("Weak", abs(weak_t) > 3)
    ]
    
    for force, confirmed in forces:
        status = "\u2713 CONFIRMED" if confirmed else "\u2717 NOT CONFIRMED"
        print(f"  {force:12s}: {status}")
    
    confirmed_count = sum(1 for _, c in forces if c)
    print(f"\n{confirmed_count}/4 forces supported by data")
    
    if confirmed_count == 4:
        print("\nNavigator's perception MATCHES the data.")
    elif confirmed_count >= 2:
        print("\nNavigator's perception PARTIALLY MATCHES the data.")
    else:
        print("\nNavigator's perception DOES NOT MATCH the data.")

if __name__ == "__main__":
    main()