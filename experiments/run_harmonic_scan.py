#!/usr/bin/env python3
"""
Run Harmonic Scan with 150W Power Cap
Energy-First Evolutionary Squeeze Experiment
"""
import sys
import os
import subprocess
import time
import json
from pathlib import Path

# Add paths for GPU control
sys.path.insert(0, r'D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src')

try:
    from gpu_clock_signaling import GPUClockSignaler
    gpu = GPUClockSignaler()
    print("GPU Clock Signaler loaded")
except ImportError as e:
    print(f"Warning: Could not load GPUClockSignaler: {e}")
    gpu = None

def set_power_limit(watts):
    """Set GPU power limit"""
    if gpu:
        print(f"Setting power limit to {watts}W...")
        result = gpu.set_power_limit(watts)
        print(f"Power limit result: {result}")
    else:
        print(f"Would set power limit to {watts}W (GPU control not available)")

def compile_grid_version(nx, ny, steps=50000):
    """Compile fractal_habit for specific grid size with step limit"""
    print(f"\n{'='*60}")
    print(f"Compiling {nx}x{ny} version ({steps} steps)")
    print(f"{'='*60}")
    
    source_dir = r"D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src"
    output_dir = r"D:\openclaw-local\workspace-main\harmonic_scan_experiment"
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    grid_dir = os.path.join(output_dir, f"{nx}x{ny}")
    os.makedirs(grid_dir, exist_ok=True)
    
    # Read source file
    source_file = os.path.join(source_dir, "fractal_habit.cu")
    with open(source_file, 'r') as f:
        source_content = f.read()
    
    # Modify grid size and step count
    modified_content = source_content
    modified_content = modified_content.replace('#define NX   1024', f'#define NX   {nx}')
    modified_content = modified_content.replace('#define NY   1024', f'#define NY   {ny}')
    modified_content = modified_content.replace('#define TOTAL_STEPS      10000000', 
                                               f'#define TOTAL_STEPS      {steps}')
    modified_content = modified_content.replace('10M steps', f'{steps//1000}k steps')
    modified_content = modified_content.replace('Steps:     10000000', f'Steps:     {steps}')
    
    # Write modified source
    modified_file = os.path.join(grid_dir, f"fractal_habit_{nx}x{ny}.cu")
    with open(modified_file, 'w') as f:
        f.write(modified_content)
    
    # Compile
    print(f"Compiling {nx}x{ny}...")
    
    # Use the same compilation command as before
    compile_cmd = f'cd /d "C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\VC\\Auxiliary\\Build" && call vcvars64.bat > nul 2>&1 && cd /d "{grid_dir}" && nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 fractal_habit_{nx}x{ny}.cu -o fractal_habit_{nx}x{ny}.exe -lnvml -lcufft'
    
    result = subprocess.run(['cmd', '/c', compile_cmd], 
                          capture_output=True, text=True, shell=True)
    
    if result.returncode == 0:
        print(f"✅ Compiled successfully: {nx}x{ny}")
        exe_path = os.path.join(grid_dir, f"fractal_habit_{nx}x{ny}.exe")
        if os.path.exists(exe_path):
            size = os.path.getsize(exe_path)
            print(f"   Executable: {size:,} bytes")
        return grid_dir
    else:
        print(f"❌ Compilation failed for {nx}x{ny}")
        print(f"   Error: {result.stderr}")
        return None

