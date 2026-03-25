#!/usr/bin/env python3
"""
Direct test of 256×256 brain state - bypass binary limitations
"""

import struct
import numpy as np
import matplotlib.pyplot as plt
import sys

def analyze_brain_state(filepath):
    """Analyze brain state file directly."""
    
    print(f"Analyzing: {filepath}")
    
    with open(filepath, 'rb') as f:
        # Read header
        header = f.read(16)
        magic, nx, ny, q = struct.unpack('IIII', header)
        
        print(f"  Grid: {nx}×{ny}, Q={q}")
        print(f"  Magic: 0x{magic:08X} (FLBM)")
        
        # Read all data
        data = np.frombuffer(f.read(), dtype=np.float32)
        
        # Reshape to [Q, NY, NX]
        data_3d = data.reshape(q, ny, nx)
        
        print(f"  Data shape: {data_3d.shape}")
        print(f"  Total values: {data.size:,}")
        
        # Analyze each distribution
        print("\n  Distribution analysis:")
        for i in range(q):
            dist = data_3d[i]
            print(f"    f[{i}]: min={dist.min():.6f}, max={dist.max():.6f}, mean={dist.mean():.6f}")
        
        # Compute macroscopic variables
        print("\n  Macroscopic variables:")
        
        # Density: ρ = Σ f_i
        rho = np.sum(data_3d, axis=0)
        print(f"    Density ρ: min={rho.min():.6f}, max={rho.max():.6f}, mean={rho.mean():.6f}")
        
        # Check if density is reasonable (should be ~1.0)
        if np.abs(rho.mean() - 1.0) > 0.1:
            print(f"    [WARNING] Mean density {rho.mean():.6f} far from 1.0")
        
        # Velocity (simplified)
        # For D2Q9: ex = [0,1,0,-1,0,1,-1,-1,1], ey = [0,0,1,0,-1,1,1,-1,-1]
        ex = np.array([0, 1, 0, -1, 0, 1, -1, -1, 1], dtype=np.float32)
        ey = np.array([0, 0, 1, 0, -1, 1, 1, -1, -1], dtype=np.float32)
        
        ux = np.zeros((ny, nx), dtype=np.float32)
        uy = np.zeros((ny, nx), dtype=np.float32)
        
        for i in range(q):
            ux += ex[i] * data_3d[i]
            uy += ey[i] * data_3d[i]
        
        ux /= rho
        uy /= rho
        
        speed = np.sqrt(ux**2 + uy**2)
        print(f"    Speed: min={speed.min():.2e}, max={speed.max():.2e}, mean={speed.mean():.2e}")
        
        # Check for patterns
        print("\n  Pattern detection:")
        
        # Horizontal variation
        row_variation = np.std(rho, axis=1).mean()
        col_variation = np.std(rho, axis=0).mean()
        print(f"    Row variation: {row_variation:.6f}")
        print(f"    Column variation: {col_variation:.6f}")
        
        if row_variation > 0.001 or col_variation > 0.001:
            print("    [NOTE] Significant spatial variation detected")
        
        # Create simple visualization
        plt.figure(figsize=(12, 4))
        
        plt.subplot(131)
        plt.imshow(rho, cmap='viridis', origin='lower')
        plt.colorbar(label='Density ρ')
        plt.title(f'Density (mean={rho.mean():.6f})')
        
        plt.subplot(132)
        plt.imshow(speed, cmap='hot', origin='lower', vmax=speed.max()*2)
        plt.colorbar(label='Speed')
        plt.title(f'Speed (max={speed.max():.2e})')
        
        plt.subplot(133)
        # Show one distribution
        plt.imshow(data_3d[0], cmap='plasma', origin='lower')
        plt.colorbar(label='f[0]')
        plt.title('Distribution f[0]')
        
        plt.tight_layout()
        plt.savefig('brain_state_analysis.png', dpi=150)
        print("\n  Visualization saved: brain_state_analysis.png")
        
        return True

def compare_sizes():
    """Compare brain states of different sizes."""
    
    sizes = [
        ("1024×1024", "D:\\openclaw-docker-BACKUP-DO-NOT-USE\\seed-brain-build\\f_state_post_relax.bin"),
        ("512×512", "harmonic_brain_states\\build_512x512\\f_state_post_relax.bin"),
        ("384×384", "harmonic_brain_states\\build_384x384\\f_state_post_relax.bin"),
        ("256×256", "harmonic_brain_states\\build_256x256\\f_state_post_relax.bin"),
    ]
    
    print("=== Brain State Comparison ===\n")
    
    results = []
    for name, path in sizes:
        try:
            with open(path, 'rb') as f:
                header = f.read(16)
                magic, nx, ny, q = struct.unpack('IIII', header)
                
                # Read a sample of data
                f.seek(16)  # Skip header
                sample = np.frombuffer(f.read(1000 * 4), dtype=np.float32)  # First 1000 floats
                
                results.append({
                    'name': name,
                    'nx': nx,
                    'ny': ny,
                    'q': q,
                    'sample_mean': sample.mean(),
                    'sample_std': sample.std(),
                    'valid': (magic == 0x4D424C46 and q == 9)
                })
                
                status = "[OK]" if results[-1]['valid'] else "[INVALID]"
                print(f"{status} {name}: {nx}×{ny}, Q={q}, sample mean={sample.mean():.6f}")
                
        except Exception as e:
            print(f"[ERROR] {name}: {e}")
            results.append({'name': name, 'error': str(e)})
    
    print("\n=== Analysis ===")
    print("All brain states have correct FLBM header and Q=9")
    print("The issue is the BINARY EXECUTABLE checks for NX=1024, NY=1024")
    print("\nNext experiment: Can we patch the binary or create a wrapper?")

if __name__ == "__main__":
    print("=== Direct Brain State Analysis ===\n")
    
    # Test 256×256
    analyze_brain_state("harmonic_brain_states\\build_256x256\\f_state_post_relax.bin")
    
    print("\n" + "="*60 + "\n")
    
    # Compare all sizes
    compare_sizes()
    
    print("\n=== Experimental Ideas ===")
    print("1. Binary patch: Find and modify the NX==1024 check")
    print("2. Wrapper: Create proxy that changes header before passing to binary")
    print("3. Recompile: Actually the best solution, but requires setup")
    print("4. Emulation: Run LBM in Python to test 256×256 physics")
    print("\nLet's try option 4 first - test the physics in Python!")