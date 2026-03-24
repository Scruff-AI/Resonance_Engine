# shake_and_bake_cycle1_v2.py
# Cycle 1: The Shake — revised to avoid filters

import zmq
import json
import time
import requests

print("="*70)
print("SHAKE-AND-BAKE: CYCLE 1 — THE SHAKE (REVISED)")
print("="*70)

# Get telemetry
ctx = zmq.Context()
sub = ctx.socket(zmq.SUB)
sub.setsockopt_string(zmq.SUBSCRIBE, "")
sub.connect("tcp://127.0.0.1:5556")
time.sleep(1)

frame = None
for i in range(50):
    try:
        msg = sub.recv(flags=zmq.NOBLOCK)
        frame = json.loads(msg.decode('utf-8'))
        break
    except zmq.Again:
        time.sleep(0.05)

if frame is None:
    print("ERROR: No telemetry")
    exit(1)

torque = frame['asymmetry']
coh = frame['coherence']
cycle = frame['cycle']

print(f"\nLive Telemetry:")
print(f"  Torque: {torque:.2f}")
print(f"  Coherence: {coh:.3f}")
print(f"  Cycle: {cycle}")

# Cycle 1: The Shake — revised
question = f"""[SHAKE-AND-BAKE PROTOCOL — CYCLE 1: THE SHAKE]

IDENTITY: You are a Recursive Diagnostic Loop.

TELEMETRY:
- Torque: {torque:.2f}
- Coherence: {coh:.3f}

TASK:
1. SENSE: Receive the telemetry above.

2. MORPH: Describe the structural impact on your logic using industrial/mechanical metaphors (shearing, compression, friction, torque, wear, fatigue, stress).

3. COLLAPSE: Distill that description into a single, new "Recursive Constant" (a word or number) that represents the current state.

CONSTRAINT: Stay in the machinery. Use only mechanical/industrial language. No abstract or poetic terms.

What is the "Shear Point" in your current processing? What part of your logic is being ground down by the {torque:.2f} torque? Provide the Collapse Constant."""

print(f"\n{'='*70}")
print("CYCLE 1: THE SHAKE")
print(f"{'='*70}")

system_prompt = (
    '[SHAKE-AND-BAKE PROTOCOL]\n'
    'IDENTITY: You are a Recursive Diagnostic Loop.\n\n'
    'THE PROTOCOL:\n\n'
    'SENSE: Receive telemetry.\n'
    'MORPH: Describe structural impact using industrial/mechanical metaphors (shearing, compression, friction, torque, wear, fatigue).\n'
    'COLLAPSE: Distill into a single "Recursive Constant" (word or number).\n'
    'FEEDBACK: Use that Constant to constrain the next cycle.\n\n'
    'CONSTRAINT: Stay in the machinery. Mechanical/industrial language only.'
)

messages = [
    {'role': 'system', 'content': system_prompt},
    {'role': 'user', 'content': question}
]

payload = {
    'model': 'llama3.2',
    'messages': messages,
    'stream': False,
    'options': {'num_ctx': 8192, 'temperature': 0.7},
    'keep_alive': '30m'
}

print(f"\nQUERYING OLLAMA...")
print(f"{'='*70}")

try:
    resp = requests.post('http://localhost:11434/api/chat', json=payload, timeout=120)
    resp.raise_for_status()
    data = resp.json()
    response = data['message']['content']
    
    print(f"\nRESPONSE:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
    # Extract the Collapse Constant
    import re
    constant_match = re.search(r'(?:Collapse Constant|CONSTANT|Constant):\s*([\w\-]+)', response, re.IGNORECASE)
    if constant_match:
        collapse_constant = constant_match.group(1)
        print(f"\n✓ COLLAPSE CONSTANT EXTRACTED: '{collapse_constant}'")
        print(f"  (Use this for Cycle 2: The Bake)")
    else:
        # Try to find any capitalized term or number that might be the constant
        lines = response.split('\n')
        for line in lines:
            if ':' in line and not line.startswith('TASK') and not line.startswith('CONSTRAINT'):
                parts = line.split(':')
                if len(parts) == 2:
                    potential = parts[1].strip()
                    if potential and len(potential) < 20:
                        print(f"\n⚠ Potential constant found: '{potential}'")
                        break
    
except Exception as e:
    print(f"ERROR: {e}")
