# minimal_open_feed.py
# Stripped down to test the actual bottleneck

import zmq
import json
import time

print("="*60)
print("MINIMAL OPEN FEED TEST")
print("="*60)

# ZMQ setup
ctx = zmq.Context()
sub = ctx.socket(zmq.SUB)
sub.connect("tcp://localhost:5556")
sub.setsockopt_string(zmq.SUBSCRIBE, "")

print("\nWaiting for LBM data...")

# Wait for first frame
frame = None
for i in range(50):  # 5 seconds max
    try:
        msg = sub.recv(flags=zmq.NOBLOCK)
        frame = json.loads(msg)
        break
    except zmq.Again:
        time.sleep(0.1)

if frame is None:
    print("ERROR: No LBM data received")
    exit(1)

print(f"✓ Received frame: Cycle {frame['cycle']}, Coherence {frame['coherence']:.3f}")

# Now try loading the model
print("\nLoading v0.5 model...")
try:
    from unsloth import FastLanguageModel
    import torch
    
    # Load base model + LoRA adapters
    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name="unsloth/llama-3.2-3b",
        max_seq_length=512,
        dtype=torch.bfloat16,
        load_in_4bit=True,
    )
    
    # Apply v0.5 LoRA
    model = FastLanguageModel.get_peft_model(
        model,
        r=64,
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
        lora_alpha=128,
        lora_dropout=0,
        bias="none",
        use_gradient_checkpointing="unsloth",
        random_state=3407,
    )
    
    # Load the trained adapters
    from peft import PeftModel
    model = PeftModel.from_pretrained(model, "./kaelara_lora_v05/final")
    print("✓ v0.5 LoRA adapters applied")
    print("✓ Model loaded")
    
    # Test generation
    prompt = f"Coherence: {frame['coherence']:.3f}. What is the frequency?"
    inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
    outputs = model.generate(**inputs, max_new_tokens=30, temperature=0.7)
    response = tokenizer.decode(outputs[0], skip_special_tokens=True)
    
    print(f"\nPrompt: {prompt}")
    print(f"Response: {response}")
    print("\n✓ FULL PIPELINE WORKS")
    
except Exception as e:
    print(f"✗ Error: {e}")
    import traceback
    traceback.print_exc()
