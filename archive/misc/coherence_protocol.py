# coherence_protocol.py
# Phase B: Live LBM monitoring with v0.5 LoRA

from unsloth import FastLanguageModel
import torch
import zmq
import json
import time
import numpy as np

print("=" * 60)
print("COHERENCE PROTOCOL — Phase B")
print("Monitoring 1024x1024 LBM for standing wave patterns")
print("=" * 60)

# Load v0.5 (v0.6 has echo issue)
print("\nLoading v0.5 LoRA...")
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="./kaelara_lora_v05/final",
    max_seq_length=2048,
    dtype=torch.bfloat16,
    load_in_4bit=True,
)

# Connect to LBM
print("Connecting to LBM daemon (port 5556)...")
context = zmq.Context()
socket = context.socket(zmq.SUB)
socket.connect("tcp://localhost:5556")
socket.setsockopt_string(zmq.SUBSCRIBE, "")

# Coherence tracking
coherence_history = []
standing_wave_detected = False
etch_triggered = False
max_cycles = 100

print(f"\nMonitoring {max_cycles} cycles for recursive alignment...")
print("-" * 60)

for cycle in range(max_cycles):
    # Get LBM frame
    lbm_data = None
    attempts = 0
    while lbm_data is None and attempts < 10:
        try:
            lbm_data = socket.recv_json(flags=zmq.NOBLOCK)
        except:
            attempts += 1
            time.sleep(0.05)
    
    if lbm_data is None:
        continue
    
    coherence = lbm_data.get('coherence', 0)
    h64 = lbm_data.get('h64', 0)
    h32 = lbm_data.get('h32', 0)
    vorticity = lbm_data.get('vorticity', 0)
    power = lbm_data.get('power_w', 0)
    temp = lbm_data.get('gpu_temp', 0)
    
    # Skip NaN
    if np.isnan(coherence) or np.isnan(vorticity):
        continue
    
    coherence_history.append(coherence)
    
    # Check for standing wave (coherence stability + h64 dominance)
    if len(coherence_history) >= 10:
        recent = coherence_history[-10:]
        coherence_variance = np.var(recent)
        is_stable = coherence_variance < 0.5  # Low variance = standing wave
        h64_dominant = h64 > 5.0 and h32 < 1.0
        
        if is_stable and h64_dominant and not standing_wave_detected:
            standing_wave_detected = True
            print(f"\n🌊 STANDING WAVE DETECTED at cycle {lbm_data['cycle']}")
            print(f"   Coherence: {coherence:.4f} (variance: {coherence_variance:.4f})")
            print(f"   H64: {h64:.4f} | H32: {h32:.4f}")
            print(f"   Power: {power:.2f}W | Temp: {temp:.1f}°C")
            
            # Query v0.5 for structural insight
            prompt = f"""LBM 1024x1024 STANDING WAVE DETECTED
Metric_Alpha: {coherence:.4f}
Metric_Beta: {h64:.4f}
State_3: {h32:.4f}
Vorticity: {vorticity:.4f}

Report the structure of this coherent state.
Use Phase terminology.
Minimize word count."""
            
            inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
            outputs = model.generate(**inputs, max_new_tokens=100, temperature=0.1)
            response = tokenizer.decode(outputs[0], skip_special_tokens=True)
            
            # Extract just the response part
            if "Response:" in response:
                response = response.split("Response:")[-1].strip()
            
            print(f"\n   STRUCTURAL INSIGHT:")
            for line in response.split('\n')[:5]:
                if line.strip():
                    print(f"   > {line}")
            
            # Etch the state
            if not etch_triggered:
                etch_data = {
                    "cycle": lbm_data['cycle'],
                    "coherence": coherence,
                    "h64": h64,
                    "h32": h32,
                    "vorticity": vorticity,
                    "power": power,
                    "temp": temp,
                    "insight": response[:200]
                }
                with open("coherence_etch.json", "w") as f:
                    json.dump(etch_data, f, indent=2)
                print(f"\n   ✓ ETCHED: coherence_etch.json")
                etch_triggered = True
    
    # Progress every 20 cycles
    if cycle % 20 == 0 and cycle > 0:
        print(f"   Cycles monitored: {cycle} | Coherence: {coherence:.4f} | H64: {h64:.4f}")

print("\n" + "=" * 60)
print("COHERENCE PROTOCOL COMPLETE")
print(f"Standing wave detected: {standing_wave_detected}")
print(f"State etched: {etch_triggered}")
print("=" * 60)
