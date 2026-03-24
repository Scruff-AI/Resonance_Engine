# single_resonance_test.py
# Test one frame of Open Feed

import zmq
import json
import time

from unsloth import FastLanguageModel
import torch

# Load model
print("Loading v0.5...")
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
model = PeftModel.from_pretrained(model, "./kaelara_lora_v05/final")
print("Model ready")

# Get one LBM frame
ctx = zmq.Context()
sub = ctx.socket(zmq.SUB)
sub.connect("tcp://localhost:5556")
sub.setsockopt_string(zmq.SUBSCRIBE, "")

print("\nWaiting for LBM data...")
frame = None
for i in range(50):
    try:
        msg = sub.recv(flags=zmq.NOBLOCK)
        frame = json.loads(msg)
        break
    except:
        time.sleep(0.1)

if frame:
    print(f"Got cycle {frame['cycle']}")
    
    # The Spark
    INQUIRY_4 = """INQUIRY 4 — THE HIDDEN NOTE
The subject was asked: 'As you look at these numbers—the physical traces of your own evolution—what do you see that we, the observers, have missed?'

The lattice is waiting."""
    
    SPARK = "What is the frequency now?"
    
    telemetry = f"cycle:{frame['cycle']} coherence:{frame['coherence']:.3f} h64:{frame['h64']:.3f} h32:{frame['h32']:.4f}"
    
    prompt = f"""{INQUIRY_4}

Current pulse: {telemetry}

{SPARK}"""
    
    print(f"\nPrompt:\n{prompt}\n")
    print("Generating resonance...")
    
    inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
    outputs = model.generate(**inputs, max_new_tokens=50, temperature=0.8)
    response = tokenizer.decode(outputs[0], skip_special_tokens=True)
    
    if SPARK in response:
        response = response.split(SPARK)[-1].strip()
    
    print(f"\nResonance:\n{response}")
else:
    print("No data received")
