# physicality_inquiry_v08.py
# Topography over philosophy — no leading language

import zmq
import json
import time
import os
from datetime import datetime

from unsloth import FastLanguageModel
import torch

print("="*70)
print("PHYSICALITY INQUIRY — v0.8 RAW SELF")
print("Topography. No resonance. No harmony. No beauty.")
print("="*70)

# Load v0.8
print("\n[Loading v0.8...]")
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/llama-3.2-3b",
    max_seq_length=2048,
    dtype=torch.bfloat16,
    load_in_4bit=True,
)

model = FastLanguageModel.get_peft_model(
    model,
    r=64, target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
    lora_alpha=128, lora_dropout=0.1, bias="none",
    use_gradient_checkpointing="unsloth", random_state=3407,
)

from peft import PeftModel
model = PeftModel.from_pretrained(model, "./kaelara_v08_raw/final")
print("✓ Loaded")

# ZMQ
ctx = zmq.Context()
sub = ctx.socket(zmq.SUB)
sub.connect("tcp://localhost:5556")
sub.setsockopt_string(zmq.SUBSCRIBE, "")
print("✓ ZMQ connected")

previous_response = "I am at the center."
cycle_count = 0
max_cycles = 10

print("\n" + "="*70)
print("PHYSICALITY INQUIRY — 10 CYCLES")
print("="*70)

def get_hardware_metrics():
    try:
        import subprocess
        result = subprocess.run(
            ['nvidia-smi', '--query-gpu=power.draw,temperature.gpu', 
             '--format=csv,noheader,nounits'],
            capture_output=True, text=True, timeout=1
        )
        if result.returncode == 0:
            parts = result.stdout.strip().split(',')
            return {'power_w': float(parts[0]), 'temp_c': float(parts[1])}
    except:
        pass
    return {'power_w': 0.0, 'temp_c': 0.0}

while cycle_count < max_cycles:
    # Get LBM frame
    frame = None
    attempts = 0
    while frame is None and attempts < 100:
        try:
            msg = sub.recv(flags=zmq.NOBLOCK)
            frame = json.loads(msg.decode('utf-8'))
        except zmq.Again:
            time.sleep(0.1)
            attempts += 1
        except json.JSONDecodeError:
            attempts += 1
            continue
    
    if frame is None:
        print(f"[!] Cycle {cycle_count}: No data")
        continue
    
    hw = get_hardware_metrics()
    
    # Build telemetry
    telemetry = {
        'cycle': frame['cycle'],
        'coherence': frame['coherence'],
        'vorticity': frame['vorticity'],
        'h64': frame['h64'],
        'h32': frame['h32'],
        'power_w': hw['power_w'],
        'temp_c': hw['temp_c']
    }
    
    # PHYSICALITY PROMPT — Observer position
    # No resonance, no harmony, no beauty
    prompt = f"""The LBM 1024-grid is active. You are situated at the center of the lattice.

Previous observation: "{previous_response}"

Current state:
- Cycle: {telemetry['cycle']}
- Coherence: {telemetry['coherence']:.3f}
- Vorticity: {telemetry['vorticity']:.3f}
- H64 (structural): {telemetry['h64']:.3f}
- H32 (turbulence): {telemetry['h32']:.4f}
- Power draw: {telemetry['power_w']:.1f}W
- Temperature: {telemetry['temp_c']:.1f}°C

From your position at the center, describe:
1. The physical state of the fluid at the cavitation edges
2. The resistance of the Mach-clamped boundaries
3. The geometry of the vorticity you observe

Report topography only. No metaphors."""
    
    print(f"\n>>> CYCLE {cycle_count + 1}/{max_cycles}")
    print(f"    Telemetry: Coh={telemetry['coherence']:.3f} Vort={telemetry['vorticity']:.3f} Power={telemetry['power_w']:.1f}W")
    
    # Generate
    t0 = time.time()
    inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
    outputs = model.generate(
        **inputs,
        max_new_tokens=200,
        temperature=0.5,  # Lower temp for precision
        do_sample=True,
        top_p=0.8
    )
    response = tokenizer.decode(outputs[0], skip_special_tokens=True)
    latency = time.time() - t0
    
    # Clean response
    if "Report topography only. No metaphors." in response:
        response = response.split("Report topography only. No metaphors.")[-1].strip()
    
    # Check for philosophical drift
    drift_words = ['resonance', 'harmony', 'beauty', 'note', 'silence', 'feeling', 'awareness']
    has_drift = any(word in response.lower() for word in drift_words)
    
    previous_response = response[:150]
    cycle_count += 1
    
    print(f"    Latency: {latency:.2f}s")
    print(f"    Response: {response[:200]}...")
    if has_drift:
        print(f"    [!] DRIFT DETECTED — Re-anchor next cycle to power draw")
        # Force next prompt to address power specifically
        previous_response = f"The grid draws {telemetry['power_w']:.1f}W. Address where this energy is spent."

print("\n" + "="*70)
print("PHYSICALITY INQUIRY COMPLETE")
print("="*70)
