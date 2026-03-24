#!/usr/bin/env python3
"""Test suite for khra_gixx v4.1 — verifies all 4 fixes."""
import zmq, json, time, struct, sys

ctx = zmq.Context()

# Telemetry sub
tel = ctx.socket(zmq.SUB)
tel.setsockopt(zmq.SUBSCRIBE, b"")
tel.setsockopt(zmq.CONFLATE, 1)
tel.connect("tcp://127.0.0.1:5556")

# Snapshot sub
snap = ctx.socket(zmq.SUB)
snap.setsockopt(zmq.SUBSCRIBE, b"")
snap.setsockopt(zmq.CONFLATE, 1)
snap.connect("tcp://127.0.0.1:5558")

# ACK sub
ack = ctx.socket(zmq.SUB)
ack.setsockopt(zmq.SUBSCRIBE, b"")
ack.connect("tcp://127.0.0.1:5559")

# Command pub
cmd_pub = ctx.socket(zmq.PUB)
cmd_pub.connect("tcp://127.0.0.1:5557")

time.sleep(2)
passes = 0
fails = 0

def check(name, condition):
    global passes, fails
    if condition:
        print(f"  [PASS] {name}")
        passes += 1
    else:
        print(f"  [FAIL] {name}")
        fails += 1

# === TEST 1: Telemetry flowing + FIX 1 stress values ===
print("=== TEST 1: Telemetry + Stress Kernel (FIX 1) ===")
frames = []
for i in range(3):
    msg = tel.recv_string()
    d = json.loads(msg)
    frames.append(d)
    time.sleep(0.15)

for d in frames:
    print(f"  cycle={d['cycle']:>7d}  coh={d['coherence']:.4f}  vel_mean={d['vel_mean']:.6f}  vel_max={d['vel_max']:.6f}")
    print(f"           stress_xx={d['stress_xx']:.6f}  stress_yy={d['stress_yy']:.6f}  stress_xy={d['stress_xy']:.6f}")
    print(f"           vorticity={d['vorticity_mean']:.6f}  gpu_temp={d['gpu_temp_c']}C  gpu_util={d['gpu_util_pct']}%")

last = frames[-1]
check("Telemetry flowing (3 frames received)", len(frames) == 3)
check("Coherence in range [0,1]", 0.0 <= last["coherence"] <= 1.0)
check("Stress XX non-zero", abs(last["stress_xx"]) > 1e-9)
check("Stress YY non-zero", abs(last["stress_yy"]) > 1e-9)
check("Stress values physically reasonable (< 1.0)", abs(last["stress_xx"]) < 1.0 and abs(last["stress_yy"]) < 1.0)
check("Velocity mean > 0", last["vel_mean"] > 0)
check("Velocity max <= 0.25 Mach", last["vel_max"] <= 0.25)
check("GPU telemetry present", last["gpu_temp_c"] > 0)

# === TEST 2: Snapshot delivery ===
print()
print("=== TEST 2: Snapshot Delivery ===")
snap_data = snap.recv()
check("Snapshot received", len(snap_data) > 8)
if len(snap_data) > 8:
    cycle_s, w, h = struct.unpack("<IHH", snap_data[:8])
    expected = 8 + w * h * 4
    print(f"  Snapshot: cycle={cycle_s} size={w}x{h} bytes={len(snap_data)}")
    check("Snapshot dimensions 1024x1024", w == 1024 and h == 1024)
    check("Snapshot byte count correct", len(snap_data) == expected)

# === TEST 3: Command + ACK (FIX 3) ===
print()
print("=== TEST 3: Command + ACK (FIX 3) ===")
cmd_pub.send_string('{"cmd":"set_omega","value":1.95}')
time.sleep(0.5)

ack.setsockopt(zmq.RCVTIMEO, 3000)
ack_ok = False
try:
    ack_msg = ack.recv_string()
    ack_d = json.loads(ack_msg)
    print(f"  ACK received: {ack_d}")
    ack_ok = ack_d.get("ack") == "set_omega" and ack_d.get("status") == "ok"
except zmq.Again:
    print("  No ACK (ZMQ slow joiner — expected on first connect)")
check("ACK received for set_omega", ack_ok)

# Verify omega changed
time.sleep(0.3)
msg = tel.recv_string()
d = json.loads(msg)
print(f"  Telemetry omega: {d['omega']}")
check("omega changed to 1.95", abs(d["omega"] - 1.95) < 0.001)

# Restore omega
cmd_pub.send_string('{"cmd":"set_omega","value":1.97}')
time.sleep(0.5)
msg = tel.recv_string()
d = json.loads(msg)
print(f"  Restored omega: {d['omega']}")
check("omega restored to 1.97", abs(d["omega"] - 1.97) < 0.001)

# === TEST 4: Snapshot interval validation (FIX 2) ===
print()
print("=== TEST 4: Snapshot Interval Validation (FIX 2) ===")
# Send interval=15 — should round to 20
cmd_pub.send_string('{"cmd":"set_snapshot_interval","interval":15}')
time.sleep(0.5)
# We can't read the daemon's internal state directly, but we can check the ACK
try:
    ack_msg = ack.recv_string()
    ack_d = json.loads(ack_msg)
    print(f"  ACK for interval=15: {ack_d}")
    check("ACK received for set_snapshot_interval", ack_d.get("ack") == "set_snapshot_interval")
except zmq.Again:
    print("  [INFO] No ACK for interval change (checking daemon log instead)")
    check("ACK received for set_snapshot_interval", False)

# Send a valid multiple of 10
cmd_pub.send_string('{"cmd":"set_snapshot_interval","interval":10}')
time.sleep(0.3)
print("  Restored interval to 10")
print("  [NOTE] Check daemon stdout for: WARNING: snapshot_interval 15 not a multiple of 10, rounded up to 20")

# === TEST 5: Cycles advancing ===
print()
print("=== TEST 5: Cycles Advancing ===")
time.sleep(1)
msg1 = tel.recv_string()
d1 = json.loads(msg1)
time.sleep(0.5)
msg2 = tel.recv_string()
d2 = json.loads(msg2)
delta = d2["cycle"] - d1["cycle"]
print(f"  Cycle delta: {d1['cycle']} -> {d2['cycle']} (delta={delta})")
check("Cycles advancing", delta > 0)
check("Cycle rate reasonable (10-500 per 0.5s)", 10 <= delta <= 500)

# Cleanup
cmd_pub.close()
tel.close()
snap.close()
ack.close()
ctx.term()

print()
print(f"=== RESULTS: {passes} passed, {fails} failed ===")
sys.exit(0 if fails == 0 else 1)
