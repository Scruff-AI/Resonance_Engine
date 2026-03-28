#!/usr/bin/env python3
"""
EM Frequency Sweep - Direct ZMQ Version (v2)
Persistent PUB socket with ACK verification.
Bypasses observer /ask endpoint, sends commands directly to daemon.
"""

import zmq
import json
import time
import csv
import requests
from datetime import datetime
import sys
import atexit

OBSERVER_URL = "http://127.0.0.1:28820"
COMMAND_PORT = 5557
ACK_PORT = 5559

# Sweep ranges — omega capped at 1.99 (daemon rejects > 1.99)
OMEGA_VALUES = [round(0.5 + 0.1*i, 1) for i in range(15)]   # 0.5 to 1.9
KHRA_VALUES = [round(0.01 + 0.01*i, 2) for i in range(5)]    # 0.01 to 0.05
GIXX_VALUES = [round(0.004 + 0.002*i, 3) for i in range(5)]  # 0.004 to 0.012

STABILIZE_TIME = 3  # seconds
ACK_TIMEOUT_MS = 5000  # 5s per ACK

# Safety limits
MAX_TEMP = 64
MAX_POWER = 320

# --- Persistent ZMQ sockets (module-level, created once) ---
_ctx = zmq.Context()

_cmd_pub = _ctx.socket(zmq.PUB)
_cmd_pub.setsockopt(zmq.LINGER, 1000)
_cmd_pub.connect(f"tcp://127.0.0.1:{COMMAND_PORT}")

_ack_sub = _ctx.socket(zmq.SUB)
_ack_sub.connect(f"tcp://127.0.0.1:{ACK_PORT}")
_ack_sub.setsockopt_string(zmq.SUBSCRIBE, "")
_ack_sub.setsockopt(zmq.RCVTIMEO, ACK_TIMEOUT_MS)


def _cleanup():
    _cmd_pub.close()
    _ack_sub.close()
    _ctx.term()

atexit.register(_cleanup)


def drain_acks():
    """Drain any stale ACKs from the SUB socket."""
    count = 0
    while True:
        try:
            _ack_sub.recv_string(zmq.NOBLOCK)
            count += 1
        except zmq.Again:
            break
    return count


def send_zmq_command(cmd, value=None):
    """Send command via persistent PUB socket, verify ACK."""
    if value is not None:
        msg = json.dumps({"cmd": cmd, "value": float(value)})
    else:
        msg = json.dumps({"cmd": cmd})

    _cmd_pub.send_string(msg)

    # Wait for ACK
    try:
        ack_raw = _ack_sub.recv_string()
        ack = json.loads(ack_raw)
        if ack.get("status") == "ok":
            return True
        else:
            print(f"  [ACK] {cmd}: {ack.get('status', 'unknown')}")
            return False
    except zmq.Again:
        # Retry once
        print(f"  [RETRY] No ACK for {cmd}, resending...")
        _cmd_pub.send_string(msg)
        try:
            ack_raw = _ack_sub.recv_string()
            ack = json.loads(ack_raw)
            if ack.get("status") == "ok":
                return True
            print(f"  [ACK] {cmd} retry: {ack.get('status', 'unknown')}")
            return False
        except zmq.Again:
            print(f"  [FAIL] No ACK for {cmd} after retry")
            return False

def get_telemetry():
    """Get current telemetry from observer."""
    try:
        response = requests.get(f"{OBSERVER_URL}/telemetry", timeout=5)
        return response.json()
    except Exception as e:
        print(f"  Telemetry Error: {e}")
        return None

