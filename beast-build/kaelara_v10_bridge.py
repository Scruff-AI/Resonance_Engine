# kaelara_v10_bridge.py
# v0.10 Inference Bridge with Incoherence Gate

import zmq
import json
import time
import subprocess

from unsloth import FastLanguageModel
import torch

def get_gpu_metrics():
    try:
        result = subprocess.run(
            ['nvidia-smi', '--query-gpu=temperature.gpu,power.draw',
             '--format=csv,noheader,nounits'],
            capture_output=True, text=True, timeout=2
        )
        if result.returncode == 0:
            parts = result.stdout.strip().split(',')
            return {'temp_c': float(parts[0]), 'power_w': float(parts[1])}
    except:
        pass
    return {'temp_c': 45.0, 'power_w': 50.0}

def is_echo(response, prompt, threshold=0.8):
    """Incoherence Gate: Check if response is >80% echo of prompt"""
    response_clean = response.strip().lower()
    prompt_clean = prompt.strip().lower()
    
    if response_clean in prompt_clean:
        return True
    
    response_words = set(response_clean.split())
    prompt_words = set(prompt_clean.split())
    
    if len(response_words) == 0:
        return True
    
    overlap = len(response_words & prompt_words) / len(response_words)
    return overlap > threshold

print("="*70)
print("KAELARA v0.10 BRIDGE — SOMATIC INFERENCE")
print("Incoherence Gate Active | Echo Detection: 80% threshold")
print("="*70)

# Load v0.10
print("\n[Loading v0.10 Somatic...]")
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/llama-3.2-3b",
    max_seq_length=2048,
    dtype=torch.bfloat16,
    load_in_4bit=True,
)

model = FastLanguageModel.get_peft_model(
    model,
    r=128, target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
    lora_alpha=256, lora_dropout=0.05, bias="none",
    use_gradient_checkpointing="unsloth", random_state=3407,
)

from peft import PeftModel
model = PeftModel.from_pretrained(model, "./kaelara_v10_somatic/final")
print("✓ v0.10 Somatic manifesting")

# ZMQ
ctx = zmq.Context()
sub = ctx.socket(zmq.SUB)
sub.setsockopt_string(zmq.SUBSCRIBE, "")
sub.connect("tcp://127.0.0.1:5556")
print("✓ Bridge to Beast established")

print("\n" + "="*70)
print("AWAITING LIVE TELEMETRY")
print("="*70)

# Get live frame
frame = None
for i in range(50):
    try:
        msg = sub.recv(flags=zmq.NOBLOCK)
        frame = json.loads(msg.decode('utf-8'))
        print(f"Cycle {frame['cycle']}: Asym={frame['asymmetry']:.2f}, Coh={frame['coherence']:.3f}")
        break
    except zmq.Again:
        time.sleep(0.05)

if frame is None:
    print("ERROR: No telemetry")
    exit(1)

gpu = get_gpu_metrics()

# SOMATIC HANDSHAKE with Reasoning layer
base_prompt = f"""Kaelara. The bridge is open. Data is live.

Three Apples (Constants):
- NX=1024, NY=1024, Q=9
- d_w = [4/9, 1/9, 1/9, 1/9, 1/9, 1/36, 1/36, 1/36, 1/36]
- Khra'gixx: 128-cell at 0.03, 8-cell at 0.008

Current State:
- Cycle: {frame['cycle']}
- Asymmetry: {frame['asymmetry']:.2f}
- Coherence: {frame['coherence']:.3f}
- GPU: {gpu['temp_c']:.1f}°C

Reasoning:

Output:"""

print(f"\n{'='*70}")
print("SOMATIC HANDSHAKE")
print(f"{'='*70}")

temperature = 0.6
max_attempts = 3
response = None

for attempt in range(max_attempts):
    print(f"\n[Attempt {attempt+1}/{max_attempts}] T={temperature:.1f}")
    
    inputs = tokenizer(base_prompt, return_tensors="pt").to("cuda")
    outputs = model.generate(
        **inputs,
        max_new_tokens=150,
        temperature=temperature,
        do_sample=True,
        top_p=0.9
    )
    candidate = tokenizer.decode(outputs[0], skip_special_tokens=True)
    
    # Extract output part
    if "Output:" in candidate:
        candidate = candidate.split("Output:")[-1].strip()
    
    # Incoherence Gate
    if is_echo(candidate, base_prompt):
        print(f"    ⚠ ECHO DETECTED (overlap >80%)")
        temperature += 0.1
        continue
    else:
        response = candidate
        print(f"    ✓ PASSED Incoherence Gate")
        break

if response is None:
    response = "[INCOHERENCE_GATE_FAILED] All attempts echoed. Manual intervention required."

print(f"\n{'='*70}")
print("v0.10 SOMATIC RESPONSE")
print(f"{'='*70}")
print(response)

# Log
with open("KAELARA_v10_SOMATIC.log", "w") as f:
    f.write(f"Cycle: {frame['cycle']}\n")
    f.write(f"Asymmetry: {frame['asymmetry']:.4f}\n")
    f.write(f"Temperature: {temperature:.1f}\n")
    f.write(f"Attempts: {attempt+1}\n\n")
    f.write(f"RESPONSE:\n{response}\n")

print(f"\n{'='*70}")
print("LOGGED TO: KAELARA_v10_SOMATIC.log")
print(f"{'='*70}")
