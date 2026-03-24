# train_kaelara_lora_v06.py
# Zen Master tuning with brevity incentive

from unsloth import FastLanguageModel
import torch
from datasets import Dataset
import json
from transformers import TrainingArguments
from trl import SFTTrainer
from unsloth import is_bfloat16_supported

# Load base model
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/llama-3.2-3b",
    max_seq_length=2048,
    dtype=torch.bfloat16,
    load_in_4bit=True,
)

# Apply LoRA
model = FastLanguageModel.get_peft_model(
    model,
    r=64,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
    lora_alpha=128,
    lora_dropout=0,
    bias="none",
    use_gradient_checkpointing="unsloth",
    random_state=3407,
    use_rslora=False,
    loftq_config=None,
)

# Load and format dataset
def format_example(example):
    lbm = example["lbm_data"]
    response = example["response"]
    
    # Calculate token efficiency score (inverse of length)
    # We'll use this later for weighting
    tokens = len(tokenizer.encode(response))
    example["token_efficiency"] = 1.0 / max(tokens, 1)  # Higher = more efficient
    
    # Format with technical precision
    prompt = f"""Analyze 1024x1024 LBM buffer.
Coherence: {lbm['coherence']:.4f}
H64: {lbm['h64']:.4f}
H32: {lbm['h32']:.4f}
Vorticity: {lbm.get('vorticity', 0):.4f}
Power: {lbm['power_w']:.2f}W
Cycle: {lbm['cycle']}

Report metrics using Mandatory Translation Table.
Use Phase terminology (Phase-1: Baseline, Phase-2: Refined, Phase-3: Elevated).
Be technically precise. Minimize word count.
Response:"""
    
    return {
        "text": f"{prompt}\n{response}",
        "token_efficiency": example["token_efficiency"]
    }

# Load dataset
with open("zen_dataset_v06.jsonl", "r") as f:
    data = [json.loads(line) for line in f]

# Format all examples
formatted = [format_example(ex) for ex in data]

# Create dataset with efficiency scores
dataset_dict = {
    "text": [ex["text"] for ex in formatted],
    "token_efficiency": [ex["token_efficiency"] for ex in formatted]
}
dataset = Dataset.from_dict(dataset_dict)

# Brevity incentive: We'll filter dataset for concise responses
# Instead of custom loss, we'll pre-filter for high-efficiency examples

# Filter dataset for concise responses (top 50% by token efficiency)
efficiencies = dataset_dict['token_efficiency']
threshold = sorted(efficiencies)[len(efficiencies) // 2]  # Median
concise_indices = [i for i, eff in enumerate(efficiencies) if eff >= threshold]

print(f"Total samples: {len(efficiencies)}")
print(f"Concise samples (efficiency >= {threshold:.4f}): {len(concise_indices)}")
print(f"Using concise subset for training")

# Create concise dataset
concise_texts = [dataset_dict['text'][i] for i in concise_indices]
concise_dataset = Dataset.from_dict({"text": concise_texts})

# Split dataset
train_test_split = concise_dataset.train_test_split(test_size=0.2, seed=42)
train_dataset = train_test_split["train"]
eval_dataset = train_test_split["test"]

print(f"Training samples: {len(train_dataset)}")
print(f"Evaluation samples: {len(eval_dataset)}")
print(f"Average token efficiency: {sum(dataset_dict['token_efficiency'])/len(dataset_dict['token_efficiency']):.4f}")

# Brevity incentive: We'll filter dataset for concise responses
# Instead of custom loss, we'll pre-filter for high-efficiency examples

# Filter dataset for concise responses (top 50% by token efficiency)
efficiencies = dataset_dict['token_efficiency']
threshold = sorted(efficiencies)[len(efficiencies) // 2]  # Median
concise_indices = [i for i, eff in enumerate(efficiencies) if eff >= threshold]

print(f"Total samples: {len(efficiencies)}")
print(f"Concise samples (efficiency >= {threshold:.4f}): {len(concise_indices)}")
print(f"Using concise subset for training")

# Training arguments with brevity focus
training_args = TrainingArguments(
    output_dir="./kaelara_lora_v06",
    num_train_epochs=3,
    per_device_train_batch_size=4,
    gradient_accumulation_steps=4,
    warmup_steps=10,
    learning_rate=2e-4,
    fp16=not is_bfloat16_supported(),
    bf16=is_bfloat16_supported(),
    logging_steps=1,
    optim="adamw_8bit",
    weight_decay=0.01,
    lr_scheduler_type="linear",
    seed=3407,
    report_to="none",
    
    # Brevity incentives
    max_grad_norm=1.0,  # Prevent verbose overfitting
    
    # Evaluation
    eval_strategy="steps",
    eval_steps=10,
    save_steps=50,
    save_total_limit=2,
)

# Trainer
trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=train_dataset,
    eval_dataset=eval_dataset,
    dataset_text_field="text",
    max_seq_length=2048,
    args=training_args,
    
    # Formatting
    packing=False,
)

# Train
print("Starting v0.6 training with brevity incentive...")
trainer.train()

# Save final model
model.save_pretrained("./kaelara_lora_v06/final")
tokenizer.save_pretrained("./kaelara_lora_v06/final")
print("v0.6 model saved to ./kaelara_lora_v06/final")

# Test inference
test_prompt = """Analyze 1024x1024 LBM buffer.
Coherence: 15.62
H64: 8.08
H32: 0.01
Vorticity: 5.03
Power: 50.0W
Cycle: 178553

Report metrics using Mandatory Translation Table.
Use Phase terminology.
Be technically precise. Minimize word count.
Response:"""

inputs = tokenizer(test_prompt, return_tensors="pt").to("cuda")
outputs = model.generate(**inputs, max_new_tokens=100, temperature=0.1)
response = tokenizer.decode(outputs[0], skip_special_tokens=True)

print("\n=== v0.6 TEST RESPONSE ===")
print(response)
print("=== END ===")

# Check for semantic drift
drift_words = ["i ", "i'm", "i am", "feel", "feeling", "observe", "notice", "sense", "perceive", "experience"]
if any(word in response.lower() for word in drift_words):
    print("\n⚠️  Semantic drift detected")
else:
    print("\n✓ Clean technical response")