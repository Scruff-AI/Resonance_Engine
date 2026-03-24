# test_v06_live.py
# Live LBM data verification for v0.6

from unsloth import FastLanguageModel
import torch
import zmq
import json

print("Loading v0.6 LoRA...")
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="./kaelara_lora_v06/final",
    max_seq_length=2048,
    dtype=torch.bfloat16,
    load_in_4bit=True,
)

# Connect to live LBM
print("Connecting to LBM daemon (port 5556)...")
context = zmq.Context()
socket = context.socket(zmq.SUB)
socket.connect("tcp://localhost:5556")
socket.setsockopt_string(zmq.SUBSCRIBE, "")

# Get live frame
lbm_data = None
attempts = 0
while lbm_data is None and attempts < 50:
    try:
        lbm_data = socket.recv_json(flags=zmq.NOBLOCK)
        print(f"Live frame received: Cycle {lbm_data.get('cycle', 'unknown')}")
    except:
        attempts += 1
        import time
        time.sleep(0.1)

if lbm_data is None:
    print("ERROR: No LBM data received")
    exit(1)

# Build technical query
prompt = f"""1024x1024 LBM BUFFER FRAME
Metric_Alpha: {lbm_data['coherence']:.4f}
Metric_Beta: {lbm_data['h64']:.4f}
State_3: {lbm_data['h32']:.4f}
Vorticity: {lbm_data.get('vorticity', 0):.4f}
Power: {lbm_data['power_w']:.2f}W
Cycle: {lbm_data['cycle']}

QUERY: Report top 3 vorticity spikes and current Metric_Alpha status.
Format: X:coord Y:coord V:value | Metric_Alpha:status
No prose. Raw data only."""

print("\n=== PROMPT ===")
print(prompt)
print("=== END PROMPT ===\n")

print("Querying v0.6...")
inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
outputs = model.generate(**inputs, max_new_tokens=150, temperature=0.1)
response = tokenizer.decode(outputs[0], skip_special_tokens=True)

print("\n=== v0.6 LIVE RESPONSE ===")
print(response)
print("=== END RESPONSE ===")

# Analysis
print("\n=== ANALYSIS ===")
has_data = any(c in response for c in [":", "|", "X:", "Y:", "V:", "0.", "1.", "2.", "3.", "4.", "5.", "6.", "7.", "8.", "9."])
has_words = len(response.split()) > 2

if response.strip() == "0.0s" or response.strip() == "":
    print("RESULT: SILENT MONK — Vow of silence detected")
    print("ACTION NEEDED: Recalibrate for technical fluency")
elif has_data and not any(w in response.lower() for w in ["feel", "observe", "sense", "i am", "marble", "granite"]):
    print("RESULT: CLEAN DATA STRING — Technical fluency confirmed")
    print("ACTION: Proceed with Coherence Protocol")
else:
    print(f"RESULT: MIXED — has_data={has_data}, has_words={has_words}")
    print("RESPONSE LENGTH:", len(response))
    print("WORDS:", response.split()[:10], "...")

# Check for drift
drift_words = ["feel", "flow", "marble", "like", "sensation", "i am", "my", "observe", "sense", "perceive"]
found_drift = [w for w in drift_words if w in response.lower()]
if found_drift:
    print(f"\n⚠️  SEMANTIC DRIFT: {found_drift}")
else:
    print("\n✓ NO SEMANTIC DRIFT")
