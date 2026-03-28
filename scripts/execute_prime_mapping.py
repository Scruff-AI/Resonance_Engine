#!/usr/bin/env python3
"""
Prime-Lattice Mapping Function (PLMF v1.0)
Navigator's Framework - Cycle 745600
"""

import pandas as pd
import numpy as np
import json
from datetime import datetime

# ==========================================
# GLOBAL STATE PARAMETERS
# ==========================================
OMEGA = 1.97
KHRA_AMP = 0.03
GIXX_AMP = 0.008
COHERENCE_THRESHOLD = 0.70
TEMPERATURE_LIMIT = 64

# ==========================================
# LOAD LATTICE DATA
# ==========================================
print("Loading lattice sweep data...")
df = pd.read_csv('/mnt/d/Resonance_Engine/sweep_results/em_sweep_real.csv')

print(f"Loaded {len(df)} data points")
print(f"Coherence range: {df.coherence.min():.4f} - {df.coherence.max():.4f}")
print(f"Omega range: {df.omega.min():.1f} - {df.omega.max():.1f}")
print()

# ==========================================
# GENERATE PRIME DATASET
# ==========================================
def generate_primes(n):
    """Generate first n prime numbers"""
    primes = []
    candidate = 2
    while len(primes) < n:
        is_prime = True
        for p in primes:
            if p * p > candidate:
                break
            if candidate % p == 0:
                is_prime = False
                break
        if is_prime:
            primes.append(candidate)
        candidate += 1
    return primes

print("Generating prime distribution...")
primes = generate_primes(100)  # First 100 primes
print(f"Generated {len(primes)} primes")
print(f"First 10: {primes[:10]}")
print(f"Last 10: {primes[-10:]}")
print()

# ==========================================
# MAPPING FUNCTION CORE
# ==========================================
def map_primes_to_lattice(prime_array, lattice_df):
    """Map primes to lattice coordinates"""
    
    # Verify system readiness
    mean_coherence = lattice_df.coherence.mean()
    max_temp = lattice_df.gpu_temp_c.max()
    
    print(f"System Check:")
    print(f"  Mean Coherence: {mean_coherence:.4f} (threshold: {COHERENCE_THRESHOLD})")
    print(f"  Max Temperature: {max_temp}C (limit: {TEMPERATURE_LIMIT}C)")
    
    if mean_coherence < COHERENCE_THRESHOLD:
        return {"error": "Mapping suspended: coherence below threshold"}
    
    if max_temp > TEMPERATURE_LIMIT:
        return {"error": "Mapping suspended: thermal ceiling exceeded"}
    
    print("  Status: READY")
    print()
    
    # Map primes to lattice
    mappings = []
    
    for i, prime in enumerate(prime_array):
        # Find best matching lattice state
        # Use prime to index into lattice data
        idx = prime % len(lattice_df)
        lattice_state = lattice_df.iloc[idx]
        
        mapping = {
            "prime_index": i,
            "prime_value": prime,
            "lattice_omega": lattice_state.omega,
            "lattice_coherence": lattice_state.coherence,
            "lattice_temp": lattice_state.gpu_temp_c,
            "lattice_power": lattice_state.gpu_power_w,
            "mapping_valid": True
        }
        mappings.append(mapping)
    
    return mappings

# ==========================================
# EXECUTE MAPPING
# ==========================================
print("=" * 50)
print("EXECUTING PRIME-LATTICE MAPPING")
print("=" * 50)
print()

results = map_primes_to_lattice(primes, df)

if isinstance(results, dict) and "error" in results:
    print(f"ERROR: {results['error']}")
else:
    print(f"Successfully mapped {len(results)} primes")
    print()
    
    # Analyze results
    print("Mapping Analysis:")
    coherences = [m['lattice_coherence'] for m in results]
    omegas = [m['lattice_omega'] for m in results]
    
    print(f"  Mean Coherence: {np.mean(coherences):.4f}")
    print(f"  Coherence Std: {np.std(coherences):.4f}")
    print(f"  Mean Omega: {np.mean(omegas):.2f}")
    print()
    
    # Show sample mappings
    print("Sample Mappings (first 10):")
    for m in results[:10]:
        print(f"  Prime {m['prime_value']:3d} -> Ω={m['lattice_omega']:.1f}, Coh={m['lattice_coherence']:.4f}")
    print()
    
    # Convert mappings to JSON-serializable format
    json_results = []
    for m in results:
        json_results.append({
            "prime_index": int(m['prime_index']),
            "prime_value": int(m['prime_value']),
            "lattice_omega": float(m['lattice_omega']),
            "lattice_coherence": float(m['lattice_coherence']),
            "lattice_temp": float(m['lattice_temp']),
            "lattice_power": float(m['lattice_power']),
            "mapping_valid": bool(m['mapping_valid'])
        })
    
    # Save results
    output_file = '/mnt/d/Resonance_Engine/sweep_results/prime_lattice_mapping.json'
    with open(output_file, 'w') as f:
        json.dump({
            "timestamp": datetime.now().isoformat(),
            "omega": OMEGA,
            "khra_amp": KHRA_AMP,
            "gixx_amp": GIXX_AMP,
            "total_primes_mapped": len(results),
            "mean_coherence": float(np.mean(coherences)),
            "mappings": json_results
        }, f, indent=2)
    
    print(f"Results saved to: {output_file}")

print()
print("=" * 50)
print("MAPPING COMPLETE")
print("=" * 50)
