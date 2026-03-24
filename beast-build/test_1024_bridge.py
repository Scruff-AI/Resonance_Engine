# test_1024_bridge.py
# Test connection to 1024x1024 daemon on port 5556

import zmq
import json
import time

print("=" * 70)
print("TESTING 1024x1024 GRID CONNECTION")
print("=" * 70)
print()

context = zmq.Context()
socket = context.socket(zmq.SUB)
socket.connect("tcp://localhost:5556")
socket.setsockopt_string(zmq.SUBSCRIBE, "")

print("Connected to tcp://localhost:5556")
print("Waiting for data...")
print()

# Receive 5 samples
for i in range(5):
    try:
        message = socket.recv_json(flags=zmq.NOBLOCK)
        print(f"Sample {i+1}:")
        print(f"  Grid size: {message.get('grid_size', 'unknown')}")
        print(f"  Coherence: {message.get('coherence', 0):.2f}")
        print(f"  H64: {message.get('h64', 0):.2f}")
        print(f"  H32: {message.get('h32', 0):.2f}")
        print(f"  Power: {message.get('power_w', 0):.1f}W")
        print(f"  Cycle: {message.get('cycle', 0)}")
        print()
        time.sleep(0.1)
    except zmq.Again:
        print(f"Sample {i+1}: No data yet...")
        time.sleep(0.5)

print("=" * 70)
print("Test complete")
print("=" * 70)
