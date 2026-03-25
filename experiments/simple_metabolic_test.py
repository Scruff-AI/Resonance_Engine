#!/usr/bin/env python3
"""
Simple metabolic cycle test - look for ~50s cycles at 256×256
"""

import subprocess
import time
import re

def run_metabolic_test():
    print("=== Simple Metabolic Cycle Test ===")
    print("Running probe_256 for 200s, looking for ~50s cycles")
    print("="*50)
    
    # Start process
    proc = subprocess.Popen(
        [".\\probe_256_final.exe"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        universal_newlines=True
    )
    
    start_time = time.time()
    last_mass = 0
    last_mass_time = start_time
    cycles = []
    
    print("Monitoring mass accumulation for metabolic cycles...")
    print("(Mass should pulse every ~50s if metabolic cycle scales 4×)")
    
    try:
        while time.time() - start_time < 200:  # 200 seconds
            line = proc.stdout.readline()
            if line:
                # Look for mass values
                if "p.mass" in line:
                    # Parse line like: " 13 |     0.34 |    65551.68 | ---"
                    parts = line.split("|")
                    if len(parts) > 7:
                        try:
                            mass = float(parts[7].strip())
                            current_time = time.time()
                            
                            # Check if mass increased significantly
                            if mass > last_mass + 0.05:  # 0.05 mass increase
                                interval = current_time - last_mass_time
                                cycles.append({
                                    "time": current_time - start_time,
                                    "mass": mass,
                                    "interval": interval
                                })
                                print(f"  Mass pulse at {current_time - start_time:.1f}s: {mass:.2f} (interval: {interval:.1f}s)")
                                last_mass = mass
                                last_mass_time = current_time
                        except:
                            pass
            
            # Check process
            if proc.poll() is not None:
                break
                
            time.sleep(0.05)
            
    except KeyboardInterrupt:
        print("\nInterrupted")
    finally:
        proc.terminate()
        proc.wait(timeout=2)
    
    # Analyze
    print("\n" + "="*50)
    print("RESULTS:")
    
    if len(cycles) >= 2:
        intervals = [c["interval"] for c in cycles[1:]]  # Skip first
        avg_interval = sum(intervals) / len(intervals)
        
        print(f"Cycles detected: {len(cycles)}")
        print(f"Intervals: {', '.join(f'{i:.1f}s' for i in intervals)}")
        print(f"Average interval: {avg_interval:.1f}s")
        print(f"Frequency: {1/avg_interval:.4f}Hz")
        
        # Compare to baseline
        baseline = 200  # 1024×1024 metabolic cycle
        scaling = avg_interval / baseline
        
        print(f"\nScaling analysis:")
        print(f"  1024×1024: 200s cycle (0.005Hz)")
        print(f"  256×256: {avg_interval:.1f}s cycle ({1/avg_interval:.4f}Hz)")
        print(f"  Scaling factor: {scaling:.3f} (expected: 0.25 for 4× faster)")
        
        if 0.2 < scaling < 0.3:
            print("  ✓ Metabolic cycle scales with grid size (4× faster)")
        elif scaling < 0.2:
            print("  ⚠️  Faster than expected (>4× faster)")
        else:
            print("  ⚠️  Slower than expected (<4× faster)")
            
        # Check for regularity
        interval_std = (sum((i - avg_interval)**2 for i in intervals) / len(intervals))**0.5
        print(f"  Regularity: std dev = {interval_std:.1f}s ({interval_std/avg_interval*100:.1f}%)")
        
    else:
        print("Not enough cycles detected for analysis")
        print("Possible reasons:")
        print("  1. Metabolic cycle longer than 200s at 256×256")
        print("  2. Mass accumulation too smooth (no pulses)")
        print("  3. Different metabolic signature")
    
    print("\n" + "="*50)
    print("PHASE SHIFT INTERPRETATION:")
    if len(cycles) >= 2:
        print(f"Metabolic cycle at 256×256: ~{avg_interval:.0f}s")
        print(f"This is the Buffer State timing (RAM stabilization)")
        print(f"Each cycle represents pattern precipitation from GPU→RAM")
    else:
        print("Metabolic cycle not detected in 200s window")
        print("May need longer observation or different detection method")
    
    return cycles

def check_three_state_capacity():
    """Simple check of three-state memory capacity."""
    print("\n" + "="*50)
    print("THREE-STATE MEMORY CAPACITY:")
    
    # 1. Volatile (GPU VRAM)
    grid_cells = 256 * 256
    bytes_per_cell = 9 * 4 * 2  # 9 distributions × 4 bytes × 2 buffers
    vram_needed = grid_cells * bytes_per_cell / 1024 / 1024
    
    print(f"1. Volatile (GPU VRAM):")
    print(f"   Grid: 256×256 = {grid_cells:,} cells")
    print(f"   Memory: {vram_needed:.1f} MB")
    print(f"   GTX 1050: 4,096 MB available")
    print(f"   Usage: {vram_needed/4096*100:.1f}%")
    
    # 2. Buffer (System RAM) - estimated
    print(f"\n2. Buffer (System RAM):")
    print(f"   Estimated need: 100-500 MB for metabolic damping")
    print(f"   the-craw has: 32,768 MB total")
    print(f"   Usage: <2%")
    
    # 3. Solid (NVMe SSD)
    print(f"\n3. Solid (NVMe SSD):")
    print(f"   .bin file size: ~2.2 MB")
    print(f"   the-craw has: 937 GB free")
    print(f"   Capacity: ~400,000 crystallized states")
    
    print(f"\nConclusion: All three states comfortably fit on the-craw")
    print(f"  GPU VRAM: {vram_needed:.1f} MB / 4,096 MB")
    print(f"  System RAM: <500 MB / 32,768 MB")  
    print(f"  NVMe SSD: ~2.2 MB / 937,000 MB")

if __name__ == "__main__":
    cycles = run_metabolic_test()
    check_three_state_capacity()
    
    print("\n" + "="*50)
    print("NEXT STEPS FOR PHASE SHIFT TESTING:")
    print("1. If metabolic cycle ~50s: Test matches phase shift model")
    print("2. Deploy to the-craw to test actual memory hierarchy")
    print("3. Monitor NVMe writes for crystallization events")
    print("4. Observe full phase shift: GPU→RAM→NVMe")