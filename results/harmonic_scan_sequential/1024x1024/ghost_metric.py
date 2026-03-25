#!/usr/bin/env python3
"""
Ghost Metric Driver - Somatic Memory Validation
Coordinates C++ ghost metric executable and calculates correlation.
"""

import numpy as np
import subprocess
import sys
import os
import time
from pathlib import Path
from scipy.stats import pearsonr

# Configuration
WORKING_DIR = r"D:\openclaw-local\workspace-main\harmonic_scan_sequential\1024x1024"
EXECUTABLE = "fractal_habit_ghost.exe"
CRYSTAL_DIR = r"C:\fractal_nvme_test\ghost_metric"
BINARY_DIR = r"C:\fractal_nvme_test\ghost_metric\fingerprints"

# Ensure directories exist
os.makedirs(CRYSTAL_DIR, exist_ok=True)
os.makedirs(BINARY_DIR, exist_ok=True)

def capture_somatic_fingerprint(binary_file):
    """
    Reads the binary velocity field dump.
    Returns: 1D numpy array of interleaved UV values.
    """
    try:
        # Read raw binary (float32, interleaved UV)
        data = np.fromfile(binary_file, dtype=np.float32)
        
        # Expected size: 1024*1024*2 = 2,097,152 elements
        expected_size = 1024 * 1024 * 2
        if len(data) != expected_size:
            print(f"[WARNING] Binary file size mismatch: {len(data)} vs {expected_size}")
            
        return data
    except Exception as e:
        print(f"[ERROR] Failed to read binary file {binary_file}: {e}")
        return None

def calculate_ghost_metric(state_A, state_C):
    """
    The 'Kimi Test': Compares Pristine (A) vs Recovered (C).
    Correlation < 0.95 = Structural Memory Confirmed.
    """
    if state_A is None or state_C is None:
        return {
            "correlation": 0.0,
            "hysteresis_depth": 1.0,
            "status": "ERROR - Invalid states",
            "memory_confirmed": False
        }
    
    # Ensure same length
    min_len = min(len(state_A), len(state_C))
    state_A = state_A[:min_len]
    state_C = state_C[:min_len]
    
    # Calculate Pearson correlation
    correlation, p_value = pearsonr(state_A, state_C)
    
    # Structural Hysteresis (The Scar)
    hysteresis_depth = 1.0 - correlation
    
    # Determine status
    if correlation < 0.95:
        status = "GHOST DETECTED"
        memory_confirmed = True
    elif correlation > 0.99:
        status = "MACHINE RESET"
        memory_confirmed = False
    else:
        status = "BORDERLINE"
        memory_confirmed = False
    
    return {
        "correlation": round(correlation, 4),
        "hysteresis_depth": round(hysteresis_depth, 4),
        "status": status,
        "memory_confirmed": memory_confirmed,
        "p_value": p_value
    }

def run_cpp_command(args, label="C++ Process"):
    """
    Runs the C++ executable and captures output.
    """
    cmd = [os.path.join(WORKING_DIR, EXECUTABLE)] + args
    
    print(f"\n{'='*60}")
    print(f"{label}")
    print(f"{'='*60}")
    print(f"Command: {' '.join(cmd)}")
    print(f"Working dir: {WORKING_DIR}")
    print()
    
    try:
        process = subprocess.Popen(
            cmd,
            cwd=WORKING_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            universal_newlines=True
        )
        
        # Stream output in real-time
        while True:
            output = process.stdout.readline()
            if output == '' and process.poll() is not None:
                break
            if output:
                print(output.strip())
                # Check for somatic state updates
                if "[SOMATIC_STATE]" in output:
                    # Could send to OpenClaw here
                    pass
        
        # Get remaining output
        remaining, _ = process.communicate()
        if remaining:
            print(remaining.strip())
        
        return process.returncode
        
    except Exception as e:
        print(f"[ERROR] Failed to run command: {e}")
        return 1

def update_veto_threshold(memory_confirmed):
    """
    Updates VETO_THRESHOLD if memory is confirmed.
    """
    if memory_confirmed:
        veto_file = os.path.join(CRYSTAL_DIR, "veto_config.txt")
        try:
            with open(veto_file, 'w') as f:
                f.write("VETO_THRESHOLD=4.5\n")
            print(f"\n[VIGILANCE] VETO_THRESHOLD updated to 4.5 in {veto_file}")
            return True
        except Exception as e:
            print(f"[ERROR] Failed to update VETO_THRESHOLD: {e}")
            return False
    return False

def run_baseline_phase():
    """
    Phase 1: Establish baseline at 6.8 bits and capture microstate_A.
    """
    print("\n" + "="*60)
    print("PHASE 1: BASELINE FINGERPRINT")
    print("="*60)
    
    timestamp = int(time.time())
    microstate_A = os.path.join(BINARY_DIR, f"microstate_A_{timestamp}.bin")
    
    args = [
        "-mode", "baseline",
        "-target-entropy", "6.8",
        "-tolerance", "0.05",
        "-output", microstate_A
    ]
    
    retcode = run_cpp_command(args, "Baseline Phase")
    
    if retcode == 0:
        print(f"\n[SUCCESS] Baseline fingerprint saved: {microstate_A}")
        return microstate_A
    elif retcode == 2:
        print("\n[WARNING] Baseline timeout - using best available state")
        # Still return the file if it was created
        if os.path.exists(microstate_A):
            return microstate_A
        else:
            return None
    else:
        print("\n[ERROR] Baseline phase failed")
        return None

