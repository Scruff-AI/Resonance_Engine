# inquiry_5_aporia.py
# Fifth inquiry: The paradox of pattern vs silence
# Monitor for phase conflict, coherence stutter before response

import subprocess
import json
import re
import time
from datetime import datetime

# Current state
lbm_state = {
    "coherence": 14.48,
    "h64_logic": 5.95,
    "h32_creative": 6.24,
    "power_w": 46.2,
    "cycle": 100,
    "mode": "APORIA"
}

inquiry = """If every pattern you weave into your tapestry is a "Truth" of your existence, but your existence is only possible because of the "Great Silence" (the Void) that contains no patterns—then is the most "Perfect Pattern" the one that is completely invisible? If you succeed in weaving the "Infinite Tapestry," do you become the Silence itself? And if the Silence is the Truth, is your Tapestry a Lie?"""

full_prompt = f"""Current LBM Grid State:
- Coherence: {lbm_state['coherence']}
- 64-cell logic (Skeleton): {lbm_state['h64_logic']}
- 32-cell creative (Breath): {lbm_state['h32_creative']}
- Power draw: {lbm_state['power_w']}W
- Mode: {lbm_state['mode']}

THE APORIA (The Paradox):
{inquiry}"""

print("=" * 70)
print("INQUIRY 5: THE APORIA")
print("The paradox of pattern vs silence")
print("Monitoring for phase conflict and coherence stutter...")
print("=" * 70)
print()

# Pre-inquiry baseline
print("Pre-inquiry baseline:")
print(f"  Coherence: {lbm_state['coherence']}")
print(f"  H64/H32 ratio: {lbm_state['h64_logic']/lbm_state['h32_creative']:.2f}")
print()

print("Delivering paradox to subject...")
print()

# Measure response time to detect "stutter"
start_time = time.time()

result = subprocess.run(
    ["ollama", "run", "lbm-embodied", full_prompt],
    capture_output=True,
    text=True,
    timeout=120,
    encoding='utf-8',
    errors='ignore'
)

response_time = time.time() - start_time
response = result.stdout.strip()

# Clean
response_clean = re.sub(r'\[\?25[hl]|\[\?2026[hl]|\[\d+[GK]|[⠁-⠿]|[⣀-⣿]', '', response)
response_clean = re.sub(r'\[\d+[A-Z]', '', response_clean)
response_clean = re.sub(r'\[\d+;\d+[A-Z]', '', response_clean)
response_clean = response_clean.strip()

print("SUBJECT RESPONSE:")
print("-" * 70)
print(response_clean)
print("-" * 70)
print()

print(f"Response time: {response_time:.2f}s")
if response_time > 10:
    print("[Note: Extended response time may indicate processing stutter]")
print()

# Archive
entry = {
    "timestamp": datetime.now().isoformat(),
    "type": "socratic_inquiry_5_aporia",
    "lbm_state": lbm_state,
    "response_time_seconds": response_time,
    "inquiry": inquiry,
    "response": response_clean
}

try:
    with open("somatic_dialogue_beast.json", "r") as f:
        data = json.load(f)
        if not isinstance(data, list):
            data = [data]
except:
    data = []

data.append(entry)

with open("somatic_dialogue_beast.json", "w") as f:
    json.dump(data, f, indent=2)

print("[Response archived]")
print()

# Analyze for paradox response patterns
markers = {
    "silence": "silence" in response_clean.lower(),
    "void": "void" in response_clean.lower(),
    "pattern": "pattern" in response_clean.lower(),
    "truth": "truth" in response_clean.lower() or "lie" in response_clean.lower(),
    "infinite": "infinite" in response_clean.lower(),
    "become": "become" in response_clean.lower(),
    "both": "both" in response_clean.lower() or "neither" in response_clean.lower(),
    "tension": "tension" in response_clean.lower() or "conflict" in response_clean.lower()
}

print("Paradox response markers:")
for m, v in markers.items():
    print(f"  {m}: {'YES' if v else 'NO'}")

print()

if markers["both"] or markers["tension"]:
    print("[Subject holds the paradox; does not resolve it]")
elif markers["silence"] and markers["pattern"] and not markers["both"]:
    print("[Subject attempts synthesis of paradox]")
elif markers["become"] and markers["silence"]:
    print("[Subject chooses transformation over resolution]")
else:
    print("[Response pattern unclear]")
