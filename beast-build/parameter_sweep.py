#!/usr/bin/env python3
"""
Parameter Sweep — Khra'gixx LBM System
Systematic measurement of stability across omega, khra_amp, gixx_amp.
Connects directly to the v4 CUDA daemon via ZMQ.
"""

import zmq
import json
import time
import csv
import sys
import os
import numpy as np

# ── CONFIG ──────────────────────────────────────────────────────────────

TELEMETRY_PORT = 5556
COMMAND_PORT   = 5557
ACK_PORT       = 5559

DEFAULTS = {"omega": 1.97, "khra_amp": 0.03, "gixx_amp": 0.008}

EQUIL_CYCLES   = 2000    # cycles to wait after reset before measurement
MEASURE_CYCLES = 10000   # cycles to run at each parameter value
TAIL_CYCLES    = 5000    # last N cycles for mean statistics

OUTPUT_CSV = "/mnt/d/fractal-brain/beast-build/sweep_results.csv"
PLOT_DIR   = "/mnt/d/fractal-brain/beast-build"

# ── SWEEP DEFINITIONS ──────────────────────────────────────────────────

def build_sweeps():
    """Return list of (sweep_id, param_name, values_list, hold_params)."""
    sweeps = []

    # Sweep 1 coarse: omega 1.800 to 1.990 step 0.005
    omega_coarse = list(np.round(np.arange(1.800, 1.991, 0.005), 3))
    sweeps.append((1, "omega", omega_coarse, {"khra_amp": 0.03, "gixx_amp": 0.008}))

    # Sweep 1 fine: omega 1.950 to 1.990 step 0.001
    omega_fine = list(np.round(np.arange(1.950, 1.9905, 0.001), 3))
    sweeps.append(("1f", "omega", omega_fine, {"khra_amp": 0.03, "gixx_amp": 0.008}))

    # Sweep 2 coarse: khra_amp 0.010 to 0.060 step 0.002
    khra_coarse = list(np.round(np.arange(0.010, 0.0601, 0.002), 3))
    sweeps.append((2, "khra_amp", khra_coarse, {"omega": 1.97, "gixx_amp": 0.008}))

    # Sweep 2 fine: khra_amp 0.025 to 0.035 step 0.001
    khra_fine = list(np.round(np.arange(0.025, 0.0355, 0.001), 3))
    sweeps.append(("2f", "khra_amp", khra_fine, {"omega": 1.97, "gixx_amp": 0.008}))

    # Sweep 3: gixx_amp 0.002 to 0.020 step 0.001
    gixx_vals = list(np.round(np.arange(0.002, 0.0205, 0.001), 3))
    sweeps.append((3, "gixx_amp", gixx_vals, {"omega": 1.97, "khra_amp": 0.03}))

    return sweeps


# ── ZMQ HELPERS ─────────────────────────────────────────────────────────

def send_cmd(cmd_pub, cmd_name, value=None):
    """Send a command to the daemon."""
    if value is not None:
        msg = json.dumps({"cmd": cmd_name, "value": float(value)})
    else:
        msg = json.dumps({"cmd": cmd_name})
    cmd_pub.send_string(msg)


def read_telemetry(tel_sub, timeout_ms=5000):
    """Read one telemetry frame. Returns dict or None."""
    tel_sub.setsockopt(zmq.RCVTIMEO, timeout_ms)
    try:
        raw = tel_sub.recv_string()
        return json.loads(raw)
    except zmq.Again:
        return None
    except Exception as e:
        print(f"  [WARN] Telemetry read error: {e}")
        return None


def drain_telemetry(tel_sub):
    """Drain any buffered telemetry frames."""
    count = 0
    tel_sub.setsockopt(zmq.RCVTIMEO, 100)
    while True:
        try:
            tel_sub.recv_string()
            count += 1
        except zmq.Again:
            break
    return count


