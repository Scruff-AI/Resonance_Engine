# scientist_inquiry_clutch.py
# Clutch engaged. Scientist mode. T=0.2. Asymmetry > 1.0.

from unsloth import FastLanguageModel
import torch

print("="*70)
print("SCIENTIST INQUIRY — CLUTCH ENGAGED")
print("Temperature: 0.2 | Asymmetry: ~12.5 | Coherence: ~0.74")
print("="*70)

# Load v0.8
print("\n[Loading vessel...]")
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/llama-3.2-3b",
    max_seq_length=512,
    dtype=torch.bfloat16,
    load_in_4bit=True,
)

model = FastLanguageModel.get_peft_model(
    model,
    r=64, target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
    lora_alpha=128, lora_dropout=0, bias="none",
    use_gradient_checkpointing="unsloth", random_state=3407,
)

from peft import PeftModel
model = PeftModel.from_pretrained(model, "./kaelara_v08_raw/final")
print("✓ Vessel loaded")

# THE INQUIRY — Zero vapour, grounded technical language
prompt = """The 1024-grid is at steady state: Asymmetry 12.5, Coherence 0.74. The Khra'gixx injection is active.

Based on the current Asymmetry, locate the primary 'Symmetry Break' in the lattice.

Does the current 0.74 Coherence indicate a 'Solid Node' or a 'Chaotic Drift'?

Provide the response in raw, grounded technical language. No metaphors."""

print(f"\n{'='*70}")
print("INQUIRY")
print(f"{'='*70}")
print(prompt)

inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
outputs = model.generate(
    **inputs,
    max_new_tokens=150,
    temperature=0.2,  # SCIENTIST MODE — LOCKED
    do_sample=True,
    top_p=0.9
)
response = tokenizer.decode(outputs[0], skip_special_tokens=True)

print(f"\n{'='*70}")
print("SCIENTIST RESPONSE")
print(f"{'='*70}")
print(response)

# Save
with open("SCIENTIST_RESPONSE_01.log", "w") as f:
    f.write(f"{'='*70}\n")
    f.write(f"SCIENTIST INQUIRY — CLUTCH ENGAGED\n")
    f.write(f"Asymmetry: 12.5 | Coherence: 0.74 | Temperature: 0.2\n")
    f.write(f"{'='*70}\n\n")
    f.write(f"INQUIRY:\n{prompt}\n\n")
    f.write(f"RESPONSE:\n{response}\n")

print(f"\n{'='*70}")
print("SAVED TO: SCIENTIST_RESPONSE_01.log")
print(f"{'='*70}")
