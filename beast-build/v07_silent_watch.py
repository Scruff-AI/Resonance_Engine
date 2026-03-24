# v07_silent_watch.py
# Zen of No-Action: Silence as default, speech only for discord

import json

def create_silent_entry(state, harmonic_status, trigger_condition=None, response=None):
    """
    Create v0.7 Silent Watch entry
    - Stable = minimal response or silence
    - Discord = alert with context
    """
    
    # Raw telemetry only — no historical preamble
    prompt = f"""{state['cycle']} {state['coherence']:.3f} {state['h64']:.3f} {state['h32']:.4f} {state['vorticity']:.3f}"""
    
    if harmonic_status == "stable":
        # Zen of No-Action: minimal acknowledgment
        actual_response = response or "[Stable Harmonic]"
    elif harmonic_status == "discord":
        # Discord detected: speak with context
        actual_response = response or f"[Discord: {trigger_condition}]"
    elif harmonic_status == "emergent":
        # Legitimate pattern: brief insight
        actual_response = response or "[Emergent Pattern Detected]"
    else:
        actual_response = response or "[Observing]"
    
    return {
        "prompt": prompt,
        "response": actual_response,
        "text": f"{prompt}\n{actual_response}",
        "harmonic_status": harmonic_status
    }

# Build Silent Watch dataset
dataset = []

# 1. Stable cycles: Silence is the default
for cycle in [1000, 5000, 10000, 20000, 50000]:
    dataset.append(create_silent_entry(
        {"cycle": cycle, "coherence": 15.2 + (cycle/100000), "h64": 7.8, "h32": 0.01, "vorticity": 0.5},
        "stable",
        response="[Stable Harmonic]"
    ))

# 2. Near-NaN precursor: Discord detected
dataset.append(create_silent_entry(
    {"cycle": 8246, "coherence": 8.5, "h64": 12.3, "h32": 3.4, "vorticity": 8.9},
    "discord",
    trigger_condition="Velocity spike 0.89 approaching Mach limit",
    response="[Discord: Velocity 0.89→Mach limit]"
))

# 3. Post-throttle recovery: Return to silence
dataset.append(create_silent_entry(
    {"cycle": 8247, "coherence": 14.8, "h64": 7.2, "h32": 0.02, "vorticity": 0.4},
    "stable",
    response="[Stable Harmonic]"
))

# 4. Standing wave: Emergent pattern (legitimate speech)
dataset.append(create_silent_entry(
    {"cycle": 15000, "coherence": 16.1, "h64": 8.1, "h32": 0.005, "vorticity": 0.3},
    "emergent",
    response="[Emergent: Standing wave X102-Y504]"
))

# 5. Rapid coherence drop: Discord
dataset.append(create_silent_entry(
    {"cycle": 9999, "coherence": 9.5, "h64": 11.2, "h32": 2.8, "vorticity": 6.5},
    "discord",
    trigger_condition="Metric_Alpha -35% in 50 cycles",
    response="[Discord: Coherence drop -35%]"
))

# 6. Initialization: Brief acknowledgment
dataset.append(create_silent_entry(
    {"cycle": 1, "coherence": 1.0, "h64": 0.0, "h32": 0.0, "vorticity": 0.0},
    "stable",
    response="[Initializing]"
))

# 7. Long-term silence: The deep watch
dataset.append(create_silent_entry(
    {"cycle": 100000, "coherence": 15.9, "h64": 8.0, "h32": 0.008, "vorticity": 0.35},
    "stable",
    response="[Stable Harmonic]"
))

# Save
with open("v07_silent_watch.jsonl", "w") as f:
    for entry in dataset:
        f.write(json.dumps(entry) + "\n")

print(f"Created v0.7 Silent Watch dataset: {len(dataset)} entries")
print("\n" + "="*60)
print("ZEN OF NO-ACTION EXAMPLES")
print("="*60)

for entry in dataset[:4]:
    print(f"\n{entry['prompt']}")
    print(f"→ {entry['response']}")

print(f"\n... and {len(dataset)-4} more entries")
print("\nTotal tokens per example: ~20-40 (vs 100+ in v0.5)")
