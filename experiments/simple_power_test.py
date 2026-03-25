#!/usr/bin/env python3
"""Simple test of GPU power control"""
import sys
import os

# Try to find the module
possible_paths = [
    r'D:\openclaw-local\services',
    r'D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain-build',
    r'D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src'
]

for path in possible_paths:
    if os.path.exists(path):
        sys.path.insert(0, path)
        print(f"Added path: {path}")

try:
    import gpu_clock_signaling
    print("SUCCESS: gpu_clock_signaling module found")
    
    # Create instance
    gpu = gpu_clock_signaling.GPUClockSignaler()
    print("GPUClockSignaler instance created")
    
    # Test power limit
    print("Setting power limit to 150W...")
    result = gpu.set_power_limit(150)
    print(f"Result: {result}")
    
except ImportError:
    print("ERROR: gpu_clock_signaling module not found")
    print("Searching for file...")
    
    # List files in possible locations
    for path in possible_paths:
        if os.path.exists(path):
            py_files = [f for f in os.listdir(path) if f.endswith('.py')]
            print(f"Python files in {path}: {py_files}")
            
except Exception as e:
    print(f"ERROR: {e}")
    import traceback
    traceback.print_exc()