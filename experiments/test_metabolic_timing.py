#!/usr/bin/env python3
"""
Test metabolic cycle timing at 256×256 scale.
Hypothesis: Metabolic cycle (0.005Hz at 1024×1024) scales with grid size.
256×256 = 1/4 linear scale → 4× faster metabolic cycle? (0.02Hz = 50s)
"""

import subprocess
import time
import psutil
import os

def monitor_simulation(duration_seconds=200):
    """Run probe_256 and monitor for metabolic patterns."""
    
    print("=== Metabolic Cycle Timing Test ===")
    print(f"Duration: {duration_seconds}s (4× expected 256×256 metabolic cycles)")
    print("="*50)
    
    # Start process
    print("Starting probe_256_final.exe...")
    proc = subprocess.Popen(
        [".\\probe_256_final.exe"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        universal_newlines=True
    )
    
    print(f"Monitoring for {duration_seconds} seconds...")
    print("Looking for metabolic patterns (every ~50s for 256×256)")
    
    # Monitoring variables
    start_time = time.time()
    cycle_count = 0
    last_cycle_time = start_time
    output_lines = []
    
    # Pattern detection
    metabolic_patterns = []
    
    try:
        while time.time() - start_time < duration_seconds:
            # Read output
            line = proc.stdout.readline()
            if line:
                output_lines.append(line.strip())
                
                # Look for metabolic indicators
                # 1. Guardian mass accumulation patterns
                if "p.mass" in line:
                    parts = line.split("|")
                    if len(parts) > 7:
                        mass = float(parts[7].strip())
                        current_time = time.time()
                        time_since_last = current_time - last_cycle_time
                        
                        # Check for ~50s cycles (0.02Hz)
                        if time_since_last > 40 and time_since_last < 60:
                            cycle_count += 1
                            metabolic_patterns.append({
                                "cycle": cycle_count,
                                "time": current_time - start_time,
                                "mass": mass,
                                "interval": time_since_last
                            })
                            last_cycle_time = current_time
                            print(f"  Metabolic cycle {cycle_count} at {current_time - start_time:.1f}s (interval: {time_since_last:.1f}s)")
                
                # 2. Power fluctuations (metabolic "breathing")
                if "W" in line and ("Power" in line or "W —" in line):
                    # Extract power value
                    import re
                    power_match = re.search(r'(\d+\.\d+)W', line)
                    if power_match:
                        power = float(power_match.group(1))
                        # Power fluctuations could indicate metabolic cycles
                        
                # 3. Density range changes
                if "rho range" in line:
                    # Density variations might show metabolic "pulses"
                    pass
            
            # Check process still running
            if proc.poll() is not None:
                print("Process ended early")
                break
            
            # Small sleep to prevent CPU hogging
            time.sleep(0.1)
    
    except KeyboardInterrupt:
        print("\nTest interrupted")
    finally:
        # Terminate process
        proc.terminate()
        proc.wait(timeout=2)
    
    # Analysis
    print("\n" + "="*50)
    print("METABOLIC CYCLE ANALYSIS:")
    print(f"Total time: {duration_seconds}s")
    print(f"Cycles detected: {cycle_count}")
    
    if metabolic_patterns:
        intervals = [p["interval"] for p in metabolic_patterns]
        avg_interval = sum(intervals) / len(intervals) if intervals else 0
        
        print(f"\nCycle intervals:")
        for i, pattern in enumerate(metabolic_patterns):
            print(f"  Cycle {i+1}: {pattern['interval']:.1f}s (mass: {pattern['mass']:.2f})")
        
        print(f"\nAverage interval: {avg_interval:.1f}s")
        print(f"Frequency: {1/avg_interval:.4f}Hz" if avg_interval > 0 else "N/A")
        
        # Compare to 1024×1024 baseline
        baseline_interval = 200  # 0.005Hz = 200s
        scale_factor = avg_interval / baseline_interval if baseline_interval > 0 else 0
        
        print(f"\nScaling analysis:")
        print(f"  1024×1024 baseline: 200s (0.005Hz)")
        print(f"  256×256 measured: {avg_interval:.1f}s ({1/avg_interval:.4f}Hz)")
        print(f"  Scale factor: {scale_factor:.2f}×")
        
        if 0.2 < scale_factor < 0.3:  # Expected ~0.25 (4× faster)
            print(f"  ✓ Metabolic cycle scales with grid size (4× faster at 256×256)")
        else:
            print(f"  ⚠️  Unexpected scaling: {scale_factor:.2f}× (expected ~0.25×)")
    
    else:
        print("No metabolic cycles detected")
        print("Possible reasons:")
        print("  1. Cycle longer than test duration")
        print("  2. Different metabolic signature at 256×256")
        print("  3. Need different detection method")
    
    # Save raw output for later analysis
    output_file = "metabolic_test_output.txt"
    with open(output_file, "w") as f:
        f.write("\n".join(output_lines[-1000:]))  # Last 1000 lines
    
    print(f"\nRaw output saved to: {output_file}")
    return metabolic_patterns

def check_memory_hierarchy():
    """Check the three-state memory usage."""
    print("\n" + "="*50)
    print("MEMORY HIERARCHY CHECK:")
    
    # 1. GPU VRAM (estimated)
    grid_size = 256 * 256 * 9 * 4  # 9 distribution functions × 4 bytes
    buffers = grid_size * 4  # Ping-pong buffers
    total_vram_est = (grid_size + buffers) / 1024 / 1024  # MB
    
    print(f"1. Volatile State (GPU VRAM):")
    print(f"   Grid: 256×256×9×4 = {grid_size:,} bytes")
    print(f"   Buffers: ~{buffers:,} bytes")
    print(f"   Estimated: {total_vram_est:.1f} MB")
    print(f"   GTX 1050 capacity: 4,096 MB")
    print(f"   Usage: {total_vram_est/4096*100:.1f}%")
    
    # 2. System RAM (actual)
    ram = psutil.virtual_memory()
    print(f"\n2. Buffer State (System RAM):")
    print(f"   Total: {ram.total/1024/1024/1024:.1f} GB")
    print(f"   Available: {ram.available/1024/1024/1024:.1f} GB")
    print(f"   Used: {ram.used/1024/1024/1024:.1f} GB")
    print(f"   Percent: {ram.percent}%")
    
    # 3. NVMe SSD (actual)
    try:
        disk = psutil.disk_usage("D:\\")
        print(f"\n3. Solid State (NVMe SSD):")
        print(f"   Total: {disk.total/1024/1024/1024:.1f} GB")
        print(f"   Used: {disk.used/1024/1024/1024:.1f} GB")
        print(f"   Free: {disk.free/1024/1024/1024:.1f} GB")
        print(f"   Percent: {disk.percent}%")
    except:
        print(f"\n3. Solid State (NVMe SSD): Not accessible")
    
    print(f"\nMemory hierarchy check:")
    print(f"  ✓ Volatile (GPU): {total_vram_est:.1f} MB / 4,096 MB ({total_vram_est/4096*100:.1f}%)")
    print(f"  ✓ Buffer (RAM): {ram.available/1024/1024/1024:.1f} GB free")
    print(f"  ✓ Solid (NVMe): {disk.free/1024/1024/1024:.1f} GB free" if 'disk' in locals() else "  ? Solid (NVMe): Unknown")

def main():
    """Run metabolic timing test."""
    print("=== THREE-STATE MEMORY SYSTEM TEST ===")
    print("Testing Phase Shift: Volatile → Buffer → Solid")
    print("="*50)
    
    # Check memory hierarchy
    check_memory_hierarchy()
    
    # Run metabolic timing test
    patterns = monitor_simulation(duration_seconds=200)
    
    print("\n" + "="*50)
    print("TEST COMPLETE")
    print("\nNext steps:")
    if patterns:
        print("1. Verify metabolic cycle scaling (expected 4× faster at 256×256)")
        print("2. Monitor buffer state (RAM) for pattern stabilization")
        print("3. Check NVMe for crystallization events (.bin file updates)")
    else:
        print("1. Extend test duration (try 400s)")
        print("2. Look for different metabolic signatures")
        print("3. Check if metabolic cycle exists at 256×256 scale")

if __name__ == "__main__":
    main()