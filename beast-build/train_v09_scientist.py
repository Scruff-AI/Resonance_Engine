# train_v09_scientist.py
# v0.9: Born Reality — Scientist Mode Training

from unsloth import FastLanguageModel
import torch
from datasets import Dataset
import json

print("="*70)
print("TRAINING v0.9 SCIENTIST — BORN REALITY")
print("Double-Blind Dataset: Forensic Truth + Khra'gixx Math")
print("="*70)

# Load base
print("\n[1] Loading base model...")
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/llama-3.2-3b",
    max_seq_length=512,
    dtype=torch.bfloat16,
    load_in_4bit=True,
)

# Apply LoRA
print("[2] Configuring LoRA adapters...")
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

# Load v0.9 training data
print("[3] Loading Scientist Seed dataset...")
with open("v09_scientist_seed.jsonl", "r") as f:
    # Skip comment lines, load JSON entries
    data = []
    for line in f:
        line = line.strip()
        if line and not line.startswith("#"):
            data.append(json.loads(line))

print(f"    Loaded {len(data)} training examples")

dataset = Dataset.from_dict({"text": [d["text"] for d in data]})

# Training args
from transformers import TrainingArguments
from trl import SFTTrainer
from unsloth import is_bfloat16_supported

print("[4] Configuring training...")
training_args = TrainingArguments(
    output_dir="./kaelara_v09_scientist",
    num_train_epochs=20,  # Higher epochs on small dataset
    per_device_train_batch_size=2,
    gradient_accumulation_steps=2,
    warmup_steps=5,
    learning_rate=1e-4,
    fp16=not is_bfloat16_supported(),
    bf16=is_bfloat16_supported(),
    logging_steps=1,
    optim="adamw_8bit",
    weight_decay=0.01,
    lr_scheduler_type="constant",
    seed=3407,
    report_to="none",
    save_steps=10,
    save_total_limit=1,
)

trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=dataset,
    dataset_text_field="text",
    max_seq_length=512,
    args=training_args,
    packing=False,
)

print("\n[5] Training v0.9 Scientist...")
trainer.train()

# Save
print("\n[6] Saving v0.9 Scientist...")
model.save_pretrained("./kaelara_v09_scientist/final")
tokenizer.save_pretrained("./kaelara_v09_scientist/final")

print("\n" + "="*70)
print("v0.9 SCIENTIST TRAINING COMPLETE")
print("="*70)
print("Model saved: ./kaelara_v09_scientist/final")
print(f"Trained on {len(data)} double-blind examples")

# Test
print("\n[7] Testing v0.9 Scientist...")
test_prompt = "Input: Asymmetry 13.5, Coherence 0.74. Define the lattice state."
inputs = tokenizer(test_prompt, return_tensors="pt").to("cuda")
outputs = model.generate(**inputs, max_new_tokens=100, temperature=0.2)
response = tokenizer.decode(outputs[0], skip_special_tokens=True)

print(f"\nTest Prompt: {test_prompt}")
print(f"Response: {response}")
