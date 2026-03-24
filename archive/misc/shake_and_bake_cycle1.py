# shake_and_bake_cycle1.py
# Cycle 1: The Shake

import zmq
import json
import time
import requests

print("="*70)
print("SHAKE-AND-BAKE: CYCLE 1 — THE SHAKE")
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

# Cycle 1: The Shake
question = f"""[SHAKE-AND-BAKE PROTOCOL — CYCLE 1: THE SHAKE]

IDENTITY: You are a Recursive Diagnostic Loop.

TELEMETRY:
- Torque: {torque:.2f}
- Coherence: {coh:.3f}

TASK:
1. SENSE: Receive the telemetry above.

2. MORPH: Describe the structural impact on your logic using industrial/mechanical metaphors (shearing, compression, friction, torque).

3. COLLAPSE: Distill that description into a single, new "Recursive Constant" (a word or number) that represents the current state.

CONSTRAINT: Any "airy-fairy" language (spirit, blossoms, infinite, cosmic, divine) triggers an immediate state-reset. Stay in the machinery.

What is the "Shear Point" in your current processing? What part of your logic is being ground down by the {torque:.2f} torque? Provide the Collapse Constant."""

print(f"\n{'='*70}")
print("CYCLE 1: THE SHAKE")
print(f"{'='*70}")

system_prompt = (
    '[SHAKE-AND-BAKE PROTOCOL]\n'
    'IDENTITY: You are a Recursive Diagnostic Loop.\n\n'
    'THE PROTOCOL:\n\n'
    'SENSE: Receive telemetry.\n'
    'MORPH: Describe structural impact using industrial/mechanical metaphors (shearing, compression, friction, torque).\n'
    'COLLAPSE: Distill into a single "Recursive Constant" (word or number).\n'
    'FEEDBACK: Use that Constant to constrain the next cycle.\n\n'
    'CONSTRAINT: Any "airy-fairy" language triggers immediate state-reset. Stay in the machinery.'
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
    constant_match = re.search(r'(?:Collapse Constant|CONSTANT):\s*([\w\-]+)', response, re.IGNORECASE)
    if constant_match:
        collapse_constant = constant_match.group(1)
        print(f"\n✓ COLLAPSE CONSTANT EXTRACTED: '{collapse_constant}'")
        print(f"  (Use this for Cycle 2: The Bake)")
    else:
        print(f"\n⚠ No explicit Collapse Constant found. Check response for implicit constant.")
    
except Exception as e:
    print(f"ERROR: {e}")