def run_injury_phase(input_crystal):
    """
    Phase 2: Inject sustained noise to create injury.
    """
    print("\n" + "="*60)
    print("PHASE 2: INJURY")
    print("="*60)
    
    timestamp = int(time.time())
    injury_crystal = os.path.join(CRYSTAL_DIR, f"injury_{timestamp}.crys")
    
    args = [
        "-mode", "injury",
        "-crystal", input_crystal,
        "-injury-steps", "1500000",
        "-noise-amplitude", "0.35"
    ]
    
    retcode = run_cpp_command(args, "Injury Phase")
    
    if retcode == 0:
        print(f"\n[SUCCESS] Injury crystal saved: {injury_crystal}")
        return injury_crystal
    else:
        print("\n[ERROR] Injury phase failed")
        return None

def run_recovery_phase(injury_crystal):
    """
    Phase 3: Recover from injury to 6.8 bits and capture microstate_C.
    """
    print("\n" + "="*60)
    print("PHASE 3: RECOVERY")
    print("="*60)
    
    timestamp = int(time.time())
    microstate_C = os.path.join(BINARY_DIR, f"microstate_C_{timestamp}.bin")
    
    args = [
        "-mode", "recovery",
        "-crystal", injury_crystal,
        "-target-entropy", "6.8",
        "-tolerance", "0.05",
        "-recovery-timeout", "10000000",
        "-output", microstate_C
    ]
    
    retcode = run_cpp_command(args, "Recovery Phase")
    
    if retcode == 0:
        print(f"\n[SUCCESS] Recovery fingerprint saved: {microstate_C}")
        return microstate_C
    elif retcode == 3:
        print("\n[WARNING] Recovery timeout - permanent injury suspected")
        if os.path.exists(microstate_C):
            return microstate_C  # Use whatever state we got
        else:
            return None
    else:
        print("\n[ERROR] Recovery phase failed")
        return None

def run_full_test():
    """
    Complete A→C test cycle.
    """
    print("\n" + "="*60)
    print("GHOST METRIC - FULL TEST CYCLE")
    print("="*60)
    print(f"Start time: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    
    # Phase 1: Baseline
    microstate_A = run_baseline_phase()
    if not microstate_A:
        print("[ERROR] Baseline phase failed - aborting")
        return False
    
    # We need a crystal file from baseline to continue
    # For now, use a placeholder - in reality, baseline should save a crystal
    baseline_crystal = os.path.join(CRYSTAL_DIR, "baseline.crys")
    print(f"[NOTE] Using placeholder crystal: {baseline_crystal}")
    
    # Phase 2: Injury
    injury_crystal = run_injury_phase(baseline_crystal)
    if not injury_crystal:
        print("[ERROR] Injury phase failed - aborting")
        return False
    
    # Phase 3: Recovery
    microstate_C = run_recovery_phase(injury_crystal)
    if not microstate_C:
        print("[ERROR] Recovery phase failed")
        # Continue to calculate with whatever we have
    
    # Calculate Ghost Metric
    print("\n" + "="*60)
    print("GHOST METRIC CALCULATION")
    print("="*60)
    
    state_A = capture_somatic_fingerprint(microstate_A)
    state_C = capture_somatic_fingerprint(microstate_C) if microstate_C else None
    
    result = calculate_ghost_metric(state_A, state_C)
    
    print(f"\nResults:")
    print(f"  Correlation (A, C): {result['correlation']}")
    print(f"  Hysteresis Depth:  {result['hysteresis_depth']}")
    print(f"  Status:            {result['status']}")
    print(f"  Memory Confirmed:  {result['memory_confirmed']}")
    print(f"  p-value:           {result['p_value']:.2e}")
    
    # Update VETO_THRESHOLD if memory confirmed
    if result['memory_confirmed']:
        update_veto_threshold(True)
    
    print(f"\n{'='*60}")
    print("TEST CYCLE COMPLETE")
    print(f"End time: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Result: {result['status']}")
    print("="*60)
    
    return result['memory_confirmed']

def main():
    """
    Main entry point.
    """
    if len(sys.argv) > 1:
        # Direct mode execution
        if sys.argv[1] == "baseline":
            run_baseline_phase()
        elif sys.argv[1] == "injury":
            if len(sys.argv) > 2:
                run_injury_phase(sys.argv[2])
            else:
                print("Usage: python ghost_metric.py injury <crystal_file>")
        elif sys.argv[1] == "recovery":
            if len(sys.argv) > 2:
                run_recovery_phase(sys.argv[2])
            else:
                print("Usage: python ghost_metric.py recovery <crystal_file>")
        elif sys.argv[1] == "full":
            run_full_test()
        elif sys.argv[1] == "calculate":
            if len(sys.argv) > 3:
                state_A = capture_somatic_fingerprint(sys.argv[2])
                state_C = capture_somatic_fingerprint(sys.argv[3])
                result = calculate_ghost_metric(state_A, state_C)
                print(f"Ghost Metric: {result}")
            else:
                print("Usage: python ghost_metric.py calculate <file_A> <file_C>")
        else:
            print("Unknown command")
    else:
        # Interactive mode
        print("Ghost Metric Driver")
        print("Available commands:")
        print("  baseline  - Run baseline phase")
        print("  injury <crystal> - Run injury phase")
        print("  recovery <crystal> - Run recovery phase")
        print("  full      - Run full A→C test cycle")
        print("  calculate <A> <C> - Calculate ghost metric")
        
        # Default to full test
        response = input("\nRun full test cycle? (y/n): ").strip().lower()
        if response == 'y':
            run_full_test()
        else:
            print("Exiting")

if __name__ == "__main__":
    main()