def run_experiment(grid_dir, nx, ny):
    """Run the compiled experiment"""
    print(f"\nRunning {nx}x{ny} experiment...")
    
    exe_path = os.path.join(grid_dir, f"fractal_habit_{nx}x{ny}.exe")
    if not os.path.exists(exe_path):
        print(f"❌ Executable not found: {exe_path}")
        return None
    
    # Create build directory with brain state
    build_dir = os.path.join(grid_dir, "build")
    os.makedirs(build_dir, exist_ok=True)
    
    # Copy appropriate brain state
    brain_state_source = r"D:\openclaw-local\workspace-main\harmonic_brain_states"
    brain_state_file = os.path.join(brain_state_source, f"build_{nx}x{ny}", "f_state_post_relax.bin")
    
    if os.path.exists(brain_state_file):
        import shutil
        shutil.copy(brain_state_file, os.path.join(build_dir, "f_state_post_relax.bin"))
        print(f"   Brain state: {os.path.getsize(brain_state_file):,} bytes")
    else:
        print(f"   Warning: No brain state for {nx}x{ny}")
        # Create empty file as placeholder
        open(os.path.join(build_dir, "f_state_post_relax.bin"), 'w').close()
    
    # Run the executable
    output_file = os.path.join(grid_dir, f"output_{nx}x{ny}.log")
    print(f"   Output: {output_file}")
    
    # Run in background
    cmd = f'cd /d "{grid_dir}" && fractal_habit_{nx}x{ny}.exe > "{output_file}" 2>&1'
    process = subprocess.Popen(['cmd', '/c', cmd], shell=True)
    
    print(f"   Process started: PID {process.pid}")
    
    # Wait a bit for initial output
    time.sleep(2)
    
    # Check if it's running
    if process.poll() is None:
        print(f"   Experiment running...")
        return process
    else:
        print(f"   Process exited with code {process.returncode}")
        # Check output
        if os.path.exists(output_file):
            with open(output_file, 'r') as f:
                lines = f.readlines()
                for line in lines[-5:]:
                    print(f"   {line.strip()}")
        return None

def main():
    print("="*70)
    print("ENERGY-FIRST EVOLUTIONARY SQUEEZE EXPERIMENT")
    print("150W Metabolic Cap - Harmonic Grid Scan")
    print("="*70)
    
    # Set power limit to 150W
    set_power_limit(150)
    
    # Grid sizes to test (harmonic steps)
    grid_sizes = [
        (1024, 1024),  # Baseline
        (896, 896),    # 12.5% reduction
        (768, 768),    # 25% reduction
        (640, 640),    # 37.5% reduction
        (512, 512)     # 50% reduction
    ]
    
    processes = []
    
    for nx, ny in grid_sizes:
        # Compile
        grid_dir = compile_grid_version(nx, ny, steps=50000)
        
        if grid_dir:
            # Run experiment
            process = run_experiment(grid_dir, nx, ny)
            if process:
                processes.append((nx, ny, process))
        
        # Small delay between compilations
        time.sleep(1)
    
    print(f"\n{'='*70}")
    print(f"Experiments launched: {len(processes)}")
    print("Monitoring output files for spectral slope results...")
    print("\nKey metric: Spectral slope (sl)")
    print("  - Good: sl ≈ -2.0 to -2.5 (coherent, power-law)")
    print("  - Bad:  sl ≈ -0.5 (white noise, harmonic mismatch)")
    print(f"{'='*70}")
    
    # Give them time to run
    print("\nWaiting for experiments to complete (approx 1-2 minutes each)...")
    time.sleep(30)
    
    # Check results
    print("\n" + "="*70)
    print("PRELIMINARY RESULTS (checking output files)")
    print("="*70)
    
    results = []
    for nx, ny, process in processes:
        output_file = os.path.join(r"D:\openclaw-local\workspace-main\harmonic_scan_experiment", 
                                  f"{nx}x{ny}", f"output_{nx}x{ny}.log")
        
        if os.path.exists(output_file):
            with open(output_file, 'r') as f:
                content = f.read()
                
            # Extract spectral slope if available
            import re
            slope_match = re.search(r'sl=([-\d.]+)', content)
            power_match = re.search(r'\| ([\d.]+)W', content)
            
            slope = slope_match.group(1) if slope_match else "N/A"
            power = power_match.group(1) if power_match else "N/A"
            
            results.append({
                'grid': f"{nx}x{ny}",
                'slope': slope,
                'power': power,
                'status': 'completed' if process.poll() is not None else 'running'
            })
            
            print(f"{nx}x{ny}: sl={slope}, power={power}W, status={results[-1]['status']}")
    
    # Kill any remaining processes
    for nx, ny, process in processes:
        if process.poll() is None:
            process.terminate()
    
    print(f"\n{'='*70}")
    print("EXPERIMENT COMPLETE")
    print("Next: Analyze spectral slopes to find harmonic sweet spot")
    print(f"{'='*70}")
    
    # Save results
    results_file = os.path.join(r"D:\openclaw-local\workspace-main\harmonic_scan_experiment", 
                               "results_summary.json")
    with open(results_file, 'w') as f:
        json.dump(results, f, indent=2)
    
    print(f"\nResults saved to: {results_file}")

if __name__ == "__main__":
    main()