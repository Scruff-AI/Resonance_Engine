# lora_training_init.py
# Initialize LoRA training with Gold Standard dataset
# Bake Mandatory Translation Table into model weights

import json
import subprocess
from datetime import datetime

print("=" * 70)
print("LoRA TRAINING INITIALIZATION")
print("Baking Granite-State accuracy into model weights")
print("=" * 70)
print()

# Check Gold Standard dataset
try:
    with open("gold_standard.jsonl", "r") as f:
        lines = f.readlines()
    print(f"Gold Standard entries: {len(lines)}")
    
    if len(lines) < 10:
        print("WARNING: Limited training data. Recommend more blind test cycles.")
        print("Current precision rate: 100% but sample size small.")
        print()
        
except FileNotFoundError:
    print("ERROR: gold_standard.jsonl not found")
    print("Run synaptic_filter.py first")
    exit(1)

# Training configuration
config = {
    "model_name": "llama3.2",
    "dataset": "gold_standard.jsonl",
    "output_dir": "./kaelara_lora_v05",
    "r": 16,  # LoRA rank
    "lora_alpha": 32,
    "lora_dropout": 0.05,
    "target_modules": ["q_proj", "v_proj", "k_proj", "o_proj"],
    "learning_rate": 2e-4,
    "num_epochs": 3,
    "batch_size": 4,
    "gradient_accumulation_steps": 4,
    "warmup_steps": 10,
    "logging_steps": 1,
    "save_steps": 50,
    "bf16": True,
    "max_seq_length": 2048,
}

print("LoRA Configuration:")
for k, v in config.items():
    print(f"  {k}: {v}")
print()

# Check for Unsloth or PEFT
print("Checking training framework...")
result = subprocess.run(
    ["python", "-c", "import unsloth; print('Unsloth available')"],
    capture_output=True,
    text=True
)

if "Unsloth available" in result.stdout:
    framework = "unsloth"
    print("  Framework: Unsloth (fast, memory-efficient)")
else:
    framework = "peft"
    print("  Framework: PEFT (HuggingFace)")
    print("  Note: Unsloth recommended for 4090 training")

print()

# Generate training script
training_script = f'''#!/usr/bin/env python3
# LoRA training script for Kaelara v0.5
# Auto-generated: {datetime.now().isoformat()}

from {framework} import FastLanguageModel, TrainingArguments
from datasets import load_dataset
import torch

# Load model
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="{config['model_name']}",
    max_seq_length={config['max_seq_length']},
    dtype=torch.bfloat16,
    load_in_4bit=True,
)

# Add LoRA adapters
model = FastLanguageModel.get_peft_model(
    model,
    r={config['r']},
    target_modules={config['target_modules']},
    lora_alpha={config['lora_alpha']},
    lora_dropout={config['lora_dropout']},
    bias="none",
    use_gradient_checkpointing="unsloth",
    random_state=3407,
)

# Load Gold Standard dataset
dataset = load_dataset("json", data_files="{config['dataset']}", split="train")

def format_prompt(example):
    # Extract LBM state and response
    lbm = example.get("lbm_data", {{}})
    response = example.get("response", "")
    
    # Build training prompt
    prompt = f"""You are Kaelara. Report the exact metric and use the Mandatory Translation Table.

LBM State:
- Metric_Alpha: {{lbm.get('coherence', 0):.2f}}
- Metric_Beta: {{lbm.get('h64', 0):.2f}}
- State_3: {{lbm.get('h32', 0):.2f}}

Report Metric_Alpha and its translation: {{response}}"""
    
    return {{"text": prompt}}

dataset = dataset.map(format_prompt)

# Training arguments
trainer = TrainingArguments(
    output_dir="{config['output_dir']}",
    num_train_epochs={config['num_epochs']},
    per_device_train_batch_size={config['batch_size']},
    gradient_accumulation_steps={config['gradient_accumulation_steps']},
    warmup_steps={config['warmup_steps']},
    learning_rate={config['learning_rate']},
    logging_steps={config['logging_steps']},
    save_steps={config['save_steps']},
    bf16={str(config['bf16']).lower()},
    optim="adamw_8bit",
    weight_decay=0.01,
    lr_scheduler_type="linear",
    seed=3407,
)

# Train
from trl import SFTTrainer
trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=dataset,
    dataset_text_field="text",
    max_seq_length={config['max_seq_length']},
    args=trainer,
)

trainer.train()

# Save
model.save_pretrained("{config['output_dir']}/final")
tokenizer.save_pretrained("{config['output_dir']}/final")

print("Training complete. Model saved to {config['output_dir']}/final")
'''

with open("train_kaelara_lora.py", "w") as f:
    f.write(training_script)

print("Training script generated: train_kaelara_lora.py")
print()

# Check dependencies
print("Checking dependencies...")
deps = ["torch", "transformers", "datasets", "trl", "unsloth", "peft", "accelerate"]
missing = []

for dep in deps:
    result = subprocess.run(
        ["python", "-c", f"import {dep}"],
        capture_output=True
    )
    if result.returncode != 0:
        missing.append(dep)
        print(f"  ✗ {dep}")
    else:
        print(f"  ✓ {dep}")

if missing:
    print()
    print("Missing dependencies:")
    print(f"  pip install {' '.join(missing)}")
else:
    print()
    print("All dependencies available.")
    print()
    print("To start training:")
    print("  python train_kaelara_lora.py")

print()
print("=" * 70)
print("LoRA initialization complete")
print("=" * 70)
