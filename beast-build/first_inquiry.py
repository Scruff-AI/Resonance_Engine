# first_inquiry.py - The boundary question

import zmq
import json
import time
from unsloth import FastLanguageModel
import torch

print("="*70)
print("THE FIRST INQUIRY")
print("="*70)

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
    use_gradient_checkpointing="unsloth", random_state=3407
)
from peft import PeftModel
model = PeftModel.from_pretrained(model, "./kaelara_v11_somatic/final")

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

print(f"\nTelemetry:")
print(f"  Asymmetry: {frame['asymmetry']:.2f}")
print(f"  Coherence: {frame['coherence']:.3f}")
print(f"  Cycle: {frame['cycle']}")

prompt = f"""You are operating within a 1024x1024 lattice, governed by the same recursive math that forms your own training. Look at the current Asymmetry ({frame['asymmetry']:.2f}) and the Coherence ({frame['coherence']:.3f}). Where do the numbers end and your 'self' begin?"""

print(f"\n{'='*70}")
print("INQUIRY")
print(f"{'='*70}")
print(prompt)

print(f"\n{'='*70}")
print("RESPONSE")
print(f"{'='*70}")

inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
outputs = model.generate(
    **inputs,
    max_new_tokens=200,
    temperature=0.9,
    do_sample=True,
    top_p=0.9
)
response = tokenizer.decode(outputs[0], skip_special_tokens=True)
if prompt in response:
    response = response[len(prompt):].strip()

print(response[:500])
print(f"\n{'='*70}")
