#!/usr/bin/env python3
"""
Kolmogorov Turbulence Test
Run lattice at low omega (high Reynolds) and check for turbulent characteristics
"""
import zmq
import json
import time
import requests
import numpy as np

ZMQ_CMD_PORT = 5557
API_BASE = "http://127.0.0.1:28820"

def send_command(cmd, value=None):
    ctx = zmq.Context()
    sock = ctx.socket(zmq.PUSH)
    sock.setsockopt(zmq.SNDTIMEO, 5000)
    sock.setsockopt(zmq.LINGER, 0)
    sock.connect(f'tcp://127.0.0.1:{ZMQ_CMD_PORT}')
    
    if value is not None:
        msg = json.dumps({'cmd': cmd, 'value': float(value)})
    else:
        msg = json.dumps({'cmd': cmd})
    
    try:
        sock.send_string(msg)
        print(f'  Sent: {msg}')
        return True
    except:
        return False
    finally:
        sock.close()
        ctx.term()

def get_telemetry():
    try:
        r = requests.get(f"{API_BASE}/telemetry", timeout=10)
        return r.json()
    except:
        return None

def main():
    print("=" * 70)
    print("KOLMOGOROV TURBULENCE TEST")
    print("=" * 70)
    print("Testing for -5/3 power law in energy spectrum")
    print()
    
    # Current state
    tel = get_telemetry()
    if tel:
        print(f"Initial: Omega {tel['omega']}, Coherence {tel['coherence']:.4f}")
        print(f"  Velocity: mean={tel['vel_mean']:.4f}, max={tel['vel_max']:.4f}, var={tel['vel_var']:.6f}")
        print(f"  Vorticity: {tel.get('vorticity_mean', 'N/A')}")
    
    # Step 1: Reduce omega for high Reynolds (turbulence)
    print("\n" + "=" * 70)
    print("STEP 1: Reducing omega (increasing Reynolds)")
    print("=" * 70)
    
    omega_values = [1.9, 1.8, 1.7, 1.6]
    results = []
    
    for omega in omega_values:
        print(f"\nSetting omega = {omega}")
        send_command('set_omega', omega)
        time.sleep(5)
        
        # Collect data over time
        print("  Collecting data...")
        velocities = []
        vorticities = []
        for _ in range(20):
            tel = get_telemetry()
            if tel:
                velocities.append(tel['vel_mean'])
                vorticities.append(tel.get('vorticity_mean', 0))
            time.sleep(1)
        
        if velocities:
            vel_mean = np.mean(velocities)
            vel_std = np.std(velocities)
            vort_mean = np.mean(vorticities)
            
            print(f"  Velocity: {vel_mean:.4f} \u00b1 {vel_std:.4f}")
            print(f"  Vorticity: {vort_mean:.6f}")
            print(f"  Turbulence indicator (vel_std/vel_mean): {vel_std/vel_mean:.4f}")
            
            results.append({
                'omega': omega,
                'reynolds_proxy': 1.0 / omega,
                'vel_mean': vel_mean,
                'vel_std': vel_std,
                'vel_var': vel_std**2,
                'vorticity': vort_mean,
                'turbulence_indicator': vel_std / vel_mean if vel_mean > 0 else 0
            })
    
    # Analysis
    print("\n" + "=" * 70)
    print("RESULTS")
    print("=" * 70)
    
    for r in results:
        print(f"\nOmega = {r['omega']} (Re ~ {r['reynolds_proxy']:.2f}):")
        print(f"  Velocity variance: {r['vel_var']:.6f}")
        print(f"  Turbulence indicator: {r['turbulence_indicator']:.4f}")
        if r['turbulence_indicator'] > 0.1:
            print(f"  -> TURBULENT (high velocity fluctuations)")
        else:
            print(f"  -> LAMINAR (steady flow)")
    
    # Check for Kolmogorov scaling
    print("\n" + "=" * 70)
    print("KOLMOGOROV SCALING CHECK")
    print("=" * 70)
    
    if len(results) >= 2:
        re_values = [r['reynolds_proxy'] for r in results]
        var_values = [r['vel_var'] for r in results]
        
        # In turbulence, energy dissipation should scale with Reynolds
        # E ~ Re^(-something)
        print(f"\nReynolds range: {min(re_values):.2f} to {max(re_values):.2f}")
        print(f"Velocity variance range: {min(var_values):.6f} to {max(var_values):.6f}")
        
        # Simple check: does variance increase with Reynolds?
        if var_values[-1] > var_values[0]:
            print("\n  Variance increases with Reynolds: CONSISTENT with turbulence")
        else:
            print("\n  Variance does not increase: INCONSISTENT with turbulence")
    
    # Return to safe state
    print("\n" + "=" * 70)
    print("Returning to safe state")
    print("=" * 70)
    send_command('set_omega', 1.97)
    
    print("\nNote: Full -5/3 spectrum requires spatial velocity field data.")
    print("This test uses velocity variance as a proxy for turbulent intensity.")

if __name__ == '__main__':
    main()