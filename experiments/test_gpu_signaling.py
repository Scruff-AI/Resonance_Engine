#!/usr/bin/env python3
"""Test GPU clock signaling system"""
import json
import time
from pathlib import Path

# Use the existing signaling directory
signal_dir = Path(r"D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain-build\gpu_clock_signal")
request_file = signal_dir / "request.json"
response_file = signal_dir / "response.json"

# Create test request
test_request = {
    "timestamp": "2026-03-11T11:20:00.000000",
    "command": "pl",  # Power limit
    "parameters": {"watts": 150},
    "status": "pending"
}

print(f"Writing request to: {request_file}")
print(f"Request: {json.dumps(test_request, indent=2)}")

# Write request
with open(request_file, 'w') as f:
    json.dump(test_request, f, indent=2)

print("\nWaiting for response... (30 second timeout)")

# Wait for response
timeout = 30
start_time = time.time()
response_received = False

while time.time() - start_time < timeout:
    if response_file.exists():
        try:
            with open(response_file, 'r') as f:
                response = json.load(f)
            print(f"\nResponse received: {json.dumps(response, indent=2)}")
            response_received = True
            break
        except Exception as e:
            print(f"Error reading response: {e}")
            break
    time.sleep(0.5)

if not response_received:
    print("\nNo response received. The GPU_Clock_Service.ps1 is likely not running.")
    print("\nTo fix this:")
    print("1. Open PowerShell as Administrator")
    print("2. Run: cd 'D:\\openclaw-docker-BACKUP-DO-NOT-USE\\seed-brain-build'")
    print("3. Run: .\\GPU_Clock_Service.ps1")
    print("\nOr register as scheduled task (see script comments)")