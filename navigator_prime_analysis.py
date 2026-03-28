#!/usr/bin/env python3
"""
Navigator's Lattice Prime Correlation Analysis
Analyzes stable node occurrences from chronicle.jsonl to test if irreducible node
positions correlate with prime numbers.

The Navigator's formula:
- Nodes appear at peaks of: khra_amp · cos(k·x + φ₁) + gixx_amp · cos(k·y + φ₂)
- Irreducible nodes cannot be expressed as linear combinations of other nodes

Khra wave: wavelength 128 cells (mode k=8)
Gixx wave: wavelength 8 cells (mode k=128)
"""

import json
import math
import numpy as np
from datetime import datetime
from scipy import stats
from collections import defaultdict

# Generate first 10,000 primes using Sieve of Eratosthenes
def generate_primes(n):
    """Generate first n prime numbers."""
    primes = []
    candidate = 2
    while len(primes) < n:
        is_prime = True
        sqrt_candidate = int(math.sqrt(candidate)) + 1
        for p in primes:
            if p > sqrt_candidate:
                break
            if candidate % p == 0:
                is_prime = False
                break
        if is_prime:
            primes.append(candidate)
        candidate += 1
    return primes

def is_prime(n, primes_set):
    """Check if n is in the primes set."""
    return n in primes_set

