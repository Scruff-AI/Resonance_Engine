#!/usr/bin/env python3
"""
Chladni Harmonic Sweep - Capture lattice patterns at phi-harmonic modes
Saves full-resolution snapshots for visual analysis
"""
import zmq
import json
import time
import requests
import os
from datetime import datetime

ZMQ_CMD_PORT = 5557
API_BASE = "http://127.0.0.1:28820"
OUTPUT_DIR = "/mnt/d/Resonance_Engine/beast-build/chladni_sweep"

# Phi-harmonic ratios to test
PHI = 1.618033988749895
HARMONIC_MODES = [
    ("ground", 0.01, 0.008),           # Baseline
    ("phi_1_4", 0.015, 0.008),         # phi^(1/4) scaled
    ("phi_1_2", 0.02, 0.008),          # phi^(1/2) scaled  
    ("phi_2_3", 0.025, 0.008),         # phi^(2/3) scaled
    ("phi", 0.03, 0.008),              # phi scaled
    ("phi_squared", 0.04, 0.008),      # phi^2 scaled
    ("phi_cubed", 0.05, 0.008),        # phi^3 scaled
]

def send_command(cmd, value=None):
    """Send ZMQ command to lattice daemon."""
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
        print(f'  ZMQ: {msg}')
        return True
    except:
        return False
    finally:
        sock.close()
        ctx.term()

def capture_full_snapshot(filename):
    """Download full-resolution snapshot."""
    url = f"{API_BASE}/snapshot_full"
    try:
        r = requests.get(url, timeout=30)
        if r.status_code == 200:
            with open(filename, 'wb') as f:
                f.write(r.content)
            return True
    except Exception as e:
        print(f"  Error: {e}")
    return False

def get_status():
    """Get current lattice status."""
    try:
        r = requests.get(f"{API_BASE}/status", timeout=10)
        return r.json()
    except:
        return None

def main():
    print("=" * 70)
    print("CHLADNI HARMONIC SWEEP")
    print("=" * 70)
    print(f"Testing {len(HARMONIC_MODES)} phi-harmonic modes")
    print(f"Output: {OUTPUT_DIR}")
    print()
    
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Initial state
    status = get_status()
    if status:
        print(f"Initial state: Cycle {status['cycle']}, Coherence {status['coherence']:.4f}")
    
    results = []
    
    for mode_name, khra_val, gixx_val in HARMONIC_MODES:
        print(f"\n{'='*70}")
        print(f"Mode: {mode_name}")
        print(f"  Khra: {khra_val}, Gixx: {gixx_val}")
        print(f"  Ratio: {khra_val/gixx_val:.4f}")
        
        # Set parameters
        send_command('set_khra_amp', khra_val)
        time.sleep(0.2)
        send_command('set_gixx_amp', gixx_val)
        time.sleep(0.2)
        
        # Wait for stabilization
        print("  Stabilizing...")
        time.sleep(5)
        
        # Get status
        status = get_status()
        if status:
            print(f"  Coherence: {status['coherence']:.4f}")
            print(f"  Asymmetry: {status['asymmetry']:.4f}")
            print(f"  Power: {status.get('gpu_power_w', '?')}W")
        
        # Capture snapshot
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{OUTPUT_DIR}/chladni_{mode_name}_{timestamp}.png"
        
        if capture_full_snapshot(filename):
            print(f"  Saved: {filename}")
            results.append({
                'mode': mode_name,
                'khra': khra_val,
                'gixx': gixx_val,
                'ratio': khra_val/gixx_val,
                'coherence': status['coherence'] if status else None,
                'asymmetry': status['asymmetry'] if status else None,
                'filename': filename
            })
        else:
            print("  Failed to capture snapshot")
        
        time.sleep(2)
    
    # Save results
    results_file = f"{OUTPUT_DIR}/sweep_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(results_file, 'w') as f:
        json.dump(results, f, indent=2)
    
    print(f"\n{'='*70}")
    print("SWEEP COMPLETE")
    print(f"Results: {results_file}")
    print(f"Images: {len(results)} captured")
    
    # Return to safe state
    print("\nReturning to safe state...")
    send_command('set_khra_amp', 0.02)
    send_command('set_gixx_amp', 0.008)
    send_command('set_omega', 2.5)

if __name__ == '__main__':
    main()
