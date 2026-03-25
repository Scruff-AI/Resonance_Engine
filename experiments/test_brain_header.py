#!/usr/bin/env python3
"""
Test brain state header verification.
Check if 256×256 brain states have correct format.
"""

import struct
import os

def check_brain_state(filepath):
    """Check brain state header."""
    if not os.path.exists(filepath):
        print(f"[ERROR] File not found: {filepath}")
        return False
    
    with open(filepath, 'rb') as f:
        # Read header (4 uint32: magic, NX, NY, Q)
        header = f.read(16)
        if len(header) != 16:
            print(f"❌ Header too short: {len(header)} bytes")
            return False
        
        magic, nx, ny, q = struct.unpack('IIII', header)
        
        # Check magic number (0x4D424C46 = 'FLBM' in ASCII)
        expected_magic = 0x4D424C46
        if magic != expected_magic:
            print(f"❌ Wrong magic: 0x{magic:08X} (expected 0x{expected_magic:08X})")
            return False
        
        # Check Q (should be 9 for D2Q9)
        if q != 9:
            print(f"❌ Wrong Q: {q} (expected 9)")
            return False
        
        # Calculate expected file size
        expected_size = 16 + (nx * ny * q * 4)  # header + float32 data
        
        # Get actual file size
        f.seek(0, 2)  # Seek to end
        actual_size = f.tell()
        
        print(f"[OK] Header OK: {filepath}")
        print(f"   NX: {nx}, NY: {ny}, Q: {q}")
        print(f"   Grid size: {nx}×{ny} = {nx*ny:,} cells")
        print(f"   Data size: {nx*ny*q:,} floats = {(nx*ny*q*4)/1024/1024:.1f} MB")
        print(f"   Total file size: {actual_size:,} bytes")
        print(f"   Expected size: {expected_size:,} bytes")
        
        if actual_size == expected_size:
            print(f"   [OK] File size matches")
        else:
            print(f"   [WARN] File size mismatch: {actual_size - expected_size:,} bytes difference")
        
        return True

# Test all brain states
print("=== Testing Brain State Headers ===\n")

# Test 256×256
check_brain_state("harmonic_brain_states/build_256x256/f_state_post_relax.bin")
print()

# Test 512×512  
check_brain_state("harmonic_brain_states/build_512x512/f_state_post_relax.bin")
print()

# Test 384×384
check_brain_state("harmonic_brain_states/build_384x384/f_state_post_relax.bin")
print()

# Test original 1024×1024
check_brain_state("D:\\openclaw-docker-BACKUP-DO-NOT-USE\\seed-brain-build\\f_state_post_relax.bin")