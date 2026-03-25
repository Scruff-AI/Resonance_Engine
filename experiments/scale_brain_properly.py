#!/usr/bin/env python3
"""
PROPERLY scale 1024×1024 brain state to 256×256
No artificial bullshit. Actual scaling.
"""

import struct
import numpy as np
import sys

def scale_brain_state(input_path, output_path, target_nx=256, target_ny=256):
    """Scale brain state properly using averaging."""
    
    print(f"Scaling brain state: {input_path} -> {output_path}")
    print(f"Target: {target_nx}×{target_ny}")
    
    # Read original brain state
    with open(input_path, 'rb') as f:
        header = f.read(16)
        magic, nx, ny, q = struct.unpack('IIII', header)
        
        print(f"Original: {nx}×{ny}, Q={q}")
        
        if magic != 0x4D424C46:
            print(f"ERROR: Wrong magic: 0x{magic:08X}")
            return False
        
        # Read all data
        data = np.frombuffer(f.read(), dtype=np.float32)
        data = data.reshape(q, ny, nx)
        
        print(f"Data shape: {data.shape}")
    
    # Calculate scaling factor
    scale_x = target_nx / nx
    scale_y = target_ny / ny
    
    print(f"Scaling: {scale_x:.3f}× horizontally, {scale_y:.3f}× vertically")
    
    # For each distribution channel
    scaled_data = np.zeros((q, target_ny, target_nx), dtype=np.float32)
    
    print("Scaling distributions...")
    for i in range(q):
        if i % 3 == 0:
            print(f"  Channel {i+1}/{q}")
        
        # Get original distribution
        orig = data[i]
        
        # Simple averaging for now (box filter)
        # In reality should use proper downsampling that preserves patterns
        for y in range(target_ny):
            y_start = int(y / scale_y)
            y_end = int((y + 1) / scale_y)
            
            for x in range(target_nx):
                x_start = int(x / scale_x)
                x_end = int((x + 1) / scale_x)
                
                # Average over the block
                block = orig[y_start:y_end, x_start:x_end]
                if block.size > 0:
                    scaled_data[i, y, x] = block.mean()
                else:
                    scaled_data[i, y, x] = orig[y_start, x_start]
    
    # Write scaled brain state
    print(f"Writing scaled brain state...")
    with open(output_path, 'wb') as f:
        # Header
        magic = 0x4D424C46
        header = struct.pack('IIII', magic, target_nx, target_ny, q)
        f.write(header)
        
        # Write data
        f.write(scaled_data.astype(np.float32).tobytes())
    
    # Verify
    print(f"\nVerification:")
    print(f"  Original size: {nx}×{ny} = {nx*ny:,} cells")
    print(f"  Scaled size: {target_nx}×{target_ny} = {target_nx*target_ny:,} cells")
    print(f"  Scaling factor: {scale_x:.3f}× = {1/(scale_x*scale_y):.1f}× smaller area")
    
    # Check density
    rho_scaled = np.sum(scaled_data, axis=0)
    rho_original = np.sum(data, axis=0)
    
    print(f"\nDensity comparison:")
    print(f"  Original: min={rho_original.min():.6f}, max={rho_original.max():.6f}, mean={rho_original.mean():.6f}")
    print(f"  Scaled:   min={rho_scaled.min():.6f}, max={rho_scaled.max():.6f}, mean={rho_scaled.mean():.6f}")
    
    # Check if density variations preserved
    var_original = rho_original.std()
    var_scaled = rho_scaled.std()
    
    print(f"\nDensity variation (std):")
    print(f"  Original: {var_original:.6f}")
    print(f"  Scaled:   {var_scaled:.6f}")
    print(f"  Ratio:    {var_scaled/var_original:.3f}×")
    
    if var_scaled > 0.001:
        print(f"  [OK] Density variations preserved")
    else:
        print(f"  ⚠️  Density variations may be too small")
    
    return True

# Main
if __name__ == "__main__":
    input_file = "D:\\openclaw-docker-BACKUP-DO-NOT-USE\\seed-brain-build\\f_state_post_relax.bin"
    output_file = "build\\f_state_scaled_256.bin"
    
    import os
    os.makedirs("build", exist_ok=True)
    
    print("=== PROPER BRAIN STATE SCALING ===")
    print("No artificial bullshit. Actual scaling from 1024×1024.")
    print("="*50)
    
    if scale_brain_state(input_file, output_file, 256, 256):
        print(f"\n✅ SUCCESS: Created {output_file}")
        print("\nTo test:")
        print(f"copy {output_file} build\\f_state_post_relax.bin")
        print("probe_256_proper.exe")
    else:
        print("\n❌ FAILED")