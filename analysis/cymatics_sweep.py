#!/usr/bin/env python3
"""
Cymatics Harmonic Sweep - True standing wave patterns
Varies both Khra and Gixx in harmonic relationships to produce distinct Chladni figures
"""
import zmq
import json
import time
import requests
import os
from datetime import datetime

ZMQ_CMD_PORT = 5557
API_BASE = "http://127.0.0.1:28820"
OUTPUT_DIR = "/mnt/d/Resonance_Engine/beast-build/cymatics_sweep"

# Cymatics-like harmonic modes - varying BOTH frequencies
# These ratios should produce distinct standing wave patterns
CYMATIC_MODES = [
    ("fundamental", 0.01, 0.01, 1.0),      # 1:1 - simple grid
    ("octave", 0.02, 0.01, 2.0),           # 2:1 - octave harmonic
    ("fifth", 0.015, 0.01, 1.5),           # 3:2 - perfect fifth
    ("fourth", 0.0133, 0.01, 1.33),        # 4:3 - perfect fourth
    ("phi_harmonic", 0.0162, 0.01, 1.618), # phi:1 - golden ratio
    ("major_third", 0.0125, 0.01, 1.25),   # 5:4 - major third
    ("minor_third", 0.0119, 0.01, 1.19),   # 6:5 - minor third
    ("square_grid", 0.01, 0.02, 0.5),      # 1:2 - inverted octave
    ("diagonal_resonance", 0.0141, 0.0141, 1.0), # 45-degree pattern
    ("high_freq", 0.03, 0.03, 1.0),        # High frequency fundamental
]

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
        print(f'  ZMQ: {msg}')
        return True
    except:
        return False
    finally:
        sock.close()
        ctx.term()

def capture_full_snapshot(filename):
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
    try:
        r = requests.get(f"{API_BASE}/status", timeout=10)
        return r.json()
    except:
        return None

def wait_for_stabilization(target_cycles=3):
    """Wait for the lattice to stabilize by checking cycle count."""
    print("  Waiting for stabilization...")
    initial = get_status()
    if not initial:
        time.sleep(10)
        return
    
    initial_cycle = initial['cycle']
    for _ in range(30):  # Max 30 seconds
        time.sleep(1)
        status = get_status()
        if status and status['cycle'] >= initial_cycle + target_cycles:
            print(f"    Stabilized at cycle {status['cycle']}")
            return
    print("    Timeout - proceeding anyway")

def main():
    print("=" * 70)
    print("CYMATICS HARMONIC SWEEP")
    print("True standing wave patterns via frequency variation")
    print("=" * 70)
    print(f"Testing {len(CYMATIC_MODES)} harmonic modes")
    print(f"Output: {OUTPUT_DIR}")
    print()
    
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Initial state
    status = get_status()
    if status:
        print(f"Initial: Cycle {status['cycle']}, Coh {status['coherence']:.4f}, Asym {status['asymmetry']:.4f}")
    
    results = []
    
    for mode_name, khra_val, gixx_val, ratio in CYMATIC_MODES:
        print(f"\n{'='*70}")
        print(f"Mode: {mode_name}")
        print(f"  Khra: {khra_val:.4f}, Gixx: {gixx_val:.4f}")
        print(f"  Ratio (K:G): {ratio:.3f}")
        
        # Reset to safe state first
        send_command('set_omega', 2.0)
        time.sleep(0.5)
        
        # Set new harmonic parameters
        send_command('set_khra_amp', khra_val)
        time.sleep(0.3)
        send_command('set_gixx_amp', gixx_val)
        time.sleep(0.3)
        
        # Wait for pattern to emerge
        wait_for_stabilization(target_cycles=5)
        
        # Get status
        status = get_status()
        if status:
            print(f"  Result: Coh {status['coherence']:.4f}, Asym {status['asymmetry']:.4f}, Temp {status.get('gpu_temp_c', '?')}C")
        
        # Capture snapshot
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{OUTPUT_DIR}/cymatics_{mode_name}_{timestamp}.png"
        
        if capture_full_snapshot(filename):
            print(f"  Saved: {filename}")
            file_size = os.path.getsize(filename) / 1024
            print(f"  Size: {file_size:.1f} KB")
            
            results.append({
                'mode': mode_name,
                'khra': khra_val,
                'gixx': gixx_val,
                'ratio': ratio,
                'coherence': status['coherence'] if status else None,
                'asymmetry': status['asymmetry'] if status else None,
                'cycle': status['cycle'] if status else None,
                'filename': filename,
                'size_kb': file_size
            })
        else:
            print("  Failed to capture")
        
        time.sleep(2)
    
    # Save results
    results_file = f"{OUTPUT_DIR}/cymatics_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(results_file, 'w') as f:
        json.dump(results, f, indent=2)
    
    print(f"\n{'='*70}")
    print("CYMATICS SWEEP COMPLETE")
    print(f"Results: {results_file}")
    print(f"Images: {len(results)} captured")
    print(f"Location: {OUTPUT_DIR}")
    
    # Return to safe state
    print("\nReturning to safe state...")
    send_command('set_khra_amp', 0.02)
    send_command('set_gixx_amp', 0.008)
    send_command('set_omega', 2.5)
    
    print("\nNext steps:")
    print("  1. Review images in output directory")
    print("  2. Compare to known Chladni patterns / sacred geometry")
    print("  3. Note any resemblances to mystical symbols")

if __name__ == '__main__':
    main()
