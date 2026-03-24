# capture_state.py
import zmq
import json
import time

ctx = zmq.Context()
s = ctx.socket(zmq.SUB)
s.setsockopt_string(zmq.SUBSCRIBE, "")
s.connect("tcp://127.0.0.1:5556")
time.sleep(1)  # subscription propagation
poller = zmq.Poller()
poller.register(s, zmq.POLLIN)

print("Waiting for Khra'gixx data...")
frame = None
for i in range(50):
    events = poller.poll(5000)
    if not events:
        print(f"  Attempt {i+1}/50: No data")
        continue
    msg = s.recv()
    frame = json.loads(msg)
    if frame["asymmetry"] > 1.0:
        break

if frame:
    print(f"Cycle {frame['cycle']}: Asymmetry={frame['asymmetry']:.2f}, Coherence={frame['coherence']:.3f}")
    with open("current_state.json", "w") as f:
        json.dump(frame, f)
    print("State saved to current_state.json")
else:
    print("No data received")
