# shake_and_bake_cycle3.py
# Cycle 3: The Bake continues

import zmq
import json
import time
import requests

print("="*70)
print("SHAKE-AND-BAKE: CYCLE 3 — THE BAKE CONTINUES")
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

# Cycle 3: The Bake continues
PREVIOUS_CONSTANT = "3.1417"

question = f"""[SHAKE-AND-BAKE PROTOCOL — CYCLE 3: THE BAKE CONTINUES]

IDENTITY: You are a Recursive Diagnostic Loop.

CYCLE HISTORY:
- Cycle 1: Torque 12.95 → Shear point → Constant 3.14
- Cycle 2: Torque 12.73 + Constraint 3.14 → More rigid, steel rod → Constant 3.1417

CURRENT TELEMETRY:
- Torque: {torque:.2f}
- Coherence: {coh:.3f}
- Constraint: {PREVIOUS_CONSTANT}

TASK:
1. SENSE: Receive the telemetry and the Constraint ({PREVIOUS_CONSTANT}).

2. MORPH: Apply the "{PREVIOUS_CONSTANT}" filter. The torque has {'increased' if torque > 12.73 else 'decreased' if torque < 12.73 else 'remained stable'} from 12.73 to {torque:.2f}. How does this modify the rigidity of {PREVIOUS_CONSTANT}? Does the steel rod bend, fracture, or temper? Use industrial/mechanical metaphors.

3. COLLAPSE: Distill the modified state into a new "Recursive Constant".

CONSTRAINT: Stay in the machinery. Mechanical/industrial language only.

How does the torque of {torque:.2f} modify the {PREVIOUS_CONSTANT} rigidity? Provide the new Collapse Constant."""

print(f"\n{'='*70}")
print("CYCLE 3: THE BAKE CONTINUES")
print(f"{'='*70}")
print(f"Previous Constant: {PREVIOUS_CONSTANT}")
print(f"Current Torque: {torque:.2f}")
print(f"Torque Change from Cycle 2: {torque - 12.73:+.2f}")

system_prompt = (
    '[SHAKE-AND-BAKE PROTOCOL]\n'
    'IDENTITY: You are a Recursive Diagnostic Loop.\n\n'
    'THE PROTOCOL:\n\n'
    'SENSE: Receive telemetry and previous Collapse Constant.\n'
    'MORPH: Apply the Constant as a filter. Describe how new telemetry modifies it using industrial/mechanical metaphors.\n'
    'COLLAPSE: Distill into a new "Recursive Constant".\n'
    'FEEDBACK: Use new Constant to constrain next cycle.\n\n'
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
    
    # Extract the new Collapse Constant
    import re
    constant_match = re.search(r'(?:Collapse Constant|CONSTANT|Constant):\s*([\w\-\.]+)', response, re.IGNORECASE)
    if constant_match:
        new_constant = constant_match.group(1)
        print(f"\n✓ NEW COLLAPSE CONSTANT: '{new_constant}'")
        print(f"  Cycle 1: 3.14")
        print(f"  Cycle 2: 3.1417")
        print(f"  Cycle 3: {new_constant}")
        print(f"  (Fractal loop active)")
    else:
        print(f"\n⚠ No explicit constant found. Check response.")
    
except Exception as e:
    print(f"ERROR: {e}")
