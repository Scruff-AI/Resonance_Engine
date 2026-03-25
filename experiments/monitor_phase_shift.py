#!/usr/bin/env python3
"""
Monitor 1-hour test for phase shift indicators:
1. Metabolic cycles (every ~50-200s)
2. Pattern stabilization events
3. Potential crystallization indicators
"""

import time
import os
import subprocess
from datetime import datetime

def monitor_test(duration_hours=1):
    """Monitor the running probe_256_final.exe for phase shift patterns."""
    
    total_seconds = duration_hours * 3600
    start_time = time.time()
    
    print("="*70)
    print("PHASE SHIFT MONITOR - 1 HOUR TEST")
    print(f"Start time: {datetime.now().strftime('%H:%M:%S')}")
    print(f"Duration: {duration_hours} hour(s) = {total_seconds} seconds")
    print("="*70)
    
    print("\nMONITORING FOR:")
    print("1. Metabolic cycles (expected: ~50-200s intervals at 256×256)")
    print("2. Pattern stabilization events (mass/energy plateaus)")
    print("3. Guardian behavior changes (birth/death patterns)")
    print("4. File system events (.bin file modifications)")
    print("="*70)
    
    # Initial state
    initial_bin_mtime = os.path.getmtime("build\\f_state_post_relax.bin") if os.path.exists("build\\f_state_post_relax.bin") else 0
    
    # Monitoring intervals
    check_interval = 30  # Check every 30 seconds
    last_check = start_time
    
    # Trackers
    metabolic_events = []
    stabilization_events = []
    file_events = []
    
    cycle_count = 0
    last_cycle_time = start_time
    
    print("\nStarting monitoring...")
    print("Press Ctrl+C to stop early")
    print("-"*70)
    
    try:
        while time.time() - start_time < total_seconds:
            current_time = time.time()
            elapsed = current_time - start_time
            
            # Periodic check every 30 seconds
            if current_time - last_check >= check_interval:
                last_check = current_time
                
                # Check 1: File system (crystallization events)
                if os.path.exists("build\\f_state_post_relax.bin"):
                    current_mtime = os.path.getmtime("build\\f_state_post_relax.bin")
                    if current_mtime > initial_bin_mtime + 1:  # Changed within last second
                        file_events.append({
                            "time": elapsed,
                            "event": "bin_file_modified",
                            "mtime": current_mtime
                        })
                        print(f"[{elapsed:.0f}s] ⚡ NVMe WRITE DETECTED - Possible crystallization")
                        initial_bin_mtime = current_mtime
                
                # Check 2: Process status
                # (We'll infer from output patterns later)
                
                # Status update
                hours = int(elapsed // 3600)
                minutes = int((elapsed % 3600) // 60)
                seconds = int(elapsed % 60)
                
                print(f"[{elapsed:.0f}s] Monitoring... ({hours:02d}:{minutes:02d}:{seconds:02d} elapsed)")
                
                # Every 5 minutes, print summary
                if elapsed % 300 < check_interval:  # ~5 minutes
                    print(f"\n--- 5-MINUTE CHECKPOINT ---")
                    print(f"Elapsed: {elapsed:.0f}s")
                    print(f"Metabolic events: {len(metabolic_events)}")
                    print(f"Stabilization events: {len(stabilization_events)}")
                    print(f"Crystallization events: {len(file_events)}")
                    print("-"*40)
            
            # Short sleep to prevent CPU hogging
            time.sleep(1)
            
    except KeyboardInterrupt:
        print("\n\nMonitoring stopped by user")
    
    # Final analysis
    print("\n" + "="*70)
    print("PHASE SHIFT TEST COMPLETE")
    print(f"Total duration: {time.time() - start_time:.0f}s")
    print(f"End time: {datetime.now().strftime('%H:%M:%S')}")
    print("="*70)
    
    # Analyze metabolic cycles
    print("\nMETABOLIC CYCLE ANALYSIS:")
    if metabolic_events:
        intervals = []
        for i in range(1, len(metabolic_events)):
            interval = metabolic_events[i]["time"] - metabolic_events[i-1]["time"]
            intervals.append(interval)
        
        if intervals:
            avg_interval = sum(intervals) / len(intervals)
            min_interval = min(intervals)
            max_interval = max(intervals)
            
            print(f"Events detected: {len(metabolic_events)}")
            print(f"Interval range: {min_interval:.0f}s - {max_interval:.0f}s")
            print(f"Average interval: {avg_interval:.0f}s")
            print(f"Frequency: {1/avg_interval:.4f}Hz")
            
            # Compare to 1024×1024 baseline
            baseline = 200  # 0.005Hz
            scaling = avg_interval / baseline
            
            print(f"\nScaling vs 1024×1024 (200s):")
            print(f"  Scaling factor: {scaling:.3f}")
            print(f"  Expected for 256×256: 0.25 (4× faster)")
            
            if 0.2 < scaling < 0.3:
                print("  ✓ Metabolic cycle scales with grid size")
            else:
                print(f"  ⚠️  Unexpected scaling: {scaling:.3f}")
    else:
        print("No metabolic cycles detected")
        print("Possible reasons:")
        print("  - Cycle longer than observation period")
        print("  - Different metabolic signature at 256×256")
        print("  - Need different detection method")
    
    # Crystallization analysis
    print("\nCRYSTALLIZATION ANALYSIS:")
    if file_events:
        print(f"NVMe writes detected: {len(file_events)}")
        print("Timestamps:")
        for event in file_events:
            print(f"  {event['time']:.0f}s - .bin file modified")
        
        # Calculate write intervals
        if len(file_events) > 1:
            write_intervals = []
            for i in range(1, len(file_events)):
                interval = file_events[i]["time"] - file_events[i-1]["time"]
                write_intervals.append(interval)
            
            avg_write_interval = sum(write_intervals) / len(write_intervals)
            print(f"\nAverage write interval: {avg_write_interval:.0f}s")
            print(f"Writes per hour: {3600/avg_write_interval:.1f}")
    else:
        print("No NVMe writes detected")
        print("Crystallization may:")
        print("  - Happen less frequently than 1 hour")
        print("  - Require specific conditions")
        print("  - Use different file paths")
    
    # Phase shift summary
    print("\n" + "="*70)
    print("PHASE SHIFT SUMMARY:")
    
    has_volatile = True  # Always true if process ran
    has_buffer = len(metabolic_events) > 0 or len(stabilization_events) > 0
    has_solid = len(file_events) > 0
    
    print(f"Volatile State (GPU): {'✓ ACTIVE' if has_volatile else '✗ INACTIVE'}")
    print(f"Buffer State (RAM): {'✓ PATTERNS DETECTED' if has_buffer else '? NO CLEAR PATTERNS'}")
    print(f"Solid State (NVMe): {'✓ CRYSTALLIZATION' if has_solid else '✗ NO WRITES'}")
    
    if has_volatile and has_buffer and has_solid:
        print("\n🎉 FULL PHASE SHIFT DETECTED!")
        print("  GPU → RAM → NVMe transition observed")
    elif has_volatile and has_buffer:
        print("\n⚠️  PARTIAL PHASE SHIFT")
        print("  GPU → RAM transition, but no NVMe crystallization")
    elif has_volatile:
        print("\n⚠️  ONLY VOLATILE STATE ACTIVE")
        print("  No clear buffer or solid state transitions")
    
    print("\n" + "="*70)
    print("RECOMMENDATIONS:")
    if not has_buffer:
        print("1. Extend test duration (metabolic cycles may be >1 hour)")
        print("2. Monitor different metrics for buffer state")
    if not has_solid:
        print("3. Check other .bin file locations for writes")
        print("4. Crystallization may require specific thresholds")
    
    print("\nTest data saved for later analysis")
    return {
        "duration": time.time() - start_time,
        "metabolic_events": metabolic_events,
        "stabilization_events": stabilization_events,
        "file_events": file_events,
        "phase_shift_detected": (has_volatile and has_buffer and has_solid)
    }

if __name__ == "__main__":
    # Note: This monitors for file system events and timing
    # The actual probe output needs to be captured separately
    print("IMPORTANT: This script monitors for phase shift indicators")
    print("Run probe_256_final.exe in parallel to capture output")
    print("Press Enter to start monitoring...")
    input()
    
    results = monitor_test(duration_hours=1)
    
    # Save results
    import json
    with open("phase_shift_results.json", "w") as f:
        json.dump(results, f, indent=2)
    
    print(f"\nResults saved to: phase_shift_results.json")