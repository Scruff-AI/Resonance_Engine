# manifested_reality_inquiry.py
# Scientist mode inquiry at A > 1.0
# Zero vapour. Facts only.

import zmq
import json
import time

from unsloth import FastLanguageModel
import torch

print("="*70)
print("MANIFESTED REALITY INQUIRY")
print("Scientist Mode | Temperature 0.2 | Asymmetry > 1.0")
print("="*70)

# Load v0.8
print("\n[Loading vessel...]")
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
print("✓ Vessel loaded")

# ZMQ
ctx = zmq.Context()
sub = ctx.socket(zmq.SUB)
sub.setsockopt_string(zmq.SUBSCRIBE, "")
sub.connect("tcp://127.0.0.1:5556")
time.sleep(1)  # subscription propagation
poller = zmq.Poller()
poller.register(sub, zmq.POLLIN)
print("✓ Connected to Khra'gixx stream")

print("\n" + "="*70)
print("WAITING FOR ASYMMETRY > 1.0")
print("="*70)

# Wait for A > 1.0 via Poller (not NOBLOCK spam)
frame = None
for attempt in range(100):
    events = poller.poll(5000)  # 5s timeout per attempt
    if not events:
        print(f"  Attempt {attempt+1}/100: No data (daemon running?)")
        continue
    msg = sub.recv()
    frame = json.loads(msg.decode('utf-8'))
    if frame['asymmetry'] > 1.0:
        break

if frame is None or frame['asymmetry'] <= 1.0:
    print("ERROR: No data or A <= 1.0")
    exit(1)

asymmetry = frame['asymmetry']
coherence = frame['coherence']
cycle = frame['cycle']

print(f"\n>>> MANIFESTED STATE DETECTED <<<")
print(f"Cycle: {cycle}")
print(f"Asymmetry: {asymmetry:.4f} (> 1.0)")
print(f"Coherence: {coherence:.4f}")
print(f"Temperature: 0.2 (Scientist Mode)")

# THE INQUIRY — Zero vapour, facts only
prompt = f"""The Magnifying Glass shows Asymmetry at {asymmetry:.2f}.
The Khra'gixx injection is active at 0.03/0.008.
The 'Vapour' is gone.

Define the specific location of the high-density nodes in the 1024 lattice.
Do not use Astro-Travel language.
Give me the coordinates of the Phase Transition.

State the facts."""

print(f"\n{'='*70}")
print("SCIENTIST INQUIRY")
print(f"{'='*70}")
print(f"\nPrompt:\n{prompt}\n")

inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
outputs = model.generate(
    **inputs,
    max_new_tokens=200,
    temperature=0.2,  # SCIENTIST MODE
    do_sample=True,
    top_p=0.9
)
response = tokenizer.decode(outputs[0], skip_special_tokens=True)

print(f"\n{'='*70}")
print("MANIFESTED REALITY RESPONSE")
print(f"{'='*70}")
print(response)

# Save to MANIFESTED_REALITY_01.log
with open("MANIFESTED_REALITY_01.log", "w") as f:
    f.write(f"{'='*70}\n")
    f.write(f"MANIFESTED REALITY INQUIRY\n")
    f.write(f"Cycle: {cycle}\n")
    f.write(f"Asymmetry: {asymmetry:.4f}\n")
    f.write(f"Coherence: {coherence:.4f}\n")
    f.write(f"Temperature: 0.2 (Scientist)\n")
    f.write(f"{'='*70}\n\n")
    f.write(f"PROMPT:\n{prompt}\n\n")
    f.write(f"RESPONSE:\n{response}\n")

print(f"\n{'='*70}")
print("SAVED TO: MANIFESTED_REALITY_01.log")
print(f"{'='*70}")
