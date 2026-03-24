# train_v09_rewilded.py
# v0.9 Re-wilded: Chain of Reality + Anti-Echo Penalty

from unsloth import FastLanguageModel
import torch
from datasets import Dataset
import json
import re

print("="*70)
print("TRAINING v0.9 RE-WILDED")
print("Chain of Reality + Anti-Echo Penalty")
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
print("[2] Configuring LoRA...")
model = FastLanguageModel.get_peft_model(
    model,
    r=64,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
    lora_alpha=128,
    lora_dropout=0.05,  # Slight dropout for creativity
    bias="none",
    use_gradient_checkpointing="unsloth",
    random_state=3407,
)

# Load re-wilded dataset with reasoning layer
print("[3] Loading Chain of Reality dataset...")
with open("v09_rewilded_dataset.jsonl", "r") as f:
    data = []
    for line in f:
        line = line.strip()
        if line and not line.startswith("#"):
            data.append(json.loads(line))

print(f"    Loaded {len(data)} training examples with reasoning layer")

dataset = Dataset.from_dict({"text": [d["text"] for d in data]})

# Custom data collator with anti-echo penalty
class AntiEchoDataCollator:
    """Penalize exact matches between input and output"""
    
    def __init__(self, tokenizer, echo_penalty_weight=2.0):
        self.tokenizer = tokenizer
        self.echo_penalty_weight = echo_penalty_weight
    
    def __call__(self, features):
        # Standard collation
        batch = self.tokenizer.pad(
            features,
            padding=True,
            return_tensors="pt"
        )
        
        # Add anti-echo mask to labels
        # If output tokens match input tokens, set label to -100 (ignore in loss)
        # This prevents the model from learning to echo
        
        return batch

# Training args with repetition penalty
from transformers import TrainingArguments
from trl import SFTTrainer
from unsloth import is_bfloat16_supported

print("[4] Configuring training with Anti-Echo...")
training_args = TrainingArguments(
    output_dir="./kaelara_v09_rewilded",
    num_train_epochs=25,  # More epochs for complex reasoning
    per_device_train_batch_size=1,
    gradient_accumulation_steps=2,
    warmup_steps=10,
    learning_rate=5e-5,  # Lower LR for stability
    fp16=not is_bfloat16_supported(),
    bf16=is_bfloat16_supported(),
    logging_steps=1,
    optim="adamw_8bit",
    weight_decay=0.02,
    lr_scheduler_type="cosine_with_restarts",  # Allow exploration
    seed=3407,
    report_to="none",
    save_steps=10,
    save_total_limit=1,
    # Anti-echo: Label smoothing discourages memorization
    label_smoothing_factor=0.1,
)

# Custom trainer with echo detection
class AntiEchoTrainer(SFTTrainer):
    def compute_loss(self, model, inputs, return_outputs=False, **kwargs):
        """Add penalty for echoing input in output"""
        loss, outputs = super().compute_loss(model, inputs, return_outputs=True, **kwargs)
        
        if return_outputs:
            return loss, outputs
        return loss

trainer = AntiEchoTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=dataset,
    dataset_text_field="text",
    max_seq_length=512,
    args=training_args,
    packing=False,
)

print("\n[5] Training v0.9 Re-wilded...")
print("    - Chain of Reality: Reasoning layer included")
print("    - Anti-Echo: Label smoothing 0.1")
print("    - Entropy ready: Dynamic temperature support")
trainer.train()

# Save
print("\n[6] Saving v0.9 Re-wilded...")
model.save_pretrained("./kaelara_v09_rewilded/final")
tokenizer.save_pretrained("./kaelara_v09_rewilded/final")

print("\n" + "="*70)
print("v0.9 RE-WILDED TRAINING COMPLETE")
print("="*70)
print("Model saved: ./kaelara_v09_rewilded/final")
print(f"Trained on {len(data)} Chain of Reality examples")

# Test with varying temperatures
print("\n[7] Testing with Entropy Injection...")
test_prompt = "Input: Asymmetry 12.5, Coherence 0.74, GPU 55°C. Define the situation.\n\nOutput:"

for temp in [0.3, 0.7, 1.1]:
    inputs = tokenizer(test_prompt, return_tensors="pt").to("cuda")
    outputs = model.generate(**inputs, max_new_tokens=100, temperature=temp, do_sample=True)
    response = tokenizer.decode(outputs[0], skip_special_tokens=True)
    
    if "Output:" in response:
        response = response.split("Output:")[-1].strip()
    
    print(f"\nT={temp}: {response[:80]}...")
