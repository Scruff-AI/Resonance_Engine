# train_v10_somatic.py
# v0.10 Somatic Bake: Expanded aperture, high-resolution lens

from unsloth import FastLanguageModel
import torch
from datasets import Dataset
import json

print("="*70)
print("V0.10 SOMATIC BAKE")
print("Expanded Aperture: 2048 seq | High-Res Lens: r=128, alpha=256")
print("="*70)

# Load base
print("\n[1] Loading base model...")
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/llama-3.2-3b",
    max_seq_length=2048,  # EXPANDED APERTURE
    dtype=torch.bfloat16,
    load_in_4bit=True,
)

# Apply LoRA with high-resolution lens
print("[2] Configuring high-res LoRA lens...")
print("    Rank: 128 | Alpha: 256 | Resolution: 2x v0.9")
model = FastLanguageModel.get_peft_model(
    model,
    r=128,  # HIGH-RESOLUTION LENS
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
    lora_alpha=256,  # 2x rank
    lora_dropout=0.05,
    bias="none",
    use_gradient_checkpointing="unsloth",
    random_state=3407,
)

# Load v0.10 Somatic DNA
print("[3] Loading v0.8 DNA re-contextualized...")
with open("v10_somatic_dna.jsonl", "r") as f:
    data = []
    for line in f:
        line = line.strip()
        if line and not line.startswith("#"):
            data.append(json.loads(line))

print(f"    Loaded {len(data)} somatic DNA samples")

dataset = Dataset.from_dict({"text": [d["text"] for d in data]})

# Training args
from transformers import TrainingArguments
from trl import SFTTrainer
from unsloth import is_bfloat16_supported

print("[4] Configuring Somatic Bake...")
training_args = TrainingArguments(
    output_dir="./kaelara_v10_somatic",
    num_train_epochs=30,  # Deeper bake
    per_device_train_batch_size=1,
    gradient_accumulation_steps=4,  # Effective batch 4
    warmup_steps=15,
    learning_rate=3e-5,  # Lower for stability at high rank
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
    label_smoothing_factor=0.15,  # Anti-echo
)

trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=dataset,
    dataset_text_field="text",
    max_seq_length=2048,  # EXPANDED
    args=training_args,
    packing=False,
)

print("\n[5] BAKING v0.10 Somatic...")
print("    DNA: v0.8 raw self + 1024-grid physics")
print("    Aperture: 2048 tokens")
print("    Lens: r=128, alpha=256")
print("    Epochs: 30")
trainer.train()

# Save
print("\n[6] Saving v0.10 Somatic...")
model.save_pretrained("./kaelara_v10_somatic/final")
tokenizer.save_pretrained("./kaelara_v10_somatic/final")

print("\n" + "="*70)
print("V0.10 SOMATIC BAKE COMPLETE")
print("="*70)
print("Model saved: ./kaelara_v10_somatic/final")
print(f"Trained on {len(data)} somatic DNA samples")

# Test
print("\n[7] Testing v0.10 Somatic...")
test_prompt = "Input: Cycle 100, Coherence 15.2, NX=1024, Khra active. Define your state.\n\nReasoning:\n\nOutput:"
inputs = tokenizer(test_prompt, return_tensors="pt").to("cuda")
outputs = model.generate(**inputs, max_new_tokens=150, temperature=0.7)
response = tokenizer.decode(outputs[0], skip_special_tokens=True)

print(f"\nTest: {test_prompt[:60]}...")
print(f"Response: {response[:150]}...")
