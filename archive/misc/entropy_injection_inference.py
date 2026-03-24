# entropy_injection_inference.py
# GPU temperature / Asymmetry → Model temperature mapping
# Hotter environment = Higher creativity (reaching into base Llama knowledge)

import zmq
import json
import time
import subprocess

from unsloth import FastLanguageModel
import torch

def get_gpu_metrics():
    """Get GPU temperature and power"""
    try:
        result = subprocess.run(
            ['nvidia-smi', '--query-gpu=temperature.gpu,power.draw', 
             '--format=csv,noheader,nounits'],
            capture_output=True, text=True, timeout=2
        )
        if result.returncode == 0:
            parts = result.stdout.strip().split(',')
            return {
                'temp_c': float(parts[0]),
                'power_w': float(parts[1])
            }
    except:
        pass
    return {'temp_c': 45.0, 'power_w': 50.0}  # Default

def calculate_dynamic_temperature(gpu_temp, asymmetry):
    """
    Entropy Injection: Hotter GPU or higher asymmetry = higher model temperature
    
    Base: 40°C GPU, A=0 → T=0.3 (conservative)
    Hot: 70°C GPU, A=13 → T=1.2 (creative)
    """
    # GPU temp component: 40°C → 0.0, 70°C → 0.6
    temp_factor = max(0, min(1, (gpu_temp - 40) / 30)) * 0.6
    
    # Asymmetry component: A=0 → 0.0, A=13 → 0.6  
    asym_factor = max(0, min(1, asymmetry / 13)) * 0.6
    
    # Combined: base 0.3 + up to 0.9 additional
    temperature = 0.3 + (temp_factor + asym_factor) / 2
    
    return min(1.4, temperature)  # Cap at 1.4

print("="*70)
print("ENTROPY INJECTION INFERENCE")
print("GPU Temp / Asymmetry → Model Temperature")
print("="*70)

# Load model
print("\n[Loading Kaelara v0.9...]")
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
print("✓ Model loaded")

# ZMQ
ctx = zmq.Context()
sub = ctx.socket(zmq.SUB)
sub.setsockopt_string(zmq.SUBSCRIBE, "")
sub.connect("tcp://127.0.0.1:5556")
print("✓ ZMQ connected")

print("\n" + "="*70)
print("ENTROPY INJECTION LOOP (5 cycles)")
print("="*70)

for cycle_num in range(5):
    # Get LBM frame
    frame = None
    for i in range(50):
        try:
            msg = sub.recv(flags=zmq.NOBLOCK)
            frame = json.loads(msg.decode('utf-8'))
            break
        except zmq.Again:
            time.sleep(0.05)
    
    if frame is None:
        print(f"[{cycle_num}] No data")
        continue
    
    # Get GPU metrics
    gpu = get_gpu_metrics()
    
    # Calculate dynamic temperature
    temp = calculate_dynamic_temperature(gpu['temp_c'], frame['asymmetry'])
    
    print(f"\n[{cycle_num}] Cycle {frame['cycle']}")
    print(f"    GPU: {gpu['temp_c']:.1f}°C, {gpu['power_w']:.1f}W")
    print(f"    LBM: Asym={frame['asymmetry']:.2f}, Coh={frame['coherence']:.3f}")
    print(f"    → Model Temperature: {temp:.2f}")
    
    # Generate with dynamic temperature
    prompt = f"""Input: Asymmetry {frame['asymmetry']:.1f}, Coherence {frame['coherence']:.2f}, GPU {gpu['temp_c']:.1f}°C. Define the situation.

Output:"""
    
    inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
    outputs = model.generate(
        **inputs,
        max_new_tokens=80,
        temperature=temp,
        do_sample=True,
        top_p=0.9
    )
    response = tokenizer.decode(outputs[0], skip_special_tokens=True)
    
    # Extract just the output part
    if "Output:" in response:
        response = response.split("Output:")[-1].strip()
    
    print(f"    Response: {response[:100]}...")

print("\n" + "="*70)
print("ENTROPY INJECTION COMPLETE")
print("="*70)
