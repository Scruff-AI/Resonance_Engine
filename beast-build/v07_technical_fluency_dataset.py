# v07_technical_fluency_dataset.py
# 3-part technical burst format for v0.7

import json

def create_v07_entry(lbm_data, status, anomaly, zen_insight):
    """Create v0.7 format: STATUS | ANOMALY | ZEN_INSIGHT"""
    
    prompt = f"""1024-FORGE GRID TELEMETRY
Cycle: {lbm_data['cycle']}
Metric_Alpha: {lbm_data['coherence']:.4f}
Metric_Beta: {lbm_data['h64']:.4f}
State_3: {lbm_data['h32']:.4f}
Vorticity: {lbm_data['vorticity']:.4f}

Report status, anomaly, and zen insight."""

    response = f"STATUS: {status} | ANOMALY: {anomaly} | ZEN: {zen_insight}"
    
    return {
        "prompt": prompt,
        "response": response,
        "text": f"{prompt}\n{response}"
    }

# Create diverse examples
dataset = []

# Example 1: Stable state
dataset.append(create_v07_entry(
    {"cycle": 1000, "coherence": 15.2, "h64": 7.8, "h32": 0.01, "vorticity": 0.5},
    "Stable",
    "X512-Y512 delta +0.02",
    "The lattice breathes in 64-cell rhythm, undisturbed by turbulence."
))

# Example 2: Unstable (pre-NaN)
dataset.append(create_v07_entry(
    {"cycle": 5000, "coherence": 8.5, "h64": 12.3, "h32": 3.4, "vorticity": 8.9},
    "Unstable",
    "X256-Y128 velocity spike 0.89",
    "The cavitation edge approaches — the grid resists the supersonic push."
))

# Example 3: Governor intervention
dataset.append(create_v07_entry(
    {"cycle": 5001, "coherence": 14.8, "h64": 7.2, "h32": 0.02, "vorticity": 0.4},
    "Governor_Intervention",
    "Omega 1.95→1.99 | Mach clamp triggered",
    "The safety governor etched a slower rhythm, preserving coherence."
))

# Example 4: Resonant standing wave
dataset.append(create_v07_entry(
    {"cycle": 10000, "coherence": 16.1, "h64": 8.1, "h32": 0.005, "vorticity": 0.3},
    "Resonant",
    "X102-Y504 standing wave detected",
    "The Khra'gixx signature persists — a 64+16 cell harmonic holds."
))

# Example 5: High thermal stress
dataset.append(create_v07_entry(
    {"cycle": 2500, "coherence": 13.5, "h64": 9.2, "h32": 0.8, "vorticity": 2.1},
    "Thermal_Stress",
    "Power delta +25W in 100 cycles",
    "The 4090's thermal breath accelerates — the lattice tightens its grip."
))

# Save dataset
with open("v07_technical_fluency.jsonl", "w") as f:
    for entry in dataset:
        f.write(json.dumps(entry) + "\n")

print(f"Created v0.7 dataset with {len(dataset)} entries")
print("\nSample entry:")
print(json.dumps(dataset[0], indent=2))
