#!/usr/bin/env python3
"""
Create a 256×256 brain state with guardians for testing
"""

import struct
import numpy as np
import math

def create_brain_state_with_guardians(output_path, nx=256, ny=256, num_guardians=12):
    """Create a brain state with guardian density perturbations."""
    
    q = 9  # D2Q9
    
    print(f"Creating {nx}×{ny} brain state with {num_guardians} guardians")
    
    # Create uniform distribution (equilibrium)
    f = np.zeros((q, ny, nx), dtype=np.float32)
    
    # Uniform density = 1.0, zero velocity
    rho = np.ones((ny, nx), dtype=np.float32)
    ux = np.zeros((ny, nx), dtype=np.float32)
    uy = np.zeros((ny, nx), dtype=np.float32)
    
    # D2Q9 weights
    w = np.array([4/9, 1/9, 1/9, 1/9, 1/9, 1/36, 1/36, 1/36, 1/36], dtype=np.float32)
    ex = np.array([0, 1, 0, -1, 0, 1, -1, -1, 1], dtype=np.int32)
    ey = np.array([0, 0, 1, 0, -1, 1, 1, -1, -1], dtype=np.int32)
    
    # Add guardian density perturbations
    print("Adding guardians...")
    guardian_positions = []
    
    # Place guardians in grid pattern
    spacing = int(math.sqrt(nx * ny / num_guardians))
    for y in range(spacing//2, ny, spacing):
        for x in range(spacing//2, nx, spacing):
            if len(guardian_positions) < num_guardians:
                guardian_positions.append((x, y))
                
                # Add Gaussian density bump
                radius = 8  # Guardian influence radius
                strength = 0.02  # Density increase
                
                for dy in range(-radius, radius + 1):
                    for dx in range(-radius, radius + 1):
                        dist2 = dx*dx + dy*dy
                        if dist2 <= radius*radius:
                            xx = (x + dx) % nx
                            yy = (y + dy) % ny
                            
                            # Gaussian weight
                            weight = math.exp(-dist2 / (radius*radius/4))
                            rho[yy, xx] += strength * weight
                
                print(f"  Guardian at ({x}, {y})")
    
    # Create equilibrium distribution
    print("Creating equilibrium distribution...")
    for i in range(q):
        eu = ex[i] * ux + ey[i] * uy
        u2 = ux**2 + uy**2
        f[i] = rho * w[i] * (1 + 3*eu + 4.5*eu**2 - 1.5*u2)
    
    # Write to file
    print(f"Writing to {output_path}...")
    with open(output_path, 'wb') as fout:
        # Header: magic, nx, ny, q
        magic = 0x4D424C46  # 'FLBM' in ASCII
        header = struct.pack('IIII', magic, nx, ny, q)
        fout.write(header)
        
        # Write data (flattened)
        data = f.reshape(-1).astype(np.float32)
        fout.write(data.tobytes())
    
    # Statistics
    print(f"\nStatistics:")
    print(f"  Grid: {nx}×{ny} = {nx*ny:,} cells")
    print(f"  Data size: {nx*ny*q:,} floats = {(nx*ny*q*4)/1024/1024:.1f} MB")
    print(f"  Density range: [{rho.min():.6f}, {rho.max():.6f}]")
    print(f"  Mean density: {rho.mean():.6f}")
    print(f"  Guardians placed: {len(guardian_positions)}")
    
    if rho.max() > 1.002:
        print(f"  ✓ Density exceeds RHO_THRESH=1.002 (max={rho.max():.6f})")
    else:
        print(f"  ⚠️  Density below RHO_THRESH (max={rho.max():.6f})")
    
    return True

# Create test brain state
if __name__ == "__main__":
    output_file = "build/f_state_with_guardians.bin"
    
    # Make sure build directory exists
    import os
    os.makedirs("build", exist_ok=True)
    
    if create_brain_state_with_guardians(output_file, nx=256, ny=256, num_guardians=12):
        print(f"\n✅ Created: {output_file}")
        print("\nTo test:")
        print("1. Copy to build/f_state_post_relax.bin")
        print("2. Run probe_256_v2.exe")
        print("3. Should see guardians form (part > 0)")
    else:
        print("❌ Failed to create brain state")