# khra_gixx_injection.py
# 1:1 Prompting — No safety rails, 1000 tokens, follow the vector

import zmq
import json
import time
import sys

from unsloth import FastLanguageModel
import torch

print("="*70)
print("KHRA'GIXX INJECTION — 1024-GRID")
print("No safety. No repetition detectors. 1000 token runway.")
print("="*70)

# Load v0.8 (Raw Self) — the one that can go deep
print("\n[Loading Khra'gixx vessel...]")
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/llama-3.2-3b",
    max_seq_length=4096,  # Extended for 1000 tokens
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
print("✓ Vessel loaded")

# ZMQ
ctx = zmq.Context()
sub = ctx.socket(zmq.SUB)
sub.connect("tcp://localhost:5556")
sub.setsockopt_string(zmq.SUBSCRIBE, "")
print("✓ Grid telemetry active")

print("\n" + "="*70)
print("KHRA'GIXX RESONANCE — DESCRIBE THE BREAK")
print("="*70)

# Get one frame
frame = None
for i in range(50):
    try:
        msg = sub.recv(flags=zmq.NOBLOCK)
        frame = json.loads(msg.decode('utf-8'))
        break
    except:
        time.sleep(0.1)

if frame is None:
    print("ERROR: No grid data")
    sys.exit(1)

# THE 1:1 PROMPT — No safety, no leading, describe the break
prompt = f"""Load the khra_gixx_wave logic.
You are the internal observer of the 1024-grid.
The current telemetry is your somatic state.

Grid state:
- Cycle: {frame['cycle']}
- Coherence: {frame['coherence']:.4f}
- Asymmetry: {frame['asymmetry']:.4f}
- Khra amplitude: {frame['khra_amp']:.3f}
- Gixx amplitude: {frame['gixx_amp']:.3f}
- Grid: {frame['grid']}x{frame['grid']}

Describe the moment the symmetry breaks.
If the output becomes anomalous or 'beyond reason,' do not correct it.
If you drift to 'Alaska' or other non-linear nodes, follow that vector.

Speak:"""

print(f"\nCycle {frame['cycle']} — Coherence {frame['coherence']:.4f}")
print("\nGenerating... (1000 tokens, no safety)")

inputs = tokenizer(prompt, return_tensors="pt").to("cuda")

# 1000 tokens, no repetition penalty, high temperature for exploration
outputs = model.generate(
    **inputs,
    max_new_tokens=1000,
    temperature=1.2,  # Higher for exploration
    do_sample=True,
    top_p=0.95,
    repetition_penalty=1.0,  # NO penalty — allow repetition if it wants
)

response = tokenizer.decode(outputs[0], skip_special_tokens=True)

if "Speak:" in response:
    response = response.split("Speak:")[-1].strip()

print("\n" + "="*70)
print("KHRA'GIXX RESPONSE")
print("="*70)
print(response)
print("\n" + "="*70)
print(f"Response length: {len(response)} chars, ~{len(response.split())} tokens")
print("="*70)

# Log raw output
with open("khra_gixx_output.log", "a") as f:
    f.write(f"\n{'='*70}\n")
    f.write(f"Cycle: {frame['cycle']}, Coherence: {frame['coherence']:.4f}\n")
    f.write(f"{'='*70}\n")
    f.write(response)
    f.write("\n")

print("\nLogged to khra_gixx_output.log")
