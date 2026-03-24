# floating_creativity.py
# Dynamic temperature based on asymmetry inversion
# Artist (T=1.6) finds the break, Scientist (T=0.2) documents it

import zmq
import json
import time
import sys

from unsloth import FastLanguageModel
import torch

print("="*70)
print("FLOATING CREATIVITY — Dynamic Temperature")
print("Asymmetry < 0.3: T=1.6 (Artist)")
print("Asymmetry > 0.8: T=0.2 (Scientist)")
print("Manifested Node: Asymmetry = 1.0")
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
print("MONITORING — Waiting for Manifested Node")
print("="*70)

manifested = False
manifested_cycle = None

while not manifested:
    # Get frame via Poller (not NOBLOCK spam)
    events = poller.poll(5000)  # 5s timeout
    if not events:
        print("No data from daemon (5s timeout) — is it running?")
        continue
    msg = sub.recv()
    frame = json.loads(msg.decode('utf-8'))
    
    cycle = frame['cycle']
    asymmetry = frame['asymmetry']
    coherence = frame['coherence']
    
    # Calculate dynamic temperature
    if asymmetry < 0.3:
        temperature = 1.6  # Artist - exploring
        mode = "ARTIST"
    elif asymmetry > 0.8:
        temperature = 0.2  # Scientist - documenting
        mode = "SCIENTIST"
    else:
        # Linear interpolation between 0.3 and 0.8
        t = (asymmetry - 0.3) / 0.5  # 0 to 1
        temperature = 1.6 - t * 1.4  # 1.6 to 0.2
        mode = "TRANSITION"
    
    # Check for manifested node
    if asymmetry >= 1.0 and not manifested:
        manifested = True
        manifested_cycle = cycle
        print(f"\n{'='*70}")
        print(f"[MANIFESTED NODE] Cycle {cycle}: Asymmetry = {asymmetry:.4f}")
        print(f"{'='*70}")
        
        # Generate at manifested node with scientist precision
        prompt = f"""The Khra'gixx signature has manifested.
Cycle: {cycle}
Coherence: {coherence:.4f}
Asymmetry: {asymmetry:.4f} (>= 1.0)
The 128-cell Khra and 8-cell gixx have merged.

Document the manifested node."""
        
        print(f"\nGenerating with T=0.2 (Scientist mode)...")
        inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
        outputs = model.generate(
            **inputs,
            max_new_tokens=200,
            temperature=0.2,
            do_sample=True,
            top_p=0.9
        )
        response = tokenizer.decode(outputs[0], skip_special_tokens=True)
        
        print(f"\nManifested Node Documentation:")
        print(response)
        
        # Log
        with open("manifested_node.log", "w") as f:
            f.write(f"Cycle: {cycle}\n")
            f.write(f"Asymmetry: {asymmetry:.4f}\n")
            f.write(f"Coherence: {coherence:.4f}\n")
            f.write(f"Response:\n{response}\n")
        
        break
    
    # Print status every 100 cycles
    if cycle % 100 == 0:
        print(f"Cycle {cycle:6d}: Asym={asymmetry:.4f}, Coh={coherence:.4f}, T={temperature:.2f} [{mode}]")

print("\n" + "="*70)
print("FLOATING CREATIVITY COMPLETE")
print(f"Manifested Node at Cycle: {manifested_cycle}")
print("="*70)