def main():
    timestamp_tag = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = f"/mnt/d/Resonance_Engine/sweep_results/em_direct_sweep_{timestamp_tag}.csv"

    total_points = len(OMEGA_VALUES) * len(KHRA_VALUES) * len(GIXX_VALUES)

    print("=" * 60)
    print("EM Frequency Sweep - Direct ZMQ v2 (persistent socket + ACK)")
    print("=" * 60)
    print(f"Omega range: {OMEGA_VALUES[0]} - {OMEGA_VALUES[-1]} ({len(OMEGA_VALUES)} steps)")
    print(f"Khra range:  {KHRA_VALUES[0]} - {KHRA_VALUES[-1]} ({len(KHRA_VALUES)} steps)")
    print(f"Gixx range:  {GIXX_VALUES[0]} - {GIXX_VALUES[-1]} ({len(GIXX_VALUES)} steps)")
    print(f"Total points: {total_points}")
    print(f"Output: {output_file}")
    print()

    # Wait for ZMQ subscription propagation (matching Observer pattern)
    print("Waiting 2s for ZMQ subscription propagation...")
    time.sleep(2.0)
    drained = drain_acks()
    if drained:
        print(f"  Drained {drained} stale ACK(s)")

    # Capture initial state for restore
    initial = get_telemetry()
    if not initial:
        print("ERROR: Cannot read telemetry — aborting")
        sys.exit(1)
    restore_omega = initial.get('omega', 1.5)
    restore_khra = initial.get('khra_amp', 0.02)
    restore_gixx = initial.get('gixx_amp', 0.008)
    print(f"Initial state: Ω={restore_omega} K={restore_khra} G={restore_gixx}")
    print()

    # Create CSV
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow([
            'timestamp', 'omega', 'khra_amp', 'gixx_amp',
            'coherence', 'asymmetry', 'vorticity_mean',
            'gpu_temp_c', 'gpu_power_w', 'cycle'
        ])

        point_count = 0
        fail_count = 0

        for omega in OMEGA_VALUES:
            for khra in KHRA_VALUES:
                for gixx in GIXX_VALUES:
                    point_count += 1
                    print(f"\n[{point_count}/{total_points}] Ω={omega} K={khra} G={gixx}")

                    # Safety check
                    telem_pre = get_telemetry()
                    if telem_pre:
                        temp = telem_pre.get('gpu_temp_c', 0)
                        power = telem_pre.get('gpu_power_w', 0)
                        if temp > MAX_TEMP:
                            print(f"  THERMAL PAUSE: {temp}C > {MAX_TEMP}C, cooling...")
                            while True:
                                time.sleep(5)
                                t = get_telemetry()
                                if t and t.get('gpu_temp_c', 99) < MAX_TEMP - 5:
                                    break
                        if power > MAX_POWER:
                            print(f"  POWER WARN: {power}W > {MAX_POWER}W")

                    # Send commands via persistent ZMQ
                    ok1 = send_zmq_command("set_omega", omega)
                    ok2 = send_zmq_command("set_khra_amp", khra)
                    ok3 = send_zmq_command("set_gixx_amp", gixx)

                    if not (ok1 and ok2 and ok3):
                        fail_count += 1
                        print(f"  Command delivery failed ({fail_count} total failures)")
                        if fail_count > 10:
                            print("ERROR: Too many failures, aborting sweep")
                            break

                    # Wait for stabilization
                    time.sleep(STABILIZE_TIME)

                    # Get telemetry
                    telem = get_telemetry()
                    if telem:
                        writer.writerow([
                            datetime.now().isoformat(), omega, khra, gixx,
                            telem.get('coherence', 0),
                            telem.get('asymmetry', 0),
                            telem.get('vorticity_mean', 0),
                            telem.get('gpu_temp_c', 0),
                            telem.get('gpu_power_w', 0),
                            telem.get('cycle', 0)
                        ])
                        f.flush()
                        print(f"  OK Coh={telem.get('coherence', 0):.4f} "
                              f"T={telem.get('gpu_temp_c', 0)}C "
                              f"P={telem.get('gpu_power_w', 0)}W")
                    else:
                        print(f"  SKIP: no telemetry")

                    if point_count % 25 == 0:
                        print(f"\n*** Progress: {point_count}/{total_points} ***\n")
                else:
                    continue
                break
            else:
                continue
            break

    print("\n" + "=" * 60)
    print(f"Sweep complete! {point_count} points measured ({fail_count} failures)")
    print(f"Output: {output_file}")
    print("=" * 60)

    # Restore initial parameters
    print(f"\nRestoring: Ω={restore_omega} K={restore_khra} G={restore_gixx}")
    send_zmq_command("set_omega", restore_omega)
    send_zmq_command("set_khra_amp", restore_khra)
    send_zmq_command("set_gixx_amp", restore_gixx)
    print("Restored.")

if __name__ == "__main__":
    main()
