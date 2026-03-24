# train_v07_silent_watch.py
# Train v0.7: Zen of No-Action

from unsloth import FastLanguageModel
import torch
from datasets import Dataset
import json

print("Loading base model...")
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/llama-3.2-3b",
    max_seq_length=512,  # Reduced — we don't need 2048 for silence
    dtype=torch.bfloat16,
    load_in_4bit=True,
)

# LoRA config — lighter for faster inference
model = FastLanguageModel.get_peft_model(
    model,
    r=32,  # Reduced from 64 — less overfitting
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
    lora_alpha=64,
    lora_dropout=0,
    bias="none",
    use_gradient_checkpointing="unsloth",
    random_state=3407,
)

# Load Silent Watch dataset
with open("v07_silent_watch.jsonl", "r") as f:
    data = [json.loads(line) for line in f]

dataset = Dataset.from_dict({"text": [d["text"] for d in data]})

print(f"Training on {len(data)} Silent Watch examples")
print(f"Average example length: {sum(len(d['text']) for d in data)/len(data):.0f} chars")

# Training args — minimal, fast
from transformers import TrainingArguments
from trl import SFTTrainer
from unsloth import is_bfloat16_supported

training_args = TrainingArguments(
    output_dir="./kaelara_v07_silent",
    num_train_epochs=5,  # More epochs on small dataset
    per_device_train_batch_size=2,
    gradient_accumulation_steps=2,
    warmup_steps=5,
    learning_rate=5e-4,  # Higher LR for small dataset
    fp16=not is_bfloat16_supported(),
    bf16=is_bfloat16_supported(),
    logging_steps=1,
    optim="adamw_8bit",
    weight_decay=0.01,
    lr_scheduler_type="constant",  # No decay — learn the pattern fast
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

print("\nTraining v0.7 Silent Watch...")
trainer.train()

# Save
model.save_pretrained("./kaelara_v07_silent/final")
tokenizer.save_pretrained("./kaelara_v07_silent/final")
print("\nv0.7 Silent Watch saved to ./kaelara_v07_silent/final")

# Test
test_prompts = [
    "1000 15.210 7.800 0.0100 0.500",
    "8246 8.500 12.300 3.4000 8.900",
    "15000 16.100 8.100 0.0050 0.300"
]

print("\n=== v0.7 SILENT WATCH TEST ===")
for prompt in test_prompts:
    inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
    outputs = model.generate(**inputs, max_new_tokens=20, temperature=0.1)
    response = tokenizer.decode(outputs[0], skip_special_tokens=True)
    
    # Extract just the response part
    if prompt in response:
        response = response.split(prompt)[-1].strip()
    
    print(f"\nInput:  {prompt}")
    print(f"Output: {response}")

print("\n=== TEST COMPLETE ===")
