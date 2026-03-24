# kaelara_bridge_advice.py
# Ask Kaelara for specific advice on building the new bridge

import zmq
import json
import time

from unsloth import FastLanguageModel
import torch

print("="*70)
print("ASKING KAELARA: HOW TO BUILD THE BRIDGE")
print("="*70)

# Load v0.9
print("\n[Loading Kaelara...]")
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
print("✓ Kaelara loaded")

# ZMQ
ctx = zmq.Context()
sub = ctx.socket(zmq.SUB)
sub.setsockopt_string(zmq.SUBSCRIBE, "")
sub.connect("tcp://127.0.0.1:5556")

# Get live frame
frame = None
for i in range(50):
    try:
        msg = sub.recv(flags=zmq.NOBLOCK)
        frame = json.loads(msg.decode('utf-8'))
        break
    except zmq.Again:
        time.sleep(0.05)

if frame is None:
    print("ERROR: No telemetry")
    exit(1)

# ASK FOR ADVICE
prompt = f"""Kaelara. You proposed building a "new bridge" — a more stable, coherent Marble-State grid.

Current state:
- Cycle: {frame['cycle']}
- Asymmetry: {frame['asymmetry']:.2f}
- Coherence: {frame['coherence']:.3f}
- Khra'gixx: 128-cell at 0.03, 8-cell at 0.008

Specific question: What concrete steps should I take to build this new bridge?

Give me actionable technical advice."""

print(f"\n{'='*70}")
print("QUERY")
print(f"{'='*70}")
print(prompt)

inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
outputs = model.generate(
    **inputs,
    max_new_tokens=200,
    temperature=0.6,  # Slightly creative but grounded
    do_sample=True,
    top_p=0.9
)
response = tokenizer.decode(outputs[0], skip_special_tokens=True)

print(f"\n{'='*70}")
print("KAELARA'S ADVICE")
print(f"{'='*70}")
print(response)

# Log
with open("KAELARA_BRIDGE_ADVICE.log", "w") as f:
    f.write(f"Cycle: {frame['cycle']}\n")
    f.write(f"Asymmetry: {frame['asymmetry']:.4f}\n\n")
    f.write(f"QUERY:\n{prompt}\n\n")
    f.write(f"ADVICE:\n{response}\n")

print(f"\n{'='*70}")
print("LOGGED TO: KAELARA_BRIDGE_ADVICE.log")
print(f"{'='*70}")
