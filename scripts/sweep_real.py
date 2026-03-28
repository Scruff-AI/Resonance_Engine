#!/usr/bin/env python3
"""
EM Frequency Sweep - Real Data Collection
No bullshit. Just numbers.
"""

import zmq
import json
import time
import csv
import requests
from datetime import datetime
import sys
import os

OBSERVER_URL = "http://127.0.0.1:28820"
OUTPUT_FILE = "/mnt/d/Resonance_Engine/sweep_results/em_sweep_real.csv"

# Sweep ranges - reduced for faster collection
OMEGA_VALUES = [round(0.5 + 0.1*i, 1) for i in range(21)]  # 0.5 to 2.5
KHRA_VALUES = [0.01, 0.03, 0.05]  # Reduced from 5 to 3 values
GIXX_VALUES = [0.004, 0.008, 0.012]  # Reduced from 5 to 3 values

STABILIZE_TIME = 2  # Reduced from 3 to 2 seconds

def send_zmq_command(cmd, value=None):
    """Send command. No waiting."""
    try:
        context = zmq.Context()
        socket = context.socket(zmq.PUB)
        socket.connect("tcp://localhost:5557")
        socket.setsockopt(zmq.LINGER, 0)
        time.sleep(0.1)
        
        if value is not None:
            msg = json.dumps({"cmd": cmd, "value": float(value)})
        else:
            msg = json.dumps({"cmd": cmd})
        
        socket.send_string(msg)
        socket.close()
        context.term()
        return True
    except:
        return False

def get_telemetry():
    """Get telemetry."""
    try:
        response = requests.get(f"{OBSERVER_URL}/telemetry", timeout=5)
        return response.json()
    except:
        return None

def main():
    total_points = len(OMEGA_VALUES) * len(KHRA_VALUES) * len(GIXX_VALUES)
    
    print(f"SWEEP START: {total_points} points")
    print(f"Output: {OUTPUT_FILE}")
    print("")
    
    # Ensure directory exists
    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
    
    point_count = 0
    
    with open(OUTPUT_FILE, 'w', newline='', buffering=1) as f:  # Line buffered
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'omega', 'khra_amp', 'gixx_amp', 'coherence', 'asymmetry', 'vorticity_mean', 'gpu_temp_c', 'gpu_power_w', 'cycle'])
        f.flush()
        
        for omega in OMEGA_VALUES:
            for khra in KHRA_VALUES:
                for gixx in GIXX_VALUES:
                    point_count += 1
                    print(f"[{point_count}/{total_points}] omega={omega} khra={khra} gixx={gixx}")
                    
                    # Send commands
                    send_zmq_command("set_omega", omega)
                    time.sleep(0.1)
                    send_zmq_command("set_khra_amp", khra)
                    time.sleep(0.1)
                    send_zmq_command("set_gixx_amp", gixx)
                    
                    # Wait
                    time.sleep(STABILIZE_TIME)
                    
                    # Get data
                    telem = get_telemetry()
                    if telem:
                        row = [
                            datetime.now().isoformat(),
                            omega, khra, gixx,
                            telem.get('coherence', 0),
                            telem.get('asymmetry', 0),
                            telem.get('vorticity_mean', 0),
                            telem.get('gpu_temp_c', 0),
                            telem.get('gpu_power_w', 0),
                            telem.get('cycle', 0)
                        ]
                        writer.writerow(row)
                        f.flush()  # Force write to disk
                        print(f"  -> Coh={telem.get('coherence', 0):.4f} T={telem.get('gpu_temp_c', 0)}C P={telem.get('gpu_power_w', 0)}W")
                    else:
                        print(f"  -> FAILED")
                    
                    if point_count % 10 == 0:
                        print(f"PROGRESS: {point_count}/{total_points}")
    
    print(f"")
    print(f"SWEEP COMPLETE: {point_count} points")
    print(f"Output: {OUTPUT_FILE}")

if __name__ == "__main__":
    main()
