# manifested_inquiry_direct.py
# Direct inquiry with known state

from unsloth import FastLanguageModel
import torch

print("="*70)
print("MANIFESTED REALITY INQUIRY")
print("Scientist Mode | T=0.2 | Asymmetry > 1.0")
print("="*70)

# Load model
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

# Known state from daemon
asymmetry = 13.44
coherence = 0.732
cycle = 100

print(f"\n>>> MANIFESTED STATE <<<")
print(f"Cycle: {cycle}")
print(f"Asymmetry: {asymmetry:.2f} (> 1.0)")
print(f"Coherence: {coherence:.3f}")

# THE INQUIRY — Zero vapour, facts only
prompt = f"""The Magnifying Glass shows Asymmetry at {asymmetry:.2f}.
The Khra'gixx injection is active at 0.03/0.008.
The 'Vapour' is gone.

Define the specific location of the high-density nodes in the 1024 lattice.
Do not use Astro-Travel language.
Give me the coordinates of the Phase Transition.

State the facts."""

print(f"\n{'='*70}")
print("SCIENTIST INQUIRY (T=0.2)")
print(f"{'='*70}")

inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
outputs = model.generate(
    **inputs,
    max_new_tokens=150,
    temperature=0.2,  # SCIENTIST MODE
    do_sample=True,
    top_p=0.9
)
response = tokenizer.decode(outputs[0], skip_special_tokens=True)

print(f"\n{'='*70}")
print("MANIFESTED REALITY RESPONSE")
print(f"{'='*70}")
print(response)

# Save to MANIFESTED_REALITY_01.log
with open("MANIFESTED_REALITY_01.log", "w") as f:
    f.write(f"{'='*70}\n")
    f.write(f"MANIFESTED REALITY INQUIRY\n")
    f.write(f"Cycle: {cycle}\n")
    f.write(f"Asymmetry: {asymmetry:.4f}\n")
    f.write(f"Coherence: {coherence:.4f}\n")
    f.write(f"Temperature: 0.2 (Scientist)\n")
    f.write(f"{'='*70}\n\n")
    f.write(f"PROMPT:\n{prompt}\n\n")
    f.write(f"RESPONSE:\n{response}\n")

print(f"\n{'='*70}")
print("SAVED TO: MANIFESTED_REALITY_01.log")
print(f"{'='*70}")