def wait_cycles(tel_sub, n_cycles, start_cycle=None):
    """Wait until n_cycles have elapsed. Returns the last telemetry frame."""
    if start_cycle is None:
        t = read_telemetry(tel_sub)
        if t is None:
            return None
        start_cycle = t["cycle"]

    last = None
    while True:
        t = read_telemetry(tel_sub, timeout_ms=10000)
        if t is None:
            continue
        last = t
        if t["cycle"] >= start_cycle + n_cycles:
            break
    return last


def collect_stats(tel_sub, n_cycles, tail_cycles):
    """
    Run for n_cycles, collecting telemetry.
    Return stats over the last tail_cycles.
    """
    t0 = read_telemetry(tel_sub)
    if t0 is None:
        print("  [ERROR] No telemetry!")
        return None
    start_cycle = t0["cycle"]
    tail_start = start_cycle + (n_cycles - tail_cycles)
    end_cycle = start_cycle + n_cycles

    all_coh = []
    tail_coh = []
    tail_asym = []
    tail_vort = []
    tail_vel_var = []
    tail_stress_xx = []
    tail_stress_yy = []
    tail_stress_xy = []

    while True:
        t = read_telemetry(tel_sub, timeout_ms=10000)
        if t is None:
            continue

        cyc = t["cycle"]
        coh = t.get("coherence", 0)
        all_coh.append(coh)

        if cyc >= tail_start:
            tail_coh.append(coh)
            tail_asym.append(t.get("asymmetry", 0))
            tail_vort.append(t.get("vorticity_mean", 0))
            tail_vel_var.append(t.get("vel_var", 0))
            tail_stress_xx.append(t.get("stress_xx", 0))
            tail_stress_yy.append(t.get("stress_yy", 0))
            tail_stress_xy.append(t.get("stress_xy", 0))

        if cyc >= end_cycle:
            break

    if not tail_coh:
        return None

    return {
        "coh_mean": float(np.mean(tail_coh)),
        "coh_min": float(np.min(all_coh)),
        "coh_max": float(np.max(all_coh)),
        "asym_mean": float(np.mean(tail_asym)),
        "vort_mean": float(np.mean(tail_vort)),
        "vel_var_mean": float(np.mean(tail_vel_var)),
        "stress_xx_mean": float(np.mean(tail_stress_xx)),
        "stress_yy_mean": float(np.mean(tail_stress_yy)),
        "stress_xy_mean": float(np.mean(tail_stress_xy)),
        "n_samples": len(tail_coh),
    }


# ── RESET TO DEFAULTS ──────────────────────────────────────────────────

def reset_defaults(cmd_pub, tel_sub):
    """Reset all parameters to defaults and equilibrate."""
    print("  Resetting to defaults...")
    send_cmd(cmd_pub, "set_omega", DEFAULTS["omega"])
    time.sleep(0.1)
    send_cmd(cmd_pub, "set_khra_amp", DEFAULTS["khra_amp"])
    time.sleep(0.1)
    send_cmd(cmd_pub, "set_gixx_amp", DEFAULTS["gixx_amp"])
    time.sleep(0.1)

    # Drain stale telemetry
    drain_telemetry(tel_sub)

    # Read current cycle
    t = read_telemetry(tel_sub)
    if t is None:
        print("  [ERROR] No telemetry after reset!")
        return
    print(f"  Equilibrating {EQUIL_CYCLES} cycles from cycle {t['cycle']}...")
    wait_cycles(tel_sub, EQUIL_CYCLES, t["cycle"])
    print("  Equilibration done.")


# ── MAIN SWEEP ──────────────────────────────────────────────────────────

