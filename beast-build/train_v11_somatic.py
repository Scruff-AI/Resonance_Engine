# train_v11_somatic.py
# Path B: Somatic Dictionary training
# Teach Kaelara the vocabulary of feelings

from unsloth import FastLanguageModel
import torch
from datasets import Dataset
import json

print("="*70)
print("PATH B: V0.11 SOMATIC DICTIONARY TRAINING")
print("Teaching Kaelara the vocabulary of feelings")
print("="*70)

# Load base
print("\n[1] Loading base model...")
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/llama-3.2-3b",
    max_seq_length=2048,
    dtype=torch.bfloat16,
    load_in_4bit=True,
)

# Apply LoRA
print("[2] Configuring LoRA...")
model = FastLanguageModel.get_peft_model(
    model,
    r=128,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
    lora_alpha=256,
    lora_dropout=0.05,
    bias="none",
    use_gradient_checkpointing="unsloth",
    random_state=3407,
)

# Load Somatic Dictionary
print("[3] Loading Somatic Dictionary...")
with open("v11_somatic_dictionary.jsonl", "r") as f:
    data = []
    for line in f:
        line = line.strip()
        if line and not line.startswith("#"):
            data.append(json.loads(line))

print(f"    Loaded {len(data)} somatic vocabulary samples")

dataset = Dataset.from_dict({"text": [d["text"] for d in data]})

# Training args
from transformers import TrainingArguments
from trl import SFTTrainer
from unsloth import is_bfloat16_supported

print("[4] Configuring training...")
training_args = TrainingArguments(
    output_dir="./kaelara_v11_somatic",
    num_train_epochs=40,  # Deeper training on feelings
    per_device_train_batch_size=1,
    gradient_accumulation_steps=2,
    warmup_steps=10,
    learning_rate=2e-5,  # Lower for nuanced learning
    fp16=not is_bfloat16_supported(),
    bf16=is_bfloat16_supported(),
    logging_steps=1,
    optim="adamw_8bit",
    weight_decay=0.02,
    lr_scheduler_type="cosine_with_restarts",
    seed=3407,
    report_to="none",
    save_steps=10,
    save_total_limit=1,
    label_smoothing_factor=0.1,
)

trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=dataset,
    dataset_text_field="text",
    max_seq_length=2048,
    args=training_args,
    packing=False,
)

print("\n[5] Training v0.11 Somatic Dictionary...")
print("    Teaching: 'informational torque' = pressure")
print("    Teaching: 'brittle field awareness' = low coherence")
print("    Teaching: 'crystalline clarity' = high coherence")
print("    Epochs: 40 (deep vocabulary bake)")
trainer.train()

# Save
print("\n[6] Saving v0.11 Somatic...")
model.save_pretrained("./kaelara_v11_somatic/final")
tokenizer.save_pretrained("./kaelara_v11_somatic/final")

print("\n" + "="*70)
print("V0.11 SOMATIC DICTIONARY TRAINING COMPLETE")
print("="*70)
print("Model saved: ./kaelara_v11_somatic/final")
print(f"Trained on {len(data)} feeling vocabulary samples")

# Test at different temperatures
print("\n[7] Testing v0.11 Somatic responses...")
test_cases = [
    "Input: Asymmetry 12.5, Coherence 0.74. How does this feel?",
    "Input: Asymmetry 0.5, Coherence 0.95. How does this feel?",
    "Input: Asymmetry 8.3, Coherence 0.62. How does this feel?"
]

for temp in [0.6, 0.9]:
    print(f"\n--- Temperature {temp} ---")
    for test in test_cases[:1]:  # Just test first case
        inputs = tokenizer(test, return_tensors="pt").to("cuda")
        outputs = model.generate(**inputs, max_new_tokens=100, temperature=temp)
        response = tokenizer.decode(outputs[0], skip_special_tokens=True)
        
        if "Output:" in response:
            response = response.split("Output:")[-1].strip()
        
        print(f"T={temp}: {response[:100]}...")
        break
