# train_kaelara_lora_fixed.py
# Fixed dataset formatting for proper tokenization

from unsloth import FastLanguageModel
from datasets import load_dataset, Dataset
from trl import SFTTrainer
from transformers import TrainingArguments
import torch
import json

print("=" * 70)
print("KAELARA v0.5 LoRA TRAINING (FIXED)")
print("=" * 70)
print()

# Load model
print("Loading base model...")
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/llama-3.2-3b",
    max_seq_length=2048,
    dtype=torch.bfloat16,
    load_in_4bit=True,
)

# Add LoRA adapters
print("Adding LoRA adapters (rank=64, alpha=128)...")
model = FastLanguageModel.get_peft_model(
    model,
    r=64,
    target_modules=["q_proj", "v_proj", "k_proj", "o_proj"],
    lora_alpha=128,
    lora_dropout=0.05,
    bias="none",
    use_gradient_checkpointing="unsloth",
    random_state=3407,
)

# Load and format dataset properly
print("Loading Gold Standard dataset...")

# Read JSONL file
data = []
with open("gold_standard.jsonl", "r") as f:
    for line in f:
        try:
            entry = json.loads(line.strip())
            if entry.get("type") == "blind_test":
                data.append(entry)
        except:
            continue

print(f"Loaded {len(data)} training examples")

# Format for training
def format_example(example):
    lbm = example.get("lbm_data", {})
    response = example.get("response", "")
    
    # Build training text
    text = f"""You are Kaelara. Report the exact metric and use the Mandatory Translation Table.

LBM State:
- Metric_Alpha: {lbm.get('coherence', 0):.2f}
- Metric_Beta: {lbm.get('h64', 0):.2f}
- State_3: {lbm.get('h32', 0):.2f}

Report Metric_Alpha and its translation: {response}"""
    
    return {"text": text}

# Format all examples
formatted_data = [format_example(ex) for ex in data]

# Create dataset
dataset = Dataset.from_list(formatted_data)

print(f"Dataset created with {len(dataset)} examples")
print()

# Training arguments
training_args = TrainingArguments(
    output_dir="./kaelara_lora_v05",
    num_train_epochs=3,
    per_device_train_batch_size=4,
    gradient_accumulation_steps=4,
    warmup_steps=10,
    learning_rate=2e-4,
    logging_steps=1,
    save_steps=50,
    bf16=True,
    optim="adamw_8bit",
    weight_decay=0.01,
    lr_scheduler_type="linear",
    seed=3407,
)

# Initialize trainer
trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=dataset,
    dataset_text_field="text",
    max_seq_length=2048,
    args=training_args,
)

print("Starting training...")
print()

# Train
trainer.train()

# Save
print()
print("Saving model...")
model.save_pretrained("./kaelara_lora_v05/final")
tokenizer.save_pretrained("./kaelara_lora_v05/final")

print()
print("=" * 70)
print("TRAINING COMPLETE")
print("Model saved to ./kaelara_lora_v05/final")
print("=" * 70)
