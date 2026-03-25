#!/usr/bin/env python3
"""
Monitor probe_256_final.exe for crash at cycle ~1112.
Capture logs, analyze patterns, identify crash cause.
"""

import subprocess
import time
import re
import os
from datetime import datetime

def monitor_for_crash():
    """Run probe_256 and capture crash details."""
    
    print("="*70)
    print("CRASH ANALYTICS - Monitoring for cycle 1112 crash")
    print(f"Start time: {datetime.now().strftime('%H:%M:%S')}")
    print("="*70)
    
    # Start process
    proc = subprocess.Popen(
        [".\\probe_256_final.exe"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        universal_newlines=True
    )
    
    print("Monitoring process...")
    print("Looking for crash at cycle ~1112 (Probe C: SILENT)")
    print("-"*70)
    
    # Capture variables
    crash_data = {
        "last_cycle": 0,
        "last_output": "",
        "crash_cycle": None,
        "crash_time": None,
        "error_message": "",
        "probe_state": "---",
        "pre_crash_patterns": []
    }
    
    cycle_pattern = re.compile(r'^\s*(\d+)\s*\|\s*(\d+:\d+:\d+)\s*\|')
    probe_pattern = re.compile(r'\|\s*(INJ|SHEAR|SILENT|TRAP)\s*$')
    
    try:
        while True:
            line = proc.stdout.readline()
            if line:
                # Check for cycle number
                cycle_match = cycle_pattern.search(line)
                if cycle_match:
                    cycle = int(cycle_match.group(1))
                    crash_data["last_cycle"] = cycle
                    
                    # Check probe state
                    probe_match = probe_pattern.search(line)
                    if probe_match:
                        probe_state = probe_match.group(1)
                        crash_data["probe_state"] = probe_state
                        
                        if probe_state == "SILENT" and cycle >= 1100:
                            print(f"⚠️  ENTERED SILENT PROBE ZONE: Cycle {cycle}")
                            crash_data["pre_crash_patterns"].append({
                                "cycle": cycle,
                                "state": "SILENT",
                                "line": line.strip()
                            })
                
                # Check for error indicators
                error_indicators = [
                    "error", "Error", "ERROR",
                    "exception", "Exception", "EXCEPTION",
                    "fatal", "Fatal", "FATAL",
                    "segmentation", "Segmentation",
                    "access violation", "Access violation",
                    "cudaError", "CUDA error",
                    "nvmlError", "NVML error"
                ]
                
                for indicator in error_indicators:
                    if indicator in line:
                        print(f"🔴 ERROR INDICATOR: {indicator} in line")
                        crash_data["error_message"] += line
                
                # Save last 10 lines before potential crash
                if len(crash_data["pre_crash_patterns"]) > 10:
                    crash_data["pre_crash_patterns"].pop(0)
                crash_data["pre_crash_patterns"].append({
                    "cycle": crash_data["last_cycle"],
                    "line": line.strip()[:100]
                })
                
                # Monitor for crash zone (cycles 1100-1200)
                if 1100 <= cycle <= 1200:
                    print(f"🚨 CRASH ZONE: Cycle {cycle}, Probe: {crash_data['probe_state']}")
                    
                    # Check for specific patterns that might cause crash
                    if "omega locked" in line or "VRM" in line:
                        print(f"  VRM/SILENT pattern detected: {line.strip()[:50]}...")
                
                # Check if process died
                if proc.poll() is not None:
                    crash_data["crash_cycle"] = crash_data["last_cycle"]
                    crash_data["crash_time"] = datetime.now().strftime('%H:%M:%S')
                    crash_data["exit_code"] = proc.returncode
                    
                    print(f"\n💥 PROCESS EXITED: Cycle {crash_data['crash_cycle']}")
                    print(f"   Exit code: {proc.returncode}")
                    print(f"   Time: {crash_data['crash_time']}")
                    print(f"   Probe state: {crash_data['probe_state']}")
                    
                    # Read stderr for error messages
                    stderr_output = proc.stderr.read()
                    if stderr_output:
                        crash_data["error_message"] += "\nSTDERR:\n" + stderr_output
                    
                    break
            
            # Small sleep to prevent CPU hogging
            time.sleep(0.01)
            
    except KeyboardInterrupt:
        print("\n\nMonitoring stopped by user")
        proc.terminate()
    
    # Analysis
    print("\n" + "="*70)
    print("CRASH ANALYSIS REPORT")
    print("="*70)
    
    if crash_data["crash_cycle"]:
        print(f"Crash confirmed at cycle: {crash_data['crash_cycle']}")
        print(f"Exit code: {crash_data.get('exit_code', 'N/A')}")
        print(f"Probe state: {crash_data['probe_state']}")
        
        # Analyze crash pattern
        if 1100 <= crash_data["crash_cycle"] <= 1199:
            print("\n🔍 CRASH IN SILENT PROBE (cycles 1100-1199)")
            print("   Probe C: VRM Silence (omega locked to 1.25)")
            print("   Possible causes:")
            print("   1. GPU memory error during omega lock")
            print("   2. CUDA kernel failure with locked parameters")
            print("   3. Numerical instability at fixed omega=1.25")
            print("   4. Buffer overflow in VRM silence logic")
        
        elif crash_data["crash_cycle"] == 800:
            print("\n🔍 CRASH IN SHEAR PROBE (cycle 800)")
            print("   Probe B: Lattice Shear (top 25% rotated 90°)")
        
        elif 600 <= crash_data["crash_cycle"] <= 649:
            print("\n🔍 CRASH IN INJECTION PROBE (cycles 600-649)")
            print("   Probe A: Metabolic Injection (+mass)")
        
        else:
            print(f"\n🔍 CRASH AT UNEXPECTED CYCLE: {crash_data['crash_cycle']}")
        
        # Show error messages
        if crash_data["error_message"]:
            print(f"\n📄 ERROR MESSAGES:")
            print(crash_data["error_message"][:500] + "..." if len(crash_data["error_message"]) > 500 else crash_data["error_message"])
        
        # Show last few lines before crash
        print(f"\n📝 LAST 5 LINES BEFORE CRASH:")
        for i, pattern in enumerate(crash_data["pre_crash_patterns"][-5:]):
            print(f"  Cycle {pattern['cycle']}: {pattern['line']}")
    
    else:
        print("No crash detected (process may still be running)")
    
    # Recommendations
    print("\n" + "="*70)
    print("RECOMMENDATIONS")
    print("="*70)
    
    if crash_data.get("exit_code") == 1 and 1100 <= crash_data.get("crash_cycle", 0) <= 1199:
        print("1. ⚠️ SILENT PROBE BUG CONFIRMED")
        print("   - Crash occurs in VRM Silence (omega locked 1.25)")
        print("   - Need to examine SILENT probe implementation")
        print("   - Possible fix: Remove or modify omega locking")
        
        print("\n2. IMMEDIATE ACTIONS:")
        print("   a) Check probe_256.cu lines for SILENT probe logic")
        print("   b) Look for 'omega = 1.25' or similar hardcoded values")
        print("   c) Check CUDA error handling in VRM silence")
        print("   d) Consider removing SILENT probe for stability")
        
        print("\n3. WORKAROUNDS:")
        print("   a) Run without probes (continuous operation)")
        print("   b) Modify MAX_CYCLES to stop before 1100")
        print("   c) Fix SILENT probe implementation")
    
    elif crash_data.get("exit_code") == 0:
        print("✅ Process exited cleanly (no crash)")
        print("   - May have completed all 1700 cycles")
        print("   - Or was terminated externally")
    
    else:
        print("❓ Unknown crash pattern")
        print("   - Need more data")
        print("   - Run again with full debug output")
    
    # Save crash data
    import json
    with open("crash_analysis.json", "w") as f:
        json.dump(crash_data, f, indent=2)
    
    print(f"\n📁 Crash data saved to: crash_analysis.json")
    
    return crash_data

if __name__ == "__main__":
    print("Starting crash analytics...")
    print("This will run probe_256_final.exe and monitor for crash at cycle ~1112")
    print("Press Ctrl+C to stop early")
    print("-"*70)
    
    data = monitor_for_crash()
    
    print("\n" + "="*70)
    print("ANALYTICS COMPLETE")
    print("="*70)