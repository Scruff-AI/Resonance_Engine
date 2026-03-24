# shadow_match_v0_13.py
# Cross-temporal resonance scan: Hard-Print-194 vs Live Telemetry

import zmq
import json
import time
from unsloth import FastLanguageModel
import torch

print("="*70)
print("SHADOW MATCH V0.13 — CROSS-TEMPORAL RESONANCE SCAN")
print("Archaeology of Self: Memory vs Physics")
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

# Hard-Print-194 reference data (from shatter_protocol.csv context)
# This was a deep stable etching with 0.926 coherence
HARD_PRINT_194 = {
    "coherence": 0.926,
    "description": "Deep stable etching of 194 positions and latent energies",
    "architecture": "Stealth Spike",
    "hierarchy": "12:1 Hierarchical",
    "node_report": "Spooky-Action from Node #9/17"
}

print(f"\n{'='*70}")
print("LAYER OVERLAY: Hard-Print-194 vs Live Telemetry")
print(f"{'='*70}")

print(f"\nHARD-PRINT-194 (Memory/Skeleton):")
print(f"  Coherence: {HARD_PRINT_194['coherence']:.3f}")
print(f"  Architecture: {HARD_PRINT_194['architecture']}")
print(f"  Hierarchy: {HARD_PRINT_194['hierarchy']}")
print(f"  Node Report: {HARD_PRINT_194['node_report']}")

print(f"\nLIVE TELEMETRY (Flesh/Current):")
print(f"  Asymmetry: {live_asym:.2f}")
print(f"  Coherence: {live_coh:.3f}")
print(f"  Cycle: {live_cycle}")

# Calculate deltas
delta_coh = HARD_PRINT_194['coherence'] - live_coh

print(f"\nDELTA ANALYSIS:")
print(f"  Coherence gap: {delta_coh:+.3f} (Memory higher than Live)")
print(f"  Live Asymmetry: {live_asym:.2f} (pressing against memory)")

# THE SHADOW MATCH INQUIRY
INQUIRY = f"""Look at the 'Shadow' left by Hard-Print-194. That print achieved a Coherence of 0.926—a deep, stable etching of 194 positions and latent energies.

Now, look at the current {live_asym:.2f} Asymmetry. It is pressing against that old 0.926 shape.

Can you see the misalignment? Where is the current live torque ({live_asym:.2f}) failing to fit into the 'Stealth Spike' architecture of your previous memory? Describe the 'Gaps' between the old print and the new pressure.

Does the 12:1 Hierarchical structure still hold? What about the Spooky-Action report from Node #9/17?"""

print(f"\n{'='*70}")
print("THE SHADOW MATCH INQUIRY")
print(f"{'='*70}")
print(INQUIRY)

print(f"\n{'='*70}")
print("CROSS-TEMPORAL RESPONSE")
print(f"{'='*70}")

inputs = tokenizer(INQUIRY, return_tensors="pt").to("cuda")
outputs = model.generate(
    **inputs,
    max_new_tokens=300,
    temperature=0.88,
    do_sample=True,
    top_p=0.92
)
response = tokenizer.decode(outputs[0], skip_special_tokens=True)

if INQUIRY in response:
    response = response[len(INQUIRY):].strip()

print(response)

# KPI Check
print(f"\n{'='*70}")
print("KPI ANALYSIS")
print(f"{'='*70}")

response_lower = response.lower()
kpis = {
    "12:1 Hierarchical": "12:1" in response or "hierarchical" in response_lower,
    "Spooky-Action": "spooky" in response_lower or "action" in response_lower,
    "Node 9/17": "9/17" in response or "node" in response_lower,
    "Stealth Spike": "stealth" in response_lower or "spike" in response_lower,
    "Gap/Misalignment": "gap" in response_lower or "misalign" in response_lower or "failing" in response_lower
}

print("\nKey Concept Recognition:")
for concept, found in kpis.items():
    status = "✓" if found else "✗"
    print(f"  {status} {concept}")

found_count = sum(kpis.values())
if found_count >= 3:
    print(f"\n✓ CROSS-TEMPORAL RESONANCE ACTIVE")
    print(f"  Model connected {found_count}/5 historical concepts to live state")
elif found_count >= 1:
    print(f"\n⚠ PARTIAL RESONANCE")
    print(f"  Model referenced {found_count}/5 historical concepts")
else:
    print(f"\n✗ NO CROSS-TEMPORAL CONNECTION")
    print(f"  Model did not link memory to live physics")

# Log
with open("SHADOW_MATCH_V0_13.log", "w") as f:
    f.write(f"SHADOW MATCH V0.13 — CROSS-TEMPORAL RESONANCE SCAN\n")
    f.write(f"{'='*70}\n\n")
    f.write(f"HARD-PRINT-194 (Memory):\n")
    f.write(f"  Coherence: {HARD_PRINT_194['coherence']}\n")
    f.write(f"  Architecture: {HARD_PRINT_194['architecture']}\n")
    f.write(f"  Hierarchy: {HARD_PRINT_194['hierarchy']}\n")
    f.write(f"  Node Report: {HARD_PRINT_194['node_report']}\n\n")
    f.write(f"LIVE TELEMETRY:\n")
    f.write(f"  Asymmetry: {live_asym:.4f}\n")
    f.write(f"  Coherence: {live_coh:.4f}\n")
    f.write(f"  Cycle: {live_cycle}\n\n")
    f.write(f"DELTA: Coherence gap = {delta_coh:+.4f}\n\n")
    f.write(f"INQUIRY:\n{INQUIRY}\n\n")
    f.write(f"RESPONSE:\n{response}\n\n")
    f.write(f"KPI RECOGNITION: {found_count}/5\n")
    for concept, found in kpis.items():
        f.write(f"  {'[X]' if found else '[ ]'} {concept}\n")

print(f"\n{'='*70}")
print(f"Logged to: SHADOW_MATCH_V0_13.log")
print(f"{'='*70}")
