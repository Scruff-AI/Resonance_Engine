# test_zmq.py
import zmq
import json
import time

ctx = zmq.Context()
sub = ctx.socket(zmq.SUB)
sub.setsockopt_string(zmq.SUBSCRIBE, "")
sub.connect("tcp://127.0.0.1:5556")
time.sleep(1)

print("Waiting for telemetry...")
for i in range(50):
    try:
        msg = sub.recv(flags=zmq.NOBLOCK)
        frame = json.loads(msg.decode('utf-8'))
        print(f"Cycle {frame['cycle']}: Asym={frame['asymmetry']:.2f}, Coh={frame['coherence']:.3f}")
        break
    except zmq.Again:
        time.sleep(0.05)
else:
    print("No telemetry received")
