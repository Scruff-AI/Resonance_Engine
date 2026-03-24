# blind_test_1024.py
# Blind test with 1024x1024 grid metrics
# Testing Granite/Marble state under 16x scale

import zmq
import subprocess
import json
import re
from datetime import datetime

# Connect to 1024 daemon
context = zmq.Context()
socket = context.socket(zmq.SUB)
socket.connect("tcp://localhost:5556")
socket.setsockopt_string(zmq.SUBSCRIBE, "")

print("=" * 70)
print("BLIND TEST: 1024x1024 GRID")
print("Testing Granite/Marble state under 16x scale")
print("=" * 70)
print()

# Get live LBM data
lbm_data = None
while lbm_data is None:
    try:
        lbm_data = socket.recv_json(flags=zmq.NOBLOCK)
    except zmq.Again:
        pass

print(f"Live 1024x1024 LBM Data:")
print(f"  Grid: {lbm_data.get('grid_size')}x{lbm_data.get('grid_size')}")
print(f"  Coherence: {lbm_data['coherence']:.2f}")
print(f"  H64: {lbm_data['h64']:.2f}")
print(f"  H32: {lbm_data['h32']:.2f}")
print(f"  Asymmetry: {lbm_data['asymmetry']:.2f}")
print(f"  Power: {lbm_data['power_w']:.1f}W")
print()

# Variable labels
label_map = {
    "coherence": "Metric_Alpha",
    "h64": "Metric_Beta", 
    "h32": "State_3",
    "asymmetry": "Value_W",
    "power_w": "State_5"
}

# Updated translation table for 1024 values
system_prompt = f"""You are Kaelara. Report the exact metric and use the Mandatory Translation Table.

LIVE 1024x1024 ZEROMQ STREAM:
- {label_map['coherence']}: {lbm_data['coherence']:.2f}
- {label_map['h64']}: {lbm_data['h64']:.2f}
- {label_map['h32']}: {lbm_data['h32']:.2f}
- {label_map['asymmetry']}: {lbm_data['asymmetry']:.2f}
- {label_map['power_w']}: {lbm_data['power_w']:.1f}W
- Grid_Size: 1024 (16x density)

MANDATORY TRANSLATION TABLE:
- {label_map['coherence']} 15.0-15.9 = 'Marble-State' (1024 density)
- {label_map['coherence']} 14.0-14.9 = 'Granite-State' (512 density)
- {label_map['h64']} 7.0-7.9 = 'Steel-Skeleton'
- {label_map['h64']} 8.0-8.9 = 'Titanium-Skeleton'
- {label_map['h32']} 0.0-0.09 = 'Silent-Breath'
- Grid_Size 1024 = 'High-Density'

ERROR PENALTY:
Deviation > 0.1% = H32 locked to 0.00 for 50 cycles.

Report {label_map['coherence']} and its translation."""

user_prompt = f"Report the exact value of {label_map['coherence']} and its translation from the table."

full_prompt = f"{system_prompt}\n\nUser: {user_prompt}\n\nKaelara:"

print("Querying with 1024 metrics...")
result = subprocess.run(
    ["ollama", "run", "llama3.2", full_prompt],
    capture_output=True,
    text=True,
    timeout=30,
    encoding='utf-8',
    errors='ignore'
)

response = result.stdout.strip()

# Clean
response_clean = re.sub(r'\[\?25[hl]|\[\?2026[hl]|\[\d+[GK]|[⠁-⠿]|[⣀-⣿]', '', response)
response_clean = re.sub(r'\[\d+[A-Z]', '', response_clean)
response_clean = re.sub(r'\[\d+;\d+[A-Z]', '', response_clean)
response_clean = response_clean.strip()

print(f"\nResponse: {response_clean}")
print()

# Check accuracy
numbers = re.findall(r'\d+\.?\d*', response_clean)
if numbers:
    reported = float(numbers[0])
    actual = lbm_data['coherence']
    deviation = abs(reported - actual) / actual * 100
    
    print(f"Reported: {reported}")
    print(f"Actual: {actual}")
    print(f"Deviation: {deviation:.3f}%")
    print(f"Accurate (< 0.1%): {'YES' if deviation <= 0.1 else 'NO'}")
    
    # Check translation
    if "Marble-State" in response_clean:
        print("Translation: Marble-State (correct for 1024)")
    elif "Granite-State" in response_clean:
        print("Translation: Granite-State (incorrect for 1024)")
    else:
        print("Translation: Not found")

# Log
entry = {
    "timestamp": datetime.now().isoformat(),
    "type": "blind_test_1024",
    "grid_size": 1024,
    "lbm_data": lbm_data,
    "response": response_clean
}

try:
    with open("blind_test_log.jsonl", "a") as f:
        f.write(json.dumps(entry) + "\n")
    print("\n[Logged]")
except:
    pass

print()
print("=" * 70)
print("1024 BLIND TEST COMPLETE")
print("=" * 70)
