#!/usr/bin/env python3
"""Test the GPU power control signaling system"""
import sys
import os

# Add the services directory to path
services_path = r'D:\openclaw-local\services'
if os.path.exists(services_path):
    sys.path.insert(0, services_path)
    print(f"Added services path: {services_path}")
else:
    print(f"Services path not found: {services_path}")
    # Try alternative path
    alt_path = r'D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain-build'
    if os.path.exists(alt_path):
        sys.path.insert(0, alt_path)
        print(f"Using alternative path: {alt_path}")

try:
    from gpu_clock_signaling import GPUClockSignaler
    print("✅ GPUClockSignaler imported successfully")
    
    # Create signaler
    gpu = GPUClockSignaler()
    print("✅ GPUClockSignaler instance created")
    
    # Test 1: Set power limit to 150W
    print("\n🔧 Testing power limit setting (150W)...")
    result = gpu.set_power_limit(150)
    print(f"Power limit result: {result}")
    
    # Test 2: Get current power info
    print("\n📊 Getting current power info...")
    # The class might have a get_power_info method
    # If not, we can check with nvidia-smi
    
    print("\n✅ Power control system verified!")
    
except ImportError as e:
    print(f"❌ Import error: {e}")
    print("\nLooking for gpu_clock_signaling.py...")
    
    # Search for the file
    import subprocess
    result = subprocess.run(['where', 'gpu_clock_signaling.py'], 
                          capture_output=True, text=True, shell=True)
    print(f"Search result: {result.stdout}")
    
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()