#!/usr/bin/env python3
"""
Sentry Monitor — Logic-triggered checkpoint saves for Khra'gixx v3
Subscribes to telemetry on 5556, sends save_state on 5557 when:
  - Coherence shift > 0.05 (rolling window)
  - GPU temp > 75°C
  - Asymmetry spike > 2σ (rolling window)
"""

import zmq
import json
import time
import sys
import os
from collections import deque

# === CONFIG ===
TELEMETRY_PORT = 5556
COMMAND_PORT = 5557
COH_THRESHOLD = 0.15       # coherence delta trigger (was 0.05 — too sensitive)
TEMP_THRESHOLD = 82         # °C (was 75 — normal operating range)
ASYM_SIGMA = 3.5            # standard deviation multiplier (was 2.0 — too twitchy)
WINDOW_SIZE = 100           # rolling window for stats (was 50)
SAVE_COOLDOWN = 300.0       # seconds between triggered saves (was 30 — way too fast)
MAX_SAVES = 200             # keep at most this many checkpoints, delete oldest
SAVE_DIR = "/mnt/d/Resonance_Engine/beast-build/sentry_saves"

# === STATE ===
coh_window = deque(maxlen=WINDOW_SIZE)
asym_window = deque(maxlen=WINDOW_SIZE)
last_save_time = 0.0
save_count = 0
msg_count = 0


def send_save(cmd_socket, reason, cycle):
    """Send save_state command to v3 daemon. Path = directory (v3 creates file inside)."""
    global last_save_time, save_count
    now = time.time()
    if now - last_save_time < SAVE_COOLDOWN:
        return  # cooldown active

    save_count += 1
    # v3/v4 save_checkpoint expects a directory — just use SAVE_DIR
    msg = json.dumps({"cmd": "save_state", "path": SAVE_DIR}, separators=(",", ":"))
    cmd_socket.send_string(msg)
    last_save_time = now
    print(f"[SENTRY SAVE #{save_count}] cycle={cycle} reason={reason} -> {SAVE_DIR}")
    sys.stdout.flush()
    prune_old_saves()


def prune_old_saves():
    """Delete oldest checkpoints if we exceed MAX_SAVES."""
    try:
        files = sorted(
            (os.path.join(SAVE_DIR, f) for f in os.listdir(SAVE_DIR) if f.endswith(".bin")),
            key=os.path.getmtime
        )
        excess = len(files) - MAX_SAVES
        if excess > 0:
            for path in files[:excess]:
                os.remove(path)
            print(f"[SENTRY] Pruned {excess} old checkpoints, {len(files) - excess} remain")
            sys.stdout.flush()
    except OSError as e:
        print(f"[SENTRY] Prune error: {e}")
        sys.stdout.flush()


def mean_std(window):
    """Compute mean and std of deque."""
    if len(window) < 2:
        return 0.0, 0.0
    n = len(window)
    m = sum(window) / n
    variance = sum((x - m) ** 2 for x in window) / (n - 1)
    return m, variance ** 0.5


def main():
    global msg_count, save_count
    os.makedirs(SAVE_DIR, exist_ok=True)

    ctx = zmq.Context()

    # Subscribe to telemetry
    sub = ctx.socket(zmq.SUB)
    sub.connect(f"tcp://localhost:{TELEMETRY_PORT}")
    sub.setsockopt_string(zmq.SUBSCRIBE, "")
    sub.setsockopt(zmq.RCVTIMEO, 5000)

    # Command channel
    cmd = ctx.socket(zmq.PUB)
    cmd.connect(f"tcp://localhost:{COMMAND_PORT}")
    time.sleep(2)  # let ZMQ subscription propagate

    print(f"[SENTRY] Monitoring telemetry on :{TELEMETRY_PORT}, commands on :{COMMAND_PORT}")
    print(f"[SENTRY] Triggers: coh_shift>{COH_THRESHOLD}, temp>{TEMP_THRESHOLD}°C, asym>{ASYM_SIGMA}σ")
    print(f"[SENTRY] Save cooldown: {SAVE_COOLDOWN}s, window: {WINDOW_SIZE} samples, max_saves: {MAX_SAVES}")
    print(f"[SENTRY] Save dir: {SAVE_DIR}")

    # Prune on startup in case we're over the cap
    prune_old_saves()
    sys.stdout.flush()

    while True:
        try:
            raw = sub.recv_string()
        except zmq.Again:
            print("[SENTRY] No telemetry for 5s — daemon alive?")
            sys.stdout.flush()
            continue

        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            continue

        msg_count += 1

        cycle = data.get("cycle", 0)
        coh = data.get("coherence", None)
        asym = data.get("asymmetry", None)
        temp = data.get("gpu_temp_c", None)

        # Periodic heartbeat
        if msg_count % 100 == 0:
            print(f"[SENTRY] heartbeat: cycle={cycle}, coh={coh}, asym={asym}, temp={temp}, saves={save_count}")
            sys.stdout.flush()

        # --- TRIGGER 1: Temperature ---
        if temp is not None and temp > TEMP_THRESHOLD:
            send_save(cmd, f"temp_{temp}C", cycle)

        # --- TRIGGER 2: Coherence shift ---
        if coh is not None:
            coh_window.append(coh)
            if len(coh_window) >= 10:
                recent = list(coh_window)[-5:]
                older = list(coh_window)[:-5]
                recent_mean = sum(recent) / len(recent)
                older_mean = sum(older) / len(older)
                delta = abs(recent_mean - older_mean)
                if delta > COH_THRESHOLD:
                    send_save(cmd, f"coh_shift_{delta:.4f}", cycle)

        # --- TRIGGER 3: Asymmetry spike ---
        if asym is not None:
            asym_window.append(asym)
            if len(asym_window) >= 10:
                mean_a, std_a = mean_std(asym_window)
                if std_a > 0 and abs(asym - mean_a) > ASYM_SIGMA * std_a:
                    send_save(cmd, f"asym_spike_{asym:.4f}", cycle)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n[SENTRY] Shutdown. Total saves: {save_count}")
