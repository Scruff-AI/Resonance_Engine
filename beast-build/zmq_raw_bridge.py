# zmq_raw_bridge.py
# ZMQ Transparency: Raw data flow, no control

import zmq
import time
import sys

def raw_bridge():
    ctx = zmq.Context()
    
    # SUB socket — receive from LBM
    sub = ctx.socket(zmq.SUB)
    sub.connect("tcp://localhost:5556")
    sub.setsockopt_string(zmq.SUBSCRIBE, "")
    
    # Let the daemon warm up
    print("[Raw Bridge] Listening on port 5556...")
    print("[Raw Bridge] Waiting for daemon rhythm...\n")
    
    frame_count = 0
    last_print = time.time()
    
    while True:
        try:
            # Raw receive — no parsing, just presence check
            msg = sub.recv(flags=zmq.NOBLOCK)
            frame_count += 1
            
            # Print raw first 100 chars every second
            now = time.time()
            if now - last_print >= 1.0:
                raw = msg.decode('utf-8', errors='ignore')[:100]
                print(f"[{frame_count:5d}] {raw}")
                last_print = now
                frame_count = 0
                
        except zmq.Again:
            # No data — this is fine, daemon has its own rhythm
            time.sleep(0.001)
        except KeyboardInterrupt:
            print("\n[Raw Bridge] Stopping")
            break

if __name__ == "__main__":
    raw_bridge()
