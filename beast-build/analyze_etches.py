# Etch Analysis Script
# Compare 49 etches from 10k to 490k steps

import os
import struct
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

NX = 512
NY = 512

def load_etch(filename):
    """Load etch file and return rho, ux, uy arrays"""
    with open(filename, 'rb') as f:
        rho = np.frombuffer(f.read(NX * NY * 4), dtype=np.float32).reshape(NY, NX)
        ux = np.frombuffer(f.read(NX * NY * 4), dtype=np.float32).reshape(NY, NX)
        uy = np.frombuffer(f.read(NX * NY * 4), dtype=np.float32).reshape(NY, NX)
    return rho, ux, uy

def calculate_entropy(ux, uy):
    """Calculate velocity-based entropy"""
    uu = ux**2 + uy**2
    return np.mean(uu)

def calculate_variance(rho):
    """Calculate density variance"""
    return np.var(rho)

def calculate_coherence(ux, uy):
    """Calculate velocity coherence (mean flow magnitude)"""
    u_mag = np.sqrt(ux**2 + uy**2)
    return np.mean(u_mag)

def calculate_spectral_complexity(ux, uy):
    """Calculate spectral entropy as complexity measure"""
    # FFT of velocity magnitude
    u_mag = np.sqrt(ux**2 + uy**2)
    fft = np.fft.fft2(u_mag)
    power = np.abs(fft)**2
    # Normalize
    power = power / np.sum(power)
    # Spectral entropy
    spectral_entropy = -np.sum(power * np.log2(power + 1e-10))
    return spectral_entropy

def main():
    etch_dir = r'D:\fractal-brain\beast-build'
    
    # Collect all etches
    etches = []
    for i in range(1, 50):
        step = i * 10000
        filename = os.path.join(etch_dir, f'etch_{step:08d}.bin')
        if os.path.exists(filename):
            etches.append((step, filename))
    
    print(f"Found {len(etches)} etches")
    print("=" * 60)
    
    # Analyze each etch
    results = []
    for step, filename in etches:
        rho, ux, uy = load_etch(filename)
        
        entropy = calculate_entropy(ux, uy)
        variance = calculate_variance(rho)
        coherence = calculate_coherence(ux, uy)
        spectral = calculate_spectral_complexity(ux, uy)
        
        results.append({
            'step': step,
            'entropy': entropy,
            'variance': variance,
            'coherence': coherence,
            'spectral': spectral
        })
        
        print(f"Step {step:6d}: entropy={entropy:8.4f} variance={variance:10.6f} coherence={coherence:8.4f} spectral={spectral:8.2f}")
    
    # Plot trends
    steps = [r['step'] for r in results]
    entropies = [r['entropy'] for r in results]
    variances = [r['variance'] for r in results]
    coherences = [r['coherence'] for r in results]
    spectrals = [r['spectral'] for r in results]
    
    fig, axes = plt.subplots(2, 2, figsize=(12, 10))
    
    # Entropy trend
    axes[0, 0].plot(steps, entropies, 'b-', linewidth=2)
    axes[0, 0].set_xlabel('Step')
    axes[0, 0].set_ylabel('Entropy')
    axes[0, 0].set_title('Entropy Evolution (49 Etches)')
    axes[0, 0].grid(True, alpha=0.3)
    
    # Variance trend
    axes[0, 1].plot(steps, variances, 'r-', linewidth=2)
    axes[0, 1].set_xlabel('Step')
    axes[0, 1].set_ylabel('Variance')
    axes[0, 1].set_title('Density Variance Evolution')
    axes[0, 1].grid(True, alpha=0.3)
    
    # Coherence trend
    axes[1, 0].plot(steps, coherences, 'g-', linewidth=2)
    axes[1, 0].set_xlabel('Step')
    axes[1, 0].set_ylabel('Coherence (Mean Velocity)')
    axes[1, 0].set_title('Flow Coherence Evolution')
    axes[1, 0].grid(True, alpha=0.3)
    
    # Spectral complexity
    axes[1, 1].plot(steps, spectrals, 'm-', linewidth=2)
    axes[1, 1].set_xlabel('Step')
    axes[1, 1].set_ylabel('Spectral Entropy')
    axes[1, 1].set_title('Spectral Complexity (Structure)')
    axes[1, 1].grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig('etch_analysis.png', dpi=150)
    print("\nSaved: etch_analysis.png")
    
    # Summary statistics
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"Entropy:    {entropies[0]:.4f} -> {entropies[-1]:.4f} (delta = {entropies[-1] - entropies[0]:+.4f})")
    print(f"Variance:   {variances[0]:.6f} -> {variances[-1]:.6f} (delta = {variances[-1] - variances[0]:+.6f})")
    print(f"Coherence:  {coherences[0]:.4f} -> {coherences[-1]:.4f} (delta = {coherences[-1] - coherences[0]:+.4f})")
    print(f"Spectral:   {spectrals[0]:.2f} -> {spectrals[-1]:.2f} (delta = {spectrals[-1] - spectrals[0]:+.2f})")
    
    # Check for trends
    from scipy import stats
    entropy_slope, _, _, _, _ = stats.linregress(steps, entropies)
    variance_slope, _, _, _, _ = stats.linregress(steps, variances)
    coherence_slope, _, _, _, _ = stats.linregress(steps, coherences)
    spectral_slope, _, _, _, _ = stats.linregress(steps, spectrals)
    
    print(f"\nTrends (per 10k steps):")
    print(f"  Entropy slope:    {entropy_slope:.6f}")
    print(f"  Variance slope:   {variance_slope:.8f}")
    print(f"  Coherence slope:  {coherence_slope:.6f}")
    print(f"  Spectral slope:   {spectral_slope:.4f}")
    
    # Compare early vs late
    early = results[:5]  # 10k-50k
    late = results[-5:]  # 450k-490k
    
    print(f"\nEarly (10k-50k) vs Late (450k-490k):")
    print(f"  Entropy:  {np.mean([e['entropy'] for e in early]):.4f} → {np.mean([e['entropy'] for e in late]):.4f}")
    print(f"  Variance: {np.mean([e['variance'] for e in early]):.6f} → {np.mean([e['variance'] for e in late]):.6f}")
    print(f"  Spectral: {np.mean([e['spectral'] for e in early]):.2f} → {np.mean([e['spectral'] for e in late]):.2f}")

if __name__ == '__main__':
    main()
