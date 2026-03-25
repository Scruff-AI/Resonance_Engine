#!/usr/bin/env python3
"""
Scale brain state from 1024x1024 to smaller grid sizes.
Empirical scaling - let the system adapt from there.
"""
import struct
import numpy as np
import sys
import os

def read_brain_state(input_path):
    """Read FLBM brain state file"""
    with open(input_path, 'rb') as f:
        # Read header: magic(4), NX(4), NY(4), Q(4)
        header = f.read(16)
        if len(header) < 16:
            raise ValueError("File too small for header")
        
        magic, NX, NY, Q = struct.unpack('IIII', header)
        if magic != 0x4D424C46:  # 'FLBM' in hex
            raise ValueError(f"Invalid magic: 0x{magic:08X}, expected 0x4D424C46")
        
        print(f"Original: {NX}x{NY}, Q={Q}")
        
        # Read data: Q * NX * NY floats
        total_cells = Q * NX * NY
        data = np.fromfile(f, dtype=np.float32, count=total_cells)
        
        if len(data) != total_cells:
            raise ValueError(f"Data size mismatch: got {len(data)}, expected {total_cells}")
        
        # Reshape to [Q, NY, NX]
        data_3d = data.reshape(Q, NY, NX)
        
        return data_3d, NX, NY, Q

def scale_brain_state(data_3d, orig_NX, orig_NY, target_NX, target_NY):
    """Scale brain state to target grid size using simple averaging"""
    Q = data_3d.shape[0]
    
    # Calculate scaling factors
    scale_x = target_NX / orig_NX
    scale_y = target_NY / orig_NY
    
    print(f"Scaling: {orig_NX}x{orig_NY} -> {target_NX}x{target_NY} (scale: {scale_x:.3f}x{scale_y:.3f})")
    
    # Create target array
    target_data = np.zeros((Q, target_NY, target_NX), dtype=np.float32)
    
    # Simple nearest-neighbor scaling for now
    # In evolutionary squeeze, the system will adapt from this starting point
    for q in range(Q):
        for y in range(target_NY):
            src_y = min(int(y / scale_y), orig_NY - 1)
            for x in range(target_NX):
                src_x = min(int(x / scale_x), orig_NX - 1)
                target_data[q, y, x] = data_3d[q, src_y, src_x]
    
    return target_data

def write_brain_state(output_path, data_3d, NX, NY, Q):
    """Write scaled brain state file"""
    with open(output_path, 'wb') as f:
        # Write header
        header = struct.pack('IIII', 0x4D424C46, NX, NY, Q)
        f.write(header)
        
        # Write data
        data_3d.reshape(-1).tofile(f)
    
    file_size = os.path.getsize(output_path)
    print(f"Written: {output_path} ({file_size:,} bytes)")

def main():
    # Grid sizes for evolutionary squeeze
    grid_sizes = [
        (768, 768),
        (512, 512),
        (384, 384),
        (256, 256),
        (192, 192)
    ]
    
    input_file = r"D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain-build\f_state_post_relax.bin"
    output_dir = r"D:\openclaw-local\workspace-main\scaled_brain_states"
    
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    try:
        # Read original brain state
        print(f"Reading original brain state: {input_file}")
        data_3d, orig_NX, orig_NY, Q = read_brain_state(input_file)
        
        # Create scaled versions
        for target_NX, target_NY in grid_sizes:
            print(f"\n--- Creating {target_NX}x{target_NY} ---")
            
            # Scale brain state
            scaled_data = scale_brain_state(data_3d, orig_NX, orig_NY, target_NX, target_NY)
            
            # Write output
            output_file = os.path.join(output_dir, f"f_state_{target_NX}x{target_NY}.bin")
            write_brain_state(output_file, scaled_data, target_NX, target_NY, Q)
            
            # Also create build directory structure
            build_dir = os.path.join(output_dir, f"build_{target_NX}x{target_NY}")
            if not os.path.exists(build_dir):
                os.makedirs(build_dir)
            
            build_file = os.path.join(build_dir, f"f_state_post_relax.bin")
            write_brain_state(build_file, scaled_data, target_NX, target_NY, Q)
            
            print(f"  Build dir: {build_dir}")
    
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    print(f"\n✅ All scaled brain states created in: {output_dir}")
    return 0

if __name__ == "__main__":
    sys.exit(main())