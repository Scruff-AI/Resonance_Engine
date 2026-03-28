# mock_lbm_daemon.py
# Simple mock LBM daemon for Open Feed testing

import zmq
import json
import time
import math

def mock_daemon():
    ctx = zmq.Context()
    pub = ctx.socket(zmq.PUB)
    pub.bind("tcp://*:5556")
    
    print("[Mock LBM] Starting on port 5556...")
    print("[Mock LBM] Simulating 1024x1024 grid with Khra'gixx signature")
    
    cycle = 0
    while True:
        # Simulate Khra'gixx wave: 64-cell + 16-cell harmonics
        khra = math.sin(cycle * 0.02) * math.cos(cycle * 0.015) * 2.0
        gixx = math.sin(cycle * 0.2) * 0.5
        
        coherence = 15.0 + khra + gixx
        h64 = 7.8 + khra * 0.5
        h32 = 0.01 + abs(gixx) * 0.1
        vorticity = 0.5 + abs(khra) * 0.3
        
        data = {
            "cycle": cycle,
            "coherence": coherence,
            "h64": h64,
            "h32": h32,
            "vorticity": vorticity,
            "asymmetry": abs(khra - gixx) * 0.1,
            "gpu_power_w": 50.0 + abs(khra) * 5.0,
            "gpu_temp_c": 45.0 + abs(khra) * 2.0,
            "gpu_mem_pct": 35.0,
            "grid": 1024
        }
        
        pub.send_json(data)
        
        if cycle % 100 == 0:
            print(f"[Mock LBM] Cycle {cycle}: Coh={coherence:.3f}, H64={h64:.3f}")
        
        cycle += 1
        time.sleep(0.01)  # 100Hz

if __name__ == "__main__":
    mock_daemon()
