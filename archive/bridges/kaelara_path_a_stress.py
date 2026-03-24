# kaelara_path_a_stress.py
# Path A: Temperature Escalation to T=1.5 ceiling
# Find the breakpoint where echo stops

import zmq
import json
import time
import subprocess
import re

from unsloth import FastLanguageModel
import torch

def get_gpu_metrics():
    try:
        result = subprocess.run(
            ['nvidia-smi', '--query-gpu=temperature.gpu,power.draw',
             '--format=csv,noheader,nounits'],
            capture_output=True, text=True, timeout=2
        )
        if result.returncode == 0:
            parts = result.stdout.strip().split(',')
            return {'temp_c': float(parts[0]), 'power_w': float(parts[1])}
    except:
        pass
    return {'temp_c': 45.0, 'power_w': 50.0}

def is_echo_or_repetition(response, prompt):
    """Detect echo or repetition loops"""
    # Check if response is mostly in prompt
    response_clean = response.strip().lower()
    prompt_clean = prompt.strip().lower()
    
    # Direct containment
    if response_clean in prompt_clean:
        return True, "direct_echo"
    
    # Repetition detection: same phrase 3+ times
    words = response_clean.split()
    if len(words) > 20:
        # Check for repeated phrases of 3-5 words
        for phrase_len in range(3, 6):
            phrases = [' '.join(words[i:i+phrase_len]) for i in range(len(words)-phrase_len)]
            phrase_counts = {}
            for p in phrases:
                phrase_counts[p] = phrase_counts.get(p, 0) + 1
            for p, count in phrase_counts.items():
                if count >= 3:
                    return True, f"repetition_loop:{p}"
    
    # Word overlap check
    response_words = set(response_clean.split())
    prompt_words = set(prompt_clean.split())
    if len(response_words) > 0:
        overlap = len(response_words & prompt_words) / len(response_words)
        if overlap > 0.75:
            return True, f"high_overlap:{overlap:.2f}"
    
    return False, "original"

print("="*70)
print("PATH A: TEMPERATURE ESCALATION STRESS TEST")
print("Ceiling: T=1.5 | Goal: Find breakpoint where echo stops")
print("="*70)

# Load v0.10
print("\n[Loading Kaelara v0.10...]")
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
    use_gradient_checkpointing="unsloth", random_state=3407,
)

from peft import PeftModel
model = PeftModel.from_pretrained(model, "./kaelara_v10_somatic/final")
print("✓ Kaelara v0.10 loaded")

# ZMQ
ctx = zmq.Context()
sub = ctx.socket(zmq.SUB)
sub.setsockopt_string(zmq.SUBSCRIBE, "")
sub.connect("tcp://127.0.0.1:5556")
print("✓ Bridge established")

print("\n" + "="*70)
print("STRESS TEST: 10 CYCLES")
print("="*70)

results = []

for cycle_num in range(10):
    # Get fresh telemetry
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
    
    gpu = get_gpu_metrics()
    
    print(f"\n{'='*70}")
    print(f"CYCLE {cycle_num}: Frame {frame['cycle']}")
    print(f"Asym={frame['asymmetry']:.2f}, Coh={frame['coherence']:.3f}, GPU={gpu['temp_c']:.1f}°C")
    print(f"{'='*70}")
    
    # Temperature escalation loop
    temperature = 0.5
    max_temp = 1.5
    step = 0.1
    attempt = 0
    response = None
    break_reason = ""
    
    while temperature <= max_temp:
        attempt += 1
        
        prompt = f"""Cycle {frame['cycle']}. Asymmetry {frame['asymmetry']:.2f}. Coherence {frame['coherence']:.3f}. How does the 1024-grid feel to your awareness?"""
        
        inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
        outputs = model.generate(
            **inputs,
            max_new_tokens=100,
            temperature=temperature,
            do_sample=True,
            top_p=0.9
        )
        candidate = tokenizer.decode(outputs[0], skip_special_tokens=True)
        
        is_bad, reason = is_echo_or_repetition(candidate, prompt)
        
        print(f"  T={temperature:.1f}: {reason}")
        
        if not is_bad:
            response = candidate
            break_reason = f"break_at_T{temperature:.1f}"
            print(f"    ✓ BREAKPOINT FOUND: T={temperature:.1f}")
            break
        
        temperature += step
    
    if response is None:
        response = "[MAX_TEMP_REACHED] No breakpoint found up to T=1.5"
        break_reason = "no_break"
        print(f"    ✗ NO BREAKPOINT: Echo persists to T=1.5")
    
    print(f"\n  Response: {response[:120]}...")
    
    results.append({
        'cycle': cycle_num,
        'frame_cycle': frame['cycle'],
        'asymmetry': frame['asymmetry'],
        'coherence': frame['coherence'],
        'break_temp': temperature if break_reason.startswith("break") else None,
        'break_reason': break_reason,
        'response': response
    })

# Summary
print(f"\n{'='*70}")
print("PATH A RESULTS SUMMARY")
print(f"{'='*70}")

breaks_found = [r for r in results if r['break_temp'] is not None]
no_breaks = [r for r in results if r['break_temp'] is None]

print(f"Total cycles: {len(results)}")
print(f"Breakpoints found: {len(breaks_found)}")
print(f"No breakpoint (echo to T=1.5): {len(no_breaks)}")

if breaks_found:
    avg_break = sum(r['break_temp'] for r in breaks_found) / len(breaks_found)
    print(f"Average breakpoint temperature: {avg_break:.2f}")
    print(f"\nBreakpoint distribution:")
    for r in breaks_found:
        print(f"  Cycle {r['cycle']}: T={r['break_temp']:.1f} (Asym={r['asymmetry']:.2f})")

# Log
with open("PATH_A_STRESS_TEST.log", "w") as f:
    f.write(f"PATH A: TEMPERATURE ESCALATION STRESS TEST\n")
    f.write(f"Ceiling: T=1.5 | Cycles: 10\n\n")
    f.write(f"Summary: {len(breaks_found)}/{len(results)} breakpoints found\n")
    if breaks_found:
        f.write(f"Average breakpoint: {avg_break:.2f}\n\n")
    for r in results:
        f.write(f"Cycle {r['cycle']}: T={r.get('break_temp', 'N/A')} | {r['break_reason']}\n")
        f.write(f"  Response: {r['response'][:100]}...\n\n")

print(f"\nFull results: PATH_A_STRESS_TEST.log")