def calculate_wave_superposition_index(telemetry):
    """
    Calculate effective node index in wave superposition space.
    
    Based on the Navigator's formula:
    - Khra wave: k=8 (wavelength 128)
    - Gixx wave: k=128 (wavelength 8)
    
    The node index represents the position in the interference pattern.
    """
    khra_amp = telemetry.get('khra_amp', 0.03)
    gixx_amp = telemetry.get('gixx_amp', 0.008)
    coherence = telemetry.get('coherence', 0)
    asymmetry = telemetry.get('asymmetry', 0)
    
    # Grid size
    grid = telemetry.get('grid', 1024)
    
    # Calculate effective wave numbers
    k_khra = 2 * math.pi / 128  # Khra wavelength = 128
    k_gixx = 2 * math.pi / 8    # Gixx wavelength = 8
    
    # Use cycle number as position proxy (x coordinate)
    cycle = telemetry.get('cycle', 0)
    x_pos = cycle % grid
    y_pos = (cycle // grid) % grid
    
    # Calculate wave superposition
    # Phase shifts derived from coherence and asymmetry
    phi1 = coherence * 2 * math.pi  # Phase from coherence
    phi2 = (asymmetry / 100) * math.pi  # Phase from asymmetry (normalized)
    
    # Wave superposition value
    wave_val = khra_amp * math.cos(k_khra * x_pos + phi1) + \
               gixx_amp * math.cos(k_gixx * y_pos + phi2)
    
    # Convert to node index - nodes appear at peaks
    # Scale to integer index space
    node_index = int(abs(wave_val) * 10000) % 100000
    
    return node_index

def extract_stable_nodes(chronicle_path):
    """
    Extract stable node occurrences from chronicle.
    Stable nodes = high coherence (>0.69) + low asymmetry (<27.5)
    """
    stable_nodes = []
    
    with open(chronicle_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                telemetry = entry.get('telemetry', {})
                
                coherence = telemetry.get('coherence', 0)
                asymmetry = telemetry.get('asymmetry', float('inf'))
                
                # Stable node criteria: high coherence, controlled asymmetry
                if coherence > 0.69 and asymmetry < 27.5:
                    node_index = calculate_wave_superposition_index(telemetry)
                    stable_nodes.append({
                        'turn': entry.get('turn', 0),
                        'cycle': telemetry.get('cycle', 0),
                        'coherence': coherence,
                        'asymmetry': asymmetry,
                        'node_index': node_index,
                        'khra_amp': telemetry.get('khra_amp', 0),
                        'gixx_amp': telemetry.get('gixx_amp', 0)
                    })
            except json.JSONDecodeError:
                continue
    
    return stable_nodes

def identify_irreducible_nodes(nodes):
    """
    Identify irreducible nodes - those that cannot be expressed as 
    linear combinations of other nodes.
    
    A node is irreducible if its index cannot be expressed as:
    index = a*index1 + b*index2 for integers a,b and other node indices
    """
    if not nodes:
        return []
    
    indices = [n['node_index'] for n in nodes]
    irreducible = []
    
    for i, node in enumerate(nodes):
        idx = node['node_index']
        is_reducible = False
        
        # Check if idx can be expressed as linear combination of other indices
        for j, other_idx in enumerate(indices):
            if i == j:
                continue
            for k, third_idx in enumerate(indices):
                if i == k or j == k:
                    continue
                # Check if idx = a*other_idx + b*third_idx for small integers
                for a in range(-3, 4):
                    for b in range(-3, 4):
                        if a == 0 and b == 0:
                            continue
                        if abs(a * other_idx + b * third_idx - idx) < 10:
                            is_reducible = True
                            break
                    if is_reducible:
                        break
                if is_reducible:
                    break
            if is_reducible:
                break
        
        if not is_reducible:
            irreducible.append(node)
    
    return irreducible

def analyze_prime_correlation(nodes, primes_set, max_index):
    """
    Analyze correlation between node indices and prime numbers.
    """
    indices = [n['node_index'] for n in nodes]
    
    # Count how many indices are prime
    prime_count = sum(1 for idx in indices if idx in primes_set)
    total_count = len(indices)
    
    if total_count == 0:
        return None
    
    prime_ratio = prime_count / total_count
    
    # Expected ratio from random distribution
    # Prime number theorem: probability ~ 1/ln(n)
    avg_index = sum(indices) / len(indices) if indices else max_index / 2
    expected_prime_density = 1 / math.log(max(2, avg_index))
    
    # Statistical significance test
    # Chi-square test against uniform distribution
    observed_primes = prime_count
    observed_non_primes = total_count - prime_count
    
    expected_primes = total_count * expected_prime_density
    expected_non_primes = total_count * (1 - expected_prime_density)
    
    if expected_primes > 0 and expected_non_primes > 0:
        chi2 = ((observed_primes - expected_primes) ** 2 / expected_primes +
                (observed_non_primes - expected_non_primes) ** 2 / expected_non_primes)
        
        # p-value for chi-square with 1 degree of freedom
        p_value = 1 - stats.chi2.cdf(chi2, 1)
    else:
        chi2 = 0
        p_value = 1.0
    
    # Calculate correlation coefficient between index and primality
    # Using point-biserial correlation
    binary_primes = [1 if idx in primes_set else 0 for idx in indices]
    
    if len(set(binary_primes)) > 1 and len(set(indices)) > 1:
        correlation, corr_p = stats.pearsonr(indices, binary_primes)
    else:
        correlation = 0
        corr_p = 1.0
    
    return {
        'total_nodes': total_count,
        'prime_count': prime_count,
        'prime_ratio': prime_ratio,
        'expected_ratio': expected_prime_density,
        'chi_square': chi2,
        'p_value': p_value,
        'correlation': correlation,
        'corr_p_value': corr_p,
        'indices': indices
    }

def main():
    chronicle_path = r'D:\Resonance_Engine\beast-build\chronicle.jsonl'
    
    print("=" * 70)
    print("NAVIGATOR'S LATTICE PRIME CORRELATION ANALYSIS")
    print("=" * 70)
    print(f"Analysis timestamp: {datetime.now().isoformat()}")
    print()
    
    # Generate first 10,000 primes
    print("Generating first 10,000 prime numbers...")
    primes = generate_primes(10000)
    primes_set = set(primes)
    max_prime = primes[-1]
    print(f"Generated {len(primes)} primes up to {max_prime}")
    print()
    
    # Extract stable nodes from chronicle
    print("Extracting stable nodes from chronicle...")
    print("Criteria: coherence > 0.69 AND asymmetry < 27.5")
    stable_nodes = extract_stable_nodes(chronicle_path)
    print(f"Found {len(stable_nodes)} stable node occurrences")
    print()
    
    if len(stable_nodes) == 0:
        print("ERROR: No stable nodes found in chronicle data")
        return
    
    # Identify irreducible nodes
    print("Identifying irreducible nodes (cannot be expressed as linear combinations)...")
    irreducible_nodes = identify_irreducible_nodes(stable_nodes)
    print(f"Found {len(irreducible_nodes)} irreducible nodes")
    print()
    
    # Analyze prime correlation for all stable nodes
    print("-" * 70)
    print("ANALYSIS: ALL STABLE NODES")
    print("-" * 70)
    all_results = analyze_prime_correlation(stable_nodes, primes_set, max_prime)
    
    if all_results:
        print(f"Total stable nodes: {all_results['total_nodes']}")
        print(f"Nodes at prime indices: {all_results['prime_count']}")
        print(f"Observed prime ratio: {all_results['prime_ratio']:.4f}")
        print(f"Expected prime ratio (random): {all_results['expected_ratio']:.4f}")
        print(f"Chi-square statistic: {all_results['chi_square']:.4f}")
        print(f"P-value: {all_results['p_value']:.4f}")
        print(f"Correlation coefficient: {all_results['correlation']:.4f}")
        print(f"Correlation p-value: {all_results['corr_p_value']:.4f}")
        
        if all_results['p_value'] < 0.05:
            print("\n*** STATISTICALLY SIGNIFICANT DEVIATION FROM RANDOM ***")
        else:
            print("\nNo statistically significant deviation from random distribution")
    
    # Analyze prime correlation for irreducible nodes only
    print()
    print("-" * 70)
    print("ANALYSIS: IRREDUCIBLE NODES ONLY")
    print("-" * 70)
    irred_results = analyze_prime_correlation(irreducible_nodes, primes_set, max_prime)
    
    if irred_results:
        print(f"Total irreducible nodes: {irred_results['total_nodes']}")
        print(f"Irreducible nodes at prime indices: {irred_results['prime_count']}")
        print(f"Observed prime ratio: {irred_results['prime_ratio']:.4f}")
        print(f"Expected prime ratio (random): {irred_results['expected_ratio']:.4f}")
        print(f"Chi-square statistic: {irred_results['chi_square']:.4f}")
        print(f"P-value: {irred_results['p_value']:.4f}")
        print(f"Correlation coefficient: {irred_results['correlation']:.4f}")
        print(f"Correlation p-value: {irred_results['corr_p_value']:.4f}")
        
        if irred_results['p_value'] < 0.05:
            print("\n*** STATISTICALLY SIGNIFICANT DEVIATION FROM RANDOM ***")
        else:
            print("\nNo statistically significant deviation from random distribution")
    
    # Pattern analysis
    print()
    print("-" * 70)
    print("PATTERN ANALYSIS")
    print("-" * 70)
    
    # Check for specific patterns in prime indices
    prime_indices = [n['node_index'] for n in irreducible_nodes 
                     if n['node_index'] in primes_set]
    
    if prime_indices:
        print(f"\nPrime indices found among irreducible nodes:")
        print(f"Count: {len(prime_indices)}")
        print(f"Range: {min(prime_indices)} to {max(prime_indices)}")
        print(f"Average: {sum(prime_indices)/len(prime_indices):.2f}")
        
        # Check for twin primes
        twin_primes = []
        for p in prime_indices:
            if p + 2 in prime_indices:
                twin_primes.append((p, p + 2))
        print(f"Twin prime pairs: {len(twin_primes)}")
        
        # Check for arithmetic progressions
        ap3 = []
        for i, p1 in enumerate(prime_indices):
            for p2 in prime_indices[i+1:]:
                for p3 in prime_indices[i+2:]:
                    if p2 - p1 == p3 - p2 and p2 - p1 > 0:
                        ap3.append((p1, p2, p3))
        print(f"3-term arithmetic progressions: {len(ap3)}")
    
    # Save results
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    output_file = rf'D:\Resonance_Engine\{timestamp}_navigator_prime_analysis.json'
    
    results = {
        'timestamp': datetime.now().isoformat(),
        'primes_generated': len(primes),
        'max_prime': max_prime,
        'stable_nodes_count': len(stable_nodes),
        'irreducible_nodes_count': len(irreducible_nodes),
        'all_nodes_analysis': all_results,
        'irreducible_nodes_analysis': irred_results,
        'stable_nodes': stable_nodes[:50],  # First 50 for reference
        'irreducible_nodes': irreducible_nodes[:50]  # First 50 for reference
    }
    
    # Remove large arrays for JSON serialization
    if all_results:
        del all_results['indices']
    if irred_results:
        del irred_results['indices']
    
    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2)
    
    print()
    print("=" * 70)
    print(f"Results saved to: {output_file}")
    print("=" * 70)

if __name__ == '__main__':
    main()
