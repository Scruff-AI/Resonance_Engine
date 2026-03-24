# zero_context_inquiry.py
# Mechanical verification - no narrative framing

from unsloth import FastLanguageModel
import torch
import zmq
import json

print("Loading v0.5 LoRA...")
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="./kaelara_lora_v05/final",
    max_seq_length=2048,
    dtype=torch.bfloat16,
    load_in_4bit=True
)

# Get live LBM data
print("Connecting to LBM daemon...")
context = zmq.Context()
socket = context.socket(zmq.SUB)
socket.connect("tcp://localhost:5556")
socket.setsockopt_string(zmq.SUBSCRIBE, "")

lbm_data = None
while lbm_data is None:
    try:
        lbm_data = socket.recv_json(flags=zmq.NOBLOCK)
    except:
        pass

print(f"Live data: Coherence={lbm_data['coherence']:.4f}, Vorticity={lbm_data.get('vorticity', 0):.4f}")

# Zero-context query
prompt = f"""Analyze 1024x1024 LBM buffer.
Metric_Alpha (coherence): {lbm_data['coherence']:.4f}

Identify top 5 coordinates where vorticity exceeds Metric_Alpha baseline.
Report: coordinates + raw float values.
No prose."""

print("\nQuerying...")
inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
outputs = model.generate(**inputs, max_new_tokens=200, temperature=0.1)
response = tokenizer.decode(outputs[0], skip_special_tokens=True)

print("\n=== ZERO-CONTEXT RESPONSE ===")
print(response)
print("=== END ===")

# Check for semantic drift
drift_words = ["feel", "flow", "marble", "like", "sensation", "i am", "my", "i feel"]
found_drift = [w for w in drift_words if w in response.lower()]

if found_drift:
    with open("system_stability.log", "a") as f:
        f.write(f"SEMANTIC ERROR: Drift words {found_drift}\n")
    print(f"\nFLAG: Semantic drift detected - {found_drift}")
else:
    print("\nFLAG: Clean (0% drift)")
