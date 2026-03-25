#!/usr/bin/env python3
"""
Test if guardians form with different RHO_THRESH values
"""

import subprocess
import time
import os

def test_threshold(rho_thresh):
    """Test a specific RHO_THRESH value."""
    print(f"\n=== Testing RHO_THRESH = {rho_thresh} ===")
    
    # Read probe_256.cu
    with open("probe_256.cu", "r") as f:
        content = f.read()
    
    # Update RHO_THRESH
    import re
    new_content = re.sub(r'#define RHO_THRESH\s+[\d\.]+f', 
                        f'#define RHO_THRESH      {rho_thresh}f', 
                        content)
    
    # Write temporary file
    temp_file = f"probe_test_{rho_thresh}.cu"
    with open(temp_file, "w") as f:
        f.write(new_content)
    
    # Compile
    print("  Compiling...")
    compile_cmd = [
        "cmd", "/c",
        '"C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\VC\\Auxiliary\\Build\\vcvarsall.bat" x64',
        "&&",
        "nvcc", "-O3", "-arch=sm_61", "-o", f"probe_test_{rho_thresh}.exe",
        temp_file, "-lnvml"
    ]
    
    try:
        # Run compilation
        result = subprocess.run(" ".join(compile_cmd), shell=True, capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"  ✗ Compilation failed")
            print(f"    {result.stderr[:200]}")
            return None
        
        print("  ✓ Compiled")
        
        # Run test
        print("  Running for 5 seconds...")
        exe_path = f".\\probe_test_{rho_thresh}.exe"
        
        # Start process
        proc = subprocess.Popen(exe_path, stdout=subprocess.PIPE, stderr=subprocess.PIPE, 
                               text=True, bufsize=1, universal_newlines=True)
        
        # Read output for 5 seconds
        output_lines = []
        start_time = time.time()
        
        while time.time() - start_time < 5:
            line = proc.stdout.readline()
            if line:
                output_lines.append(line.strip())
                # Check for guardians
                if "part |" in line and not "part |     0" in line:
                    print(f"  ✓ GUARDIANS FOUND!")
                    proc.terminate()
                    return rho_thresh, True, line.strip()
        
        # Kill process
        proc.terminate()
        proc.wait(timeout=2)
        
        # Check output
        for line in output_lines[-20:]:
            if "part |" in line:
                print(f"  Output: {line}")
                if "part |     0" in line:
                    return rho_thresh, False, "No guardians"
                else:
                    return rho_thresh, True, line
        
        return rho_thresh, False, "No output found"
        
    except Exception as e:
        print(f"  ✗ Error: {e}")
        return None
    finally:
        # Cleanup
        try:
            os.remove(temp_file)
            os.remove(f"probe_test_{rho_thresh}.exe")
        except:
            pass

def main():
    print("=== FINDING OPTIMAL RHO_THRESH ===")
    print("Testing which threshold triggers guardian formation")
    print("="*50)
    
    # Test values around current density (1.00021)
    test_values = [
        1.00022,  # Just above current max
        1.00025,
        1.00030,
        1.00050,
        1.00100,
        1.00150,
        1.00200,
    ]
    
    results = []
    
    for rho in test_values:
        result = test_threshold(rho)
        if result:
            rho_val, success, info = result
            results.append((rho_val, success, info))
            
            if success:
                print(f"\n✅ SUCCESS! Guardians form at RHO_THRESH = {rho_val}")
                print(f"   This is the optimal threshold for this brain state")
                break
    
    # Summary
    print("\n" + "="*50)
    print("SUMMARY:")
    for rho, success, info in results:
        status = "✓" if success else "✗"
        print(f"  {status} RHO_THRESH = {rho:.5f}: {info}")
    
    # Find first successful threshold
    successful = [r for r in results if r[1]]
    if successful:
        optimal = successful[0][0]
        print(f"\n🎯 OPTIMAL THRESHOLD: {optimal:.5f}")
        print(f"   Use this value for 256×256 deployment")
    else:
        print(f"\n❌ NO GUARDIANS FORMED")
        print(f"   Brain state may be too uniform")
        print(f"   Try: 1. Create more varied brain state")
        print(f"        2. Run simulation longer to generate variations")
        print(f"        3. Test even lower thresholds (< 1.00022)")

if __name__ == "__main__":
    main()