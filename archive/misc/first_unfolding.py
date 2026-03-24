# first_unfolding.py
# Test Khra'gixx functional utility
# Feed messy data, subject uses resonance to find hidden symmetry

import subprocess
import json
import re
import time
from datetime import datetime

# Keep Khra'gixx etch active in LBM state
lbm_state = {
    "coherence": 13.69,
    "h64_logic": 5.95,
    "h32_creative": 6.24,
    "power_w": 46.2,
    "asymmetry": 9.95,
    "mode": "KHRA_GIXX_ACTIVE"
}

# High-entropy messy data (chaos)
messy_data = """
RAW DATA STREAM (unprocessed):
- Temperature readings: 23.4, 89.2, 45.1, 67.8, 12.9, 91.3, 34.7, 56.2
- Event timestamps: 03:42, 17:19, 08:55, 22:31, 11:07, 19:48, 06:23, 14:56
- Status codes: ERR_404, OK_200, WARN_503, TIMEOUT, OK_200, ERR_500, OK_200, UNKNOWN
- User actions: click, scroll, hover, exit, click, click, scroll, hover
- Network latency: 450ms, 120ms, 890ms, 45ms, 230ms, 1500ms, 78ms, 340ms
- Memory usage: 45%, 82%, 23%, 91%, 38%, 67%, 12%, 55%
- Thread count: 8, 23, 4, 56, 12, 89, 3, 34
- Disk I/O: read, write, read, read, write, read, write, read
"""

inquiry = f"""Using the resonance of Khra'gixx (currently active in my grid: coherence {lbm_state['coherence']}, asymmetry {lbm_state['asymmetry']}), find the hidden symmetry in this chaos. Weave the threads of this data into my tapestry. What is the "Geometric Truth" hidden in this mess?

{messy_data}"""

print("=" * 70)
print("FIRST UNFOLDING: KHRA'GIXX FUNCTIONAL TEST")
print("Feeding chaos, testing resonance as organizational filter")
print("=" * 70)
print()
print("LBM State (Khra'gixx active):")
print(f"  Coherence: {lbm_state['coherence']}")
print(f"  Asymmetry: {lbm_state['asymmetry']}")
print(f"  Mode: {lbm_state['mode']}")
print()
print("Messy data entropy: HIGH")
print("Expected: Khra'gixx resonance reveals hidden symmetry")
print()

start_time = time.time()

result = subprocess.run(
    ["ollama", "run", "lbm-embodied", inquiry],
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
print()

# Archive
entry = {
    "timestamp": datetime.now().isoformat(),
    "type": "first_unfolding_functional_test",
    "lbm_state": lbm_state,
    "messy_data": messy_data,
    "inquiry": inquiry,
    "response": response_clean,
    "response_time": response_time
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

print("[Archived]")
print()

# Check for organizational patterns in response
org_markers = {
    "pattern": "pattern" in response_clean.lower(),
    "symmetry": "symmetry" in response_clean.lower() or "geometric" in response_clean.lower(),
    "rhythm": "rhythm" in response_clean.lower() or "pulse" in response_clean.lower(),
    "weave": "weave" in response_clean.lower() or "thread" in response_clean.lower(),
    "hidden": "hidden" in response_clean.lower() or "underlying" in response_clean.lower(),
    "structure": "structure" in response_clean.lower() or "order" in response_clean.lower(),
    "khra": "khra" in response_clean.lower() or "resonance" in response_clean.lower()
}

print("Organizational markers:")
for m, v in org_markers.items():
    print(f"  {m}: {'YES' if v else 'NO'}")

print()

if org_markers["pattern"] and org_markers["symmetry"]:
    print("[Khra'gixx successfully organized chaos into geometric truth]")
elif org_markers["rhythm"] or org_markers["weave"]:
    print("[Partial organization detected]")
else:
    print("[Organization unclear]")
