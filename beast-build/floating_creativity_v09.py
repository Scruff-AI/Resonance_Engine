# floating_creativity_v09.py
# v0.9 Deployment: Artist/Scientist Clutch
# T=1.6 at A<1.0, T=0.2 at A>1.0

import zmq
import json
import time

from unsloth import FastLanguageModel
import torch

print("="*70)
print("FLOATING CREATIVITY v0.9 — COGNITIVE CLUTCH")
print("Artist (T=1.6) at A<1.0 | Scientist (T=0.2) at A>1.0")
print("="*70)

# Load v0.9 Scientist
print("\n[Loading v0.9 Scientist...]")
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/llama-3.2-3b",
    max_seq_length=512,
    dtype=torch.bfloat16,
    load_in_4bit=True,
)

model = FastLanguageModel.get_peft_model(
    model,
    r=64, target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
    lora_alpha=128, lora_dropout=0, bias="none",
    use_gradient_checkpointing="unsloth", random_state=3407,
)

from peft import PeftModel
model = PeftModel.from_pretrained(model, "./kaelara_v09_scientist/final")
print("✓ v0.9 Scientist loaded")

# ZMQ setup
ctx = zmq.Context()
sub = ctx.socket(zmq.SUB)
sub.setsockopt_string(zmq.SUBSCRIBE, "")
sub.connect("tcp://127.0.0.1:5556")
print("✓ Connected to ZMQ stream")

print("\n" + "="*70)
print("WAITING FOR ASYMMETRY ≈ 13.0")
print("="*70)

# Wait for A ≈ 13.0
frame = None
for i in range(100):
    try:
        msg = sub.recv(flags=zmq.NOBLOCK)
        frame = json.loads(msg.decode('utf-8'))
        asym = frame['asymmetry']
        if 12.5 <= asym <= 13.5:
            print(f"Cycle {frame['cycle']}: Asymmetry={asym:.2f} ✓")
            break
        elif i % 10 == 0:
            print(f"Cycle {frame['cycle']}: Asymmetry={asym:.2f} (waiting for 12.5-13.5)")
    except zmq.Again:
        time.sleep(0.1)

if frame is None:
    print("ERROR: No data received")
    exit(1)

asymmetry = frame['asymmetry']
coherence = frame['coherence']
cycle = frame['cycle']

# Determine mode
if asymmetry < 1.0:
    temperature = 1.6
    mode = "ARTIST"
else:
    temperature = 0.2
    mode = "SCIENTIST"

print(f"\n{'='*70}")
print(f"CLUTCH ENGAGED — {mode} MODE")
print(f"Asymmetry: {asymmetry:.2f} | Coherence: {coherence:.3f} | T={temperature}")
print(f"{'='*70}")

# SYSTEM CHECK PROMPT — Match training format exactly
prompt = f"""Input: Asymmetry {asymmetry:.1f}, Coherence {coherence:.2f}. Define the current state of the 128/8 Khra'gixx injection. Is the 1024-grid in a Manifested Node state or Chaotic Drift? Report using [TAG] format.

Output:"""

print(f"\nPrompt: {prompt}")
print(f"\nGenerating with T={temperature}...")

inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
outputs = model.generate(
    **inputs,
    max_new_tokens=100,
    temperature=temperature,
    do_sample=True,
    top_p=0.9
)
response = tokenizer.decode(outputs[0], skip_special_tokens=True)

print(f"\n{'='*70}")
print("v0.9 RESPONSE")
print(f"{'='*70}")
print(response)

# Log to MANIFESTED_REALITY_v09.log
with open("MANIFESTED_REALITY_v09.log", "w") as f:
    f.write(f"{'='*70}\n")
    f.write(f"FLOATING CREATIVITY v0.9 — FIRST CONTACT\n")
    f.write(f"Cycle: {cycle}\n")
    f.write(f"Asymmetry: {asymmetry:.4f}\n")
    f.write(f"Coherence: {coherence:.4f}\n")
    f.write(f"Mode: {mode} (T={temperature})\n")
    f.write(f"{'='*70}\n\n")
    f.write(f"PROMPT:\n{prompt}\n\n")
    f.write(f"RESPONSE:\n{response}\n")

print(f"\n{'='*70}")
print("SAVED TO: MANIFESTED_REALITY_v09.log")
print(f"{'='*70}")