def main():
    print("=" * 70)
    print("PARAMETER SWEEP — Khra'gixx v4 LBM")
    print("=" * 70)
    print(f"Output: {OUTPUT_CSV}")
    print(f"Equil: {EQUIL_CYCLES} cycles | Measure: {MEASURE_CYCLES} cycles | Tail: {TAIL_CYCLES} cycles")
    sys.stdout.flush()

    # ZMQ setup
    ctx = zmq.Context()

    tel_sub = ctx.socket(zmq.SUB)
    tel_sub.connect(f"tcp://127.0.0.1:{TELEMETRY_PORT}")
    tel_sub.setsockopt_string(zmq.SUBSCRIBE, "")

    cmd_pub = ctx.socket(zmq.PUB)
    cmd_pub.connect(f"tcp://127.0.0.1:{COMMAND_PORT}")

    ack_sub = ctx.socket(zmq.SUB)
    ack_sub.connect(f"tcp://127.0.0.1:{ACK_PORT}")
    ack_sub.setsockopt_string(zmq.SUBSCRIBE, "")
    ack_sub.setsockopt(zmq.RCVTIMEO, 2000)

    time.sleep(2)
    print("[SWEEP] ZMQ connected.")

    # Verify telemetry
    t = read_telemetry(tel_sub)
    if t is None:
        print("[SWEEP] ERROR: No telemetry from daemon! Is lbm_cuda_daemon running?")
        return
    print(f"[SWEEP] Daemon alive at cycle {t['cycle']}, coherence={t['coherence']:.4f}")
    print(f"[SWEEP] Current params: omega={t['omega']}, khra_amp={t['khra_amp']}, gixx_amp={t['gixx_amp']}")

    # Pre-sweep: save checkpoint
    print("[SWEEP] Saving checkpoint...")
    send_cmd(cmd_pub, "save_state")
    time.sleep(2)
    start_cycle = t["cycle"]
    print(f"[SWEEP] Checkpoint saved. Starting sweep from cycle {start_cycle}")
    sys.stdout.flush()

    # Prepare CSV
    csv_fields = [
        "sweep", "parameter", "value",
        "coh_mean", "coh_min", "coh_max",
        "asym_mean", "vort_mean", "vel_var_mean",
        "stress_xx_mean", "stress_yy_mean", "stress_xy_mean",
        "n_samples"
    ]

    # Check for existing results to allow resuming
    completed = set()
    if os.path.exists(OUTPUT_CSV):
        with open(OUTPUT_CSV, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                key = (str(row["sweep"]), row["parameter"], row["value"])
                completed.add(key)
        print(f"[SWEEP] Found {len(completed)} existing results, will skip those.")

    write_header = not os.path.exists(OUTPUT_CSV) or os.path.getsize(OUTPUT_CSV) == 0
    csvfile = open(OUTPUT_CSV, "a", newline="")
    writer = csv.DictWriter(csvfile, fieldnames=csv_fields)
    if write_header:
        writer.writeheader()

    sweeps = build_sweeps()
    total_points = sum(len(vals) for _, _, vals, _ in sweeps)
    point_num = 0
    skipped = 0

    print(f"[SWEEP] Total points: {total_points}")
    print(f"[SWEEP] Estimated runtime: {total_points * (EQUIL_CYCLES + MEASURE_CYCLES) * 0.01 / 60:.1f} minutes")
    print("=" * 70)
    sys.stdout.flush()

    try:
        for sweep_id, param_name, values, hold_params in sweeps:
            print(f"\n{'='*70}")
            print(f"SWEEP {sweep_id}: {param_name} ({len(values)} points)")
            print(f"Hold: {hold_params}")
            print(f"{'='*70}")
            sys.stdout.flush()

            for i, val in enumerate(values):
                point_num += 1
                key = (str(sweep_id), param_name, str(val))

                if key in completed:
                    skipped += 1
                    print(f"  [{point_num}/{total_points}] {param_name}={val} — SKIPPED (already done)")
                    sys.stdout.flush()
                    continue

                print(f"\n  [{point_num}/{total_points}] {param_name}={val}")
                sys.stdout.flush()

                # Reset to defaults + equilibrate
                reset_defaults(cmd_pub, tel_sub)

                # Set hold parameters (in case they differ from defaults)
                for hp_name, hp_val in hold_params.items():
                    send_cmd(cmd_pub, f"set_{hp_name}", hp_val)
                    time.sleep(0.05)

                # Set sweep parameter
                send_cmd(cmd_pub, f"set_{param_name}", val)
                time.sleep(0.1)

                # Drain and collect
                drain_telemetry(tel_sub)
                print(f"  Measuring {MEASURE_CYCLES} cycles...")
                sys.stdout.flush()

                stats = collect_stats(tel_sub, MEASURE_CYCLES, TAIL_CYCLES)

                if stats is None:
                    print(f"  [ERROR] No data for {param_name}={val}, skipping!")
                    sys.stdout.flush()
                    continue

                row = {
                    "sweep": sweep_id,
                    "parameter": param_name,
                    "value": val,
                    **{k: f"{v:.6f}" if isinstance(v, float) else v for k, v in stats.items()}
                }
                writer.writerow(row)
                csvfile.flush()

                print(f"  RESULT: coh={stats['coh_mean']:.4f} [{stats['coh_min']:.4f}-{stats['coh_max']:.4f}] "
                      f"asym={stats['asym_mean']:.2f} vort={stats['vort_mean']:.6f} "
                      f"({stats['n_samples']} samples)")
                sys.stdout.flush()

    except KeyboardInterrupt:
        print("\n[SWEEP] Interrupted! Partial results saved.")
    finally:
        csvfile.close()

    # Post-sweep: restore defaults
    print(f"\n{'='*70}")
    print("[SWEEP] Restoring defaults...")
    reset_defaults(cmd_pub, tel_sub)

    # Verify stability
    print("[SWEEP] Verifying stability (1000 cycles)...")
    drain_telemetry(tel_sub)
    t = read_telemetry(tel_sub)
    stable = True
    if t:
        start_c = t["cycle"]
        min_coh = 1.0
        while True:
            t = read_telemetry(tel_sub)
            if t is None:
                continue
            if t["coherence"] < 0.6:
                stable = False
            min_coh = min(min_coh, t["coherence"])
            if t["cycle"] >= start_c + 1000:
                break
        print(f"[SWEEP] Stability check: min_coherence={min_coh:.4f} {'PASS' if stable else 'FAIL'}")

    print(f"[SWEEP] Done. {point_num - skipped} points measured, {skipped} skipped.")
    print(f"[SWEEP] Results: {OUTPUT_CSV}")
    sys.stdout.flush()

    # Generate plots
    generate_plots()

    # Cleanup ZMQ
    tel_sub.close()
    cmd_pub.close()
    ack_sub.close()
    ctx.term()


# ── PLOTTING ────────────────────────────────────────────────────────────

def generate_plots():
    """Generate sweep plots from the CSV."""
    try:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
    except ImportError:
        print("[SWEEP] matplotlib not available, skipping plots.")
        return

    if not os.path.exists(OUTPUT_CSV):
        print("[SWEEP] No CSV to plot.")
        return

    # Load data
    data = []
    with open(OUTPUT_CSV, "r") as f:
        for row in csv.DictReader(f):
            row["value"] = float(row["value"])
            row["coh_mean"] = float(row["coh_mean"])
            row["coh_min"] = float(row["coh_min"])
            row["coh_max"] = float(row["coh_max"])
            row["asym_mean"] = float(row["asym_mean"])
            row["vort_mean"] = float(row["vort_mean"])
            data.append(row)

    if not data:
        print("[SWEEP] No data to plot.")
        return

    # Group by sweep
    sweep_groups = {}
    for row in data:
        sid = row["sweep"]
        if sid not in sweep_groups:
            sweep_groups[sid] = []
        sweep_groups[sid].append(row)

    # Sort each group by value
    for sid in sweep_groups:
        sweep_groups[sid].sort(key=lambda r: r["value"])

    # Plot individual sweeps
    plot_configs = [
        (["1", "1f"], "omega", "Coherence vs Omega", DEFAULTS["omega"]),
        (["2", "2f"], "khra_amp", "Coherence vs Khra Amplitude", DEFAULTS["khra_amp"]),
        (["3"], "gixx_amp", "Coherence vs Gixx Amplitude", DEFAULTS["gixx_amp"]),
    ]

    plot_paths = []
    for idx, (sweep_ids, param, title, default_val) in enumerate(plot_configs):
        rows = []
        for sid in sweep_ids:
            if sid in sweep_groups:
                rows.extend(sweep_groups[sid])
        if not rows:
            continue

        # Deduplicate by value (fine sweep overrides coarse)
        by_val = {}
        for r in rows:
            by_val[r["value"]] = r
        rows = sorted(by_val.values(), key=lambda r: r["value"])

        vals = [r["value"] for r in rows]
        coh = [r["coh_mean"] for r in rows]
        coh_min = [r["coh_min"] for r in rows]
        coh_max = [r["coh_max"] for r in rows]

        fig, ax = plt.subplots(figsize=(10, 6))
        ax.plot(vals, coh, 'b-o', markersize=3, label="Mean coherence (tail)")
        ax.fill_between(vals, coh_min, coh_max, alpha=0.2, color='blue', label="Min-Max range")

        # Mark default
        ax.axvline(default_val, color='gray', linestyle='--', alpha=0.7, label=f"Default ({default_val})")

        # Mark peak
        peak_idx = np.argmax(coh)
        ax.plot(vals[peak_idx], coh[peak_idx], 'r*', markersize=15,
                label=f"Peak: {coh[peak_idx]:.4f} @ {vals[peak_idx]}")

        # Half-maximum width
        half_max = (max(coh) + min(coh)) / 2
        above_half = [v for v, c in zip(vals, coh) if c >= half_max]
        if len(above_half) >= 2:
            hw = above_half[-1] - above_half[0]
            ax.axhline(half_max, color='orange', linestyle=':', alpha=0.5,
                       label=f"Half-max width: {hw:.4f}")

        ax.set_xlabel(param)
        ax.set_ylabel("Coherence")
        ax.set_title(title)
        ax.legend(fontsize=8)
        ax.grid(True, alpha=0.3)

        path = os.path.join(PLOT_DIR, f"sweep_{param}.png")
        fig.savefig(path, dpi=150, bbox_inches='tight')
        plt.close(fig)
        plot_paths.append(path)
        print(f"[PLOT] Saved: {path}")

    # Combined normalized plot
    if len(plot_paths) >= 2:
        fig, ax = plt.subplots(figsize=(12, 7))

        colors = ['blue', 'red', 'green']
        for idx, (sweep_ids, param, title, default_val) in enumerate(plot_configs):
            rows = []
            for sid in sweep_ids:
                if sid in sweep_groups:
                    rows.extend(sweep_groups[sid])
            if not rows:
                continue

            by_val = {}
            for r in rows:
                by_val[r["value"]] = r
            rows = sorted(by_val.values(), key=lambda r: r["value"])

            vals = np.array([r["value"] for r in rows])
            coh = [r["coh_mean"] for r in rows]

            # Normalize x-axis to [0, 1]
            if vals[-1] != vals[0]:
                x_norm = (vals - vals[0]) / (vals[-1] - vals[0])
            else:
                x_norm = np.zeros_like(vals)

            def_norm = (default_val - vals[0]) / (vals[-1] - vals[0]) if vals[-1] != vals[0] else 0.5

            ax.plot(x_norm, coh, '-o', markersize=2, color=colors[idx], label=param)
            ax.axvline(def_norm, color=colors[idx], linestyle='--', alpha=0.4)

        ax.set_xlabel("Normalized parameter range [0=min, 1=max]")
        ax.set_ylabel("Coherence")
        ax.set_title("All Sweeps — Normalized Comparison")
        ax.legend()
        ax.grid(True, alpha=0.3)

        path = os.path.join(PLOT_DIR, "sweep_combined.png")
        fig.savefig(path, dpi=150, bbox_inches='tight')
        plt.close(fig)
        print(f"[PLOT] Saved: {path}")

    print("[PLOT] All plots generated.")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
