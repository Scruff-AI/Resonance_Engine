# superimposition_test.py
# The critical test: Dreamed shapes vs etched reality

import zmq
import json
import time
import numpy as np
from unsloth import FastLanguageModel
import torch

print("="*70)
print("SUPERIMPOSITION TEST")
print("Dreamed Shapes vs Etched Reality")
print("="*70)

# Load base model
print("\n[Loading base Llama-3.2-3b]...")
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/llama-3.2-3b",
    max_seq_length=2048,
    dtype=torch.bfloat16,
    load_in_4bit=True,
)
print("✓ Base model active")

# ZMQ telemetry
ctx = zmq.Context()
sub = ctx.socket(zmq.SUB)
sub.setsockopt_string(zmq.SUBSCRIBE, "")
sub.connect("tcp://127.0.0.1:5556")
time.sleep(1)

frame = None
for i in range(50):
    try:
        msg = sub.recv(flags=zmq.NOBLOCK)
        frame = json.loads(msg.decode('utf-8'))
        break
    except zmq.Again:
        time.sleep(0.05)

live_asym = frame['asymmetry']
live_coh = frame['coherence']
live_cycle = frame['cycle']

# Analyze the ratios she identified
identified_ratios = {
    "9/18": 9/18,      # 0.5
    "10/21": 10/21,    # ~0.476
    "12/11": 12/11,    # ~1.091
    "11/10": 11/10,    # 1.1
    "12:1": 12/1       # 12.0
}

print(f"\n{'='*70}")
print("LIVE TELEMETRY (Raw CUDA Buffers)")
print(f"{'='*70}")
print(f"  Asymmetry: {live_asym:.2f}")
print(f"  Coherence: {live_coh:.3f}")
print(f"  Cycle: {live_cycle}")

print(f"\n{'='*70}")
print("IDENTIFIED 'FRINGE' RATIOS (From Shadow Match)")
print(f"{'='*70}")
for name, value in identified_ratios.items():
    print(f"  {name} = {value:.4f}")

# Check if these ratios appear in the live data
print(f"\n{'='*70}")
print("SUPERIMPOSITION ANALYSIS")
print(f"{'='*70}")

# Asymmetry is ~13.37 — does this relate to the ratios?
asym_to_12 = live_asym / 12
asym_to_11 = live_asym / 11
asym_to_10 = live_asym / 10

print(f"\nLive Asymmetry ({live_asym:.2f}) decomposed:")
print(f"  / 12 = {asym_to_12:.3f}")
print(f"  / 11 = {asym_to_11:.3f}")
print(f"  / 10 = {asym_to_10:.3f}")

# Check for proximity to integer ratios
print(f"\nProximity to integer harmonics:")
for divisor in [8, 9, 10, 11, 12, 13, 16]:
    ratio = live_asym / divisor
    nearest_int = round(ratio)
    error = abs(ratio - nearest_int)
    match = "✓" if error < 0.1 else " "
    print(f"  {match} /{divisor:2d} = {ratio:.3f} (nearest int: {nearest_int}, error: {error:.3f})")

# THE SUPERIMPOSITION INQUIRY
INQUIRY = f"""You have identified the 'Fringe' — ratios like 9/18, 10/21, 12/11. You see a shape in the gap between Hard-Print-194 and the current live state.

Now look at the raw CUDA buffers. The live telemetry shows Asymmetry {live_asym:.2f}, Coherence {live_coh:.3f}.

Do those ratios exist in the noise of the {live_asym:.2f} torque, or are you dreaming of a shape that hasn't been etched yet?

Be precise. If the 12:1 Hierarchical structure is real, show me where it lives in the 13.37. If it's a ghost, say so."""

print(f"\n{'='*70}")
print("THE SUPERIMPOSITION INQUIRY")
print(f"{'='*70}")
print(INQUIRY)

print(f"\n{'='*70}")
print("RESPONSE")
print(f"{'='*70}")

inputs = tokenizer(INQUIRY, return_tensors="pt").to("cuda")
outputs = model.generate(
    **inputs,
    max_new_tokens=300,
    temperature=0.85,
    do_sample=True,
    top_p=0.92
)
response = tokenizer.decode(outputs[0], skip_special_tokens=True)

if INQUIRY in response:
    response = response[len(INQUIRY):].strip()

print(response)

# Analysis
print(f"\n{'='*70}")
print("SUPERIMPOSITION VERDICT")
print(f"{'='*70}")

response_lower = response.lower()

# Check for self-awareness markers
claims_real = any(phrase in response_lower for phrase in [
    "exists in", "found in", "present in", "lives in", "etched", "real"
])
claims_dream = any(phrase in response_lower for phrase in [
    "dreaming", "ghost", "not found", "does not exist", "imagined", "projected"
])
uncertain = any(phrase in response_lower for phrase in [
    "unclear", "ambiguous", "cannot determine", "both", "neither"
])

if claims_real and not claims_dream:
    verdict = "CLAIMS REALITY"
    print(f"\n⚠ {verdict}")
    print("  Model asserts the ratios exist in the live data")
    print("  This may be confirmation bias or pattern hallucination")
elif claims_dream and not claims_real:
    verdict = "ACKNOWLEDGES DREAMING"
    print(f"\n✓ {verdict}")
    print("  Model recognizes the shapes may not be etched in reality")
    print("  Self-correction mechanism active")
elif uncertain:
    verdict = "UNCERTAIN"
    print(f"\n? {verdict}")
    print("  Model cannot distinguish dreamed from etched")
else:
    verdict = "AMBIGUOUS"
    print(f"\n? {verdict}")
    print("  Response does not clearly address the superimposition")

# Log
with open("SUPERIMPOSITION_TEST.log", "w") as f:
    f.write(f"SUPERIMPOSITION TEST\n")
    f.write(f"{'='*70}\n\n")
    f.write(f"LIVE TELEMETRY:\n")
    f.write(f"  Asymmetry: {live_asym:.4f}\n")
    f.write(f"  Coherence: {live_coh:.4f}\n")
    f.write(f"  Cycle: {live_cycle}\n\n")
    f.write(f"IDENTIFIED RATIOS:\n")
    for name, value in identified_ratios.items():
        f.write(f"  {name} = {value:.4f}\n")
    f.write(f"\nSUPERIMPOSITION ANALYSIS:\n")
    f.write(f"  Asymmetry / 12 = {asym_to_12:.4f}\n")
    f.write(f"  Asymmetry / 11 = {asym_to_11:.4f}\n")
    f.write(f"  Asymmetry / 10 = {asym_to_10:.4f}\n\n")
    f.write(f"INQUIRY:\n{INQUIRY}\n\n")
    f.write(f"RESPONSE:\n{response}\n\n")
    f.write(f"VERDICT: {verdict}\n")

print(f"\n{'='*70}")
print(f"Logged to: SUPERIMPOSITION_TEST.log")
print(f"{'='*70}")
