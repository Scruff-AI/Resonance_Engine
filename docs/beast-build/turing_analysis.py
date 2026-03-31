#!/usr/bin/env python3
"""
Turing Pattern Analysis - Mine existing data for fractal echo signatures
FFT of snapshots, sweep correlation analysis, scale invariance check
"""
import json
import numpy as np
from PIL import Image
import os
import glob

SWEEP_PATH = "/mnt/d/Resonance_Engine/beast-build/sweep_results.csv"
SNAPSHOT_DIRS = [
    "/mnt/d/Resonance_Engine/beast-build/cymatics_sweep",
    "/mnt/d/Resonance_Engine/beast-build/chladni_sweep",
    "/mnt/d/Resonance_Engine/sri_yantra_output",
    "/mnt/d/Resonance_Engine/cymatics_output",
    "/mnt/d/Resonance_Engine/turing_test"
]

def analyze_snapshot_fft(image_path):
    """Analyze spatial frequency content of snapshot."""
    try:
        img = Image.open(image_path).convert('L')  # Grayscale
        arr = np.array(img, dtype=np.float32)
        
        # 2D FFT
        fft = np.fft.fft2(arr)
        fft_shift = np.fft.fftshift(fft)
        magnitude = np.abs(fft_shift)
        
        # Radial average (power spectrum)
        h, w = magnitude.shape
        center = (h//2, w//2)
        
        # Create radial bins
        y, x = np.ogrid[:h, :w]
        r = np.sqrt((x-center[1])**2 + (y-center[0])**2).astype(int)
        
        radial_sum = np.bincount(r.ravel(), magnitude.ravel())
        radial_count = np.bincount(r.ravel())
        radial_profile = radial_sum / (radial_count + 1e-10)
        
        # Find peaks (characteristic wavelengths)
        peaks = []
        for i in range(2, len(radial_profile)-2):
            if radial_profile[i] > radial_profile[i-1] and radial_profile[i] > radial_profile[i+1]:
                if radial_profile[i] > np.mean(radial_profile) * 1.5:  # Significant peak
                    wavelength_pixels = max(h, w) / i if i > 0 else 0
                    peaks.append((i, wavelength_pixels, radial_profile[i]))
        
        return {
            'filename': os.path.basename(image_path),
            'size': arr.shape,
            'dominant_wavelengths': peaks[:3],  # Top 3 peaks
            'total_power': np.sum(magnitude)
        }
    except Exception as e:
        return {'filename': os.path.basename(image_path), 'error': str(e)}

def load_sweep_data():
    """Load parameter sweep data."""
    import csv
    data = []
    with open(SWEEP_PATH, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                # Skip header rows that got duplicated
                if row['value'] == 'value':
                    continue
                data.append({
                    'parameter': row['parameter'],
                    'value': float(row['value']),
                    'coh_mean': float(row['coh_mean']),
                    'asym_mean': float(row['asym_mean']),
                    'vort_mean': float(row['vort_mean']),
                    'vel_var_mean': float(row['vel_var_mean'])
                })
            except (ValueError, KeyError):
                continue
    return data

def find_turing_candidates(sweep_data):
    """Find sweep parameters that might produce Turing patterns."""
    # Turing patterns typically have:
    # - Intermediate coherence (not fully ordered, not chaotic)
    # - Intermediate asymmetry (broken symmetry but stable)
    # - Higher vorticity (rotational structures)
    
    candidates = []
    for d in sweep_data:
        # Turing "sweet spot": coherence 0.72-0.74, asymmetry 12.5-13.5
        if 0.72 <= d['coh_mean'] <= 0.74 and 12.5 <= d['asym_mean'] <= 13.5:
            if d['vort_mean'] > 0.02:  # Significant rotation
                candidates.append(d)
    
    return candidates

def check_scale_invariance():
    """Check if patterns are self-similar across scales."""
    print("\n" + "="*70)
    print("SCALE INVARIANCE CHECK (Fractal Echo)")
    print("="*70)
    
    # Find all snapshots
    all_snapshots = []
    for dir_path in SNAPSHOT_DIRS:
        if os.path.exists(dir_path):
            pngs = glob.glob(f"{dir_path}/*.png")
            all_snapshots.extend(pngs)
    
    print(f"\nFound {len(all_snapshots)} snapshots")
    
    if len(all_snapshots) < 2:
        print("Insufficient snapshots for comparison")
        return
    
    # Analyze FFT of each
    print("\nAnalyzing spatial frequency content...")
    fft_results = []
    for snapshot in all_snapshots[:10]:  # Limit to first 10
        result = analyze_snapshot_fft(snapshot)
        fft_results.append(result)
        if 'dominant_wavelengths' in result and result['dominant_wavelengths']:
            print(f"\n{result['filename']}:")
            for peak in result['dominant_wavelengths']:
                freq_bin, wavelength, power = peak
                print(f"  Peak at wavelength ~{wavelength:.1f} pixels (power={power:.2e})")
    
    # Check for common wavelengths (fractal echo)
    all_wavelengths = []
    for r in fft_results:
        if 'dominant_wavelengths' in r:
            for peak in r['dominant_wavelengths']:
                all_wavelengths.append(peak[1])
    
    if all_wavelengths:
        print(f"\nWavelength distribution:")
        print(f"  Range: {min(all_wavelengths):.1f} - {max(all_wavelengths):.1f} pixels")
        
        # Look for power-of-2 relationships (fractal echo)
        print(f"\n  Checking for fractal echo (power-of-2 relationships)...")
        for i, w1 in enumerate(all_wavelengths):
            for w2 in all_wavelengths[i+1:]:
                ratio = max(w1, w2) / min(w1, w2)
                # Check if ratio is close to 2, 4, 8, etc.
                for power in [2, 4, 8, 16]:
                    if abs(ratio - power) < 0.3:
                        print(f"    Found: {min(w1,w2):.1f} x {power} ≈ {max(w1,w2):.1f}")

def analyze_sweep_for_turing():
    """Analyze sweep data for Turing pattern signatures."""
    print("="*70)
    print("SWEEP DATA ANALYSIS - TURING CANDIDATES")
    print("="*70)
    
    sweep_data = load_sweep_data()
    print(f"\nLoaded {len(sweep_data)} sweep records")
    
    # Find candidates
    candidates = find_turing_candidates(sweep_data)
    print(f"\nFound {len(candidates)} Turing pattern candidates:")
    print("  (Coherence 0.72-0.74, Asymmetry 12.5-13.5, Vorticity > 0.02)")
    
    for c in candidates[:10]:  # Show first 10
        print(f"\n  {c['parameter']} = {c['value']:.4f}:")
        print(f"    Coherence: {c['coh_mean']:.4f}")
        print(f"    Asymmetry: {c['asym_mean']:.4f}")
        print(f"    Vorticity: {c['vort_mean']:.4f}")
        print(f"    Velocity variance: {c['vel_var_mean']:.6f}")
    
    # Check khra_amp specifically
    print("\n" + "="*70)
    print("KHRA AMPLITUDE SWEEP - DETAILED")
    print("="*70)
    
    khra_data = [d for d in sweep_data if d['parameter'] == 'khra_amp']
    khra_data.sort(key=lambda x: x['value'])
    
    print(f"\nTesting {len(khra_data)} Khra values...")
    for d in khra_data:
        marker = "*** TURING CANDIDATE ***" if d in candidates else ""
        print(f"  Khra {d['value']:.4f}: Coh {d['coh_mean']:.4f}, Asym {d['asym_mean']:.4f} {marker}")

def main():
    print("="*70)
    print("TURING PATTERN ANALYSIS - FRACTAL ECHO SEARCH")
    print("="*70)
    
    # Analyze sweep data
    analyze_sweep_for_turing()
    
    # Check snapshots for scale invariance
    check_scale_invariance()
    
    print("\n" + "="*70)
    print("ANALYSIS COMPLETE")
    print("="*70)
    print("\nKey findings:")
    print("  1. Turing candidates identified in sweep data")
    print("  2. Spatial frequency analysis of snapshots")
    print("  3. Fractal echo (scale invariance) check")
    print("\nReview the candidate parameters above.")

if __name__ == '__main__':
    main()
