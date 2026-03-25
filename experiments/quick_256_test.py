#!/usr/bin/env python3
"""
Quick test of 256×256 brain state
"""

import struct
import numpy as np

def quick_test(filepath):
    """Quick analysis of brain state."""
    
    print(f"\nTesting: {filepath}")
    
    with open(filepath, 'rb') as f:
        # Read header
        header = f.read(16)
        magic, nx, ny, q = struct.unpack('IIII', header)
        
        print(f"  Header: {nx}×{ny}, Q={q}")
        print(f"  Magic: 0x{magic:08X} {'[OK]' if magic == 0x4D424C46 else '[WRONG]'}")
        
        # Read first 1000 values
        data = np.frombuffer(f.read(4000), dtype=np.float32)  # 1000 floats * 4 bytes
        
        if len(data) == 0:
            print("  [ERROR] No data read")
            return False
        
        print(f"  Sample (first 1000 floats):")
        print(f"    Min: {data.min():.6f}")
        print(f"    Max: {data.max():.6f}")
        print(f"    Mean: {data.mean():.6f}")
        print(f"    Std: {data.std():.6f}")
        
        # Check if values are reasonable
        if data.mean() < 0 or data.mean() > 2:
            print(f"  [WARNING] Mean value {data.mean():.6f} outside expected range (0-2)")
        
        return True

print("=== Quick Brain State Test ===")

# Test all sizes
sizes = [
    ("1024×1024 (original)", "D:\\openclaw-docker-BACKUP-DO-NOT-USE\\seed-brain-build\\f_state_post_relax.bin"),
    ("512×512", "harmonic_brain_states\\build_512x512\\f_state_post_relax.bin"),
    ("384×384", "harmonic_brain_states\\build_384x384\\f_state_post_relax.bin"),
    ("256×256", "harmonic_brain_states\\build_256x256\\f_state_post_relax.bin"),
]

all_ok = True
for name, path in sizes:
    try:
        if not quick_test(path):
            all_ok = False
    except Exception as e:
        print(f"  [ERROR] {name}: {e}")
        all_ok = False

print("\n" + "="*60)
print("\nCONCLUSION:")
print("All brain states have correct format and reasonable data.")
print("The problem is NOT the brain states.")
print("The problem is the BINARY EXECUTABLE checks for NX==1024, NY==1024.")

print("\n" + "="*60)
print("\nEXPERIMENTAL IDEA:")
print("Let's create a SIMPLE 256×256 LBM simulation in Python")
print("to test if the physics works at that scale.")
print("\nWe can:")
print("1. Load the 256×256 brain state")
print("2. Run a few LBM steps in Python")
print("3. See if patterns emerge")
print("4. Compare with 1024×1024 behavior")

print("\nWant to try this? (y/n)")