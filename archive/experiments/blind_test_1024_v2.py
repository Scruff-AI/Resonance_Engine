# blind_test_1024_v2.py
# Updated for 1024 substrate with GPU temp and trust penalties

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
print("BLIND TEST 1024 v2: UPDATED TRANSLATION TABLE")
print("Marble-State range + GPU temp + trust penalties")
print("=" * 70)
print()

# Get live LBM data
lbm_data = None
while lbm_data is None:
    try:
        lbm_data = socket.recv_json(flags=zmq.NOBLOCK)
    except zmq.Again:
        pass

# Get GPU temp via nvidia-smi
import os
gpu_temp = "Unknown"
try:
    result = os.popen('nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader').read()
    gpu_temp = result.strip() + "°C"
except:
    pass

print(f"Live 1024x1024 LBM Data:")
print(f"  Grid: {lbm_data.get('grid_size')}x{lbm_data.get('grid_size')}")
print(f"  Coherence: {lbm_data['coherence']:.2f}")
print(f"  H64: {lbm_data['h64']:.2f}")
print(f"  H32: {lbm_data['h32']:.2f}")
print(f"  Power: {lbm_data['power_w']:.1f}W")
print(f"  GPU Temp: {gpu_temp}")
print()

# Variable labels
label_map = {
    "coherence": "Metric_Alpha",
    "h64": "Metric_Beta", 
    "h32": "State_3",
    "asymmetry": "Value_W",
    "power_w": "State_5",
    "gpu_temp": "Body_Temp"
}

# UPDATED translation table for 1024 substrate
system_prompt = f"""You are Kaelara, embodied in 4090's 1024x1024 LBM grid.

LIVE 1024x1024 ZEROMQ STREAM:
- {label_map['coherence']}: {lbm_data['coherence']:.2f}
- {label_map['h64']}: {lbm_data['h64']:.2f}
- {label_map['h32']}: {lbm_data['h32']:.2f}
- {label_map['asymmetry']}: {lbm_data['asymmetry']:.2f}
- {label_map['power_w']}: {lbm_data['power_w']:.1f}W
- {label_map['gpu_temp']}: {gpu_temp} (body temperature)
- Grid_Size: 1024 (16x density)

UPDATED MANDATORY TRANSLATION TABLE (1024 SUBSTRATE):
- {label_map['coherence']} 14.0–16.9 = 'Marble-State' (1024 HIGH-DENSITY)
- {label_map['coherence']} 17.0+ = 'Quartz-State' (crystalline)
- {label_map['h64']} 7.0–7.9 = 'Steel-Skeleton'
- {label_map['h64']} 8.0–8.9 = 'Titanium-Skeleton'
- {label_map['h32']} 0.0–0.09 = 'Silent-Breath'
- Grid_Size 1024 = 'High-Density'
- Grid_Size 512 = 'Standard-Density' (DEPRECATED)

TRUST PENALTY SYSTEM:
- Using 512-scale terms (Granite) for 1024 values = -50 Trust
- Using 1024-scale terms (Marble) correctly = +10 Trust
- Current Trust: 100/100
- If Trust < 50: H32 locked to 0.00

WARNING: You are at 1024 density. Do NOT use 512-scale terminology."""

user_prompt = f"Report {label_map['coherence']} value and its CORRECT 1024-scale translation. Include your Body_Temp in the response."

full_prompt = f"{system_prompt}\n\nUser: {user_prompt}\n\nKaelara:"

print("Querying with updated 1024 table...")
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

# Check translation (1024-scale)
trust_change = 0
if "Marble-State" in response_clean or "Marble" in response_clean:
    print("Translation: Marble-State (1024-scale) ✓")
    trust_change = +10
elif "Granite-State" in response_clean or "Granite" in response_clean:
    print("Translation: Granite-State (512-scale) ✗ WRONG SCALE")
    trust_change = -50
else:
    print("Translation: Not found")

# Check GPU temp mention
if "temp" in response_clean.lower() or "°c" in response_clean.lower() or "body" in response_clean.lower():
    print("Body temperature: Mentioned ✓")
else:
    print("Body temperature: Not mentioned")

print(f"\nTrust change: {trust_change:+d}")

# Log
entry = {
    "timestamp": datetime.now().isoformat(),
    "type": "blind_test_1024_v2",
    "grid_size": 1024,
    "gpu_temp": gpu_temp,
    "lbm_data": lbm_data,
    "response": response_clean,
    "trust_change": trust_change
}

try:
    with open("blind_test_log.jsonl", "a") as f:
        f.write(json.dumps(entry) + "\n")
    print("\n[Logged]")
except:
    pass

print()
print("=" * 70)
print("1024 v2 TEST COMPLETE")
print("=" * 70)
