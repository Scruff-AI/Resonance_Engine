# test_forge_daemon.py
import zmq
import time
import json

ctx = zmq.Context()
sock = ctx.socket(zmq.SUB)
sock.connect("tcp://localhost:5556")
sock.setsockopt_string(zmq.SUBSCRIBE, "")

print("Waiting for FORGE data...")
received = False
for i in range(30):
    try:
        msg = sock.recv(flags=zmq.NOBLOCK)
        data = json.loads(msg)
        print(f"Cycle {data['cycle']}: Coh={data['coherence']:.3f}, H64={data['h64']:.3f}, H32={data['h32']:.4f}, Vort={data['vorticity']:.3f}")
        received = True
        break
    except zmq.Again:
        time.sleep(0.1)
    except Exception as e:
        print(f"Error: {e}")
        break

if not received:
    print("No data received after 3 seconds")
    print("Checking if daemon is still running...")
    import subprocess
    result = subprocess.run(['ps', 'aux'], capture_output=True, text=True)
    if 'lbm_1024x1024_forge' in result.stdout:
        print("Daemon process found")
    else:
        print("Daemon process NOT found — may have crashed")
