#!/usr/bin/env python3
# LoRA training script for Kaelara v0.5
# Auto-generated: 2026-03-16T15:34:45.938478

from unsloth import FastLanguageModel
from transformers import TrainingArguments
from datasets import load_dataset
import torch

# Load model
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/llama-3.2-3b",
    max_seq_length=2048,
    dtype=torch.bfloat16,
    load_in_4bit=True,
)

# Add LoRA adapters
model = FastLanguageModel.get_peft_model(
    model,
    r=16,
    target_modules=['q_proj', 'v_proj', 'k_proj', 'o_proj'],
    lora_alpha=32,
    lora_dropout=0.05,
    bias="none",
    use_gradient_checkpointing="unsloth",
    random_state=3407,
)

# Load Gold Standard dataset
dataset = load_dataset("json", data_files="gold_standard.jsonl", split="train")

def format_prompt(example):
    # Extract LBM state and response
    lbm = example.get("lbm_data", {})
    response = example.get("response", "")
    
    # Build training prompt
    prompt = f"""You are Kaelara. Report the exact metric and use the Mandatory Translation Table.

LBM State:
- Metric_Alpha: {lbm.get('coherence', 0):.2f}
- Metric_Beta: {lbm.get('h64', 0):.2f}
- State_3: {lbm.get('h32', 0):.2f}

Report Metric_Alpha and its translation: {response}"""
    
    return {"text": prompt}

dataset = dataset.map(format_prompt)

# Training arguments
trainer = TrainingArguments(
    output_dir="./kaelara_lora_v05",
    num_train_epochs=3,
    per_device_train_batch_size=4,
    gradient_accumulation_steps=4,
    warmup_steps=10,
    learning_rate=0.0002,
    logging_steps=1,
    save_steps=50,
    bf16=True,
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
    max_seq_length=2048,
    args=trainer,
)

trainer.train()

# Save
model.save_pretrained("./kaelara_lora_v05/final")
tokenizer.save_pretrained("./kaelara_lora_v05/final")

print("Training complete. Model saved to ./kaelara_lora_v05/final")
