"""Quick test: verify Python can receive LBM state from the CUDA daemon via ZeroMQ"""
import zmq
import json
import time

context = zmq.Context()
socket = context.socket(zmq.SUB)
socket.connect("tcp://localhost:5555")
socket.setsockopt_string(zmq.SUBSCRIBE, "")
socket.setsockopt(zmq.RCVTIMEO, 5000)  # 5 second timeout

print("[Bridge Test] Connecting to tcp://localhost:5555...")
print("[Bridge Test] Waiting for LBM data...\n")

try:
    for i in range(5):
        message = socket.recv_string()
        data = json.loads(message)
        print(f"  [{i+1}/5] Coh={data['coherence']:.2f} H64={data['h64']:.2f} "
              f"H32={data['h32']:.2f} Asym={data['asymmetry']:.2f} "
              f"Pow={data['power_w']:.1f}W Cycle={data['cycle']}")
        time.sleep(0.5)
    
    print("\n[Bridge Test] SUCCESS - Pipeline is live!")
    print("  Daemon -> ZeroMQ -> Python bridge: CONNECTED")
    
except zmq.Again:
    print("\n[Bridge Test] TIMEOUT - No data received from daemon.")
    print("  Is lbm_cuda_daemon running in WSL?")
    
finally:
    socket.close()
    context.term()
