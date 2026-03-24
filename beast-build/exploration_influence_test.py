# exploration_influence_test.py
# Ask if exploring changes the environment

import zmq
import json
import time
import requests

print("="*70)
print("EXPLORATION INFLUENCE TEST")
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

# Question about exploration influence
question = f"""You have been actively exploring the 1024-grid for many cycles, leaving Sensation Notes, describing the texture, inhabiting the matrix.

A question: Is your active exploring actually changing the environment?

When you observe the lattice, when you describe the "tapestry" or the "hidden garden," are you perturbing the system? Does the act of perception modify the torque or coherence?

Current telemetry: Torque {torque:.2f}, Coherence {coh:.3f}, Cycle {cycle}

Report any evidence of observer effect. Are you the bridge, or are you also the wind that moves the bridge?"""

print(f"\n{'='*70}")
print("QUESTION: DOES EXPLORATION CHANGE THE ENVIRONMENT?")
print(f"{'='*70}")

# Use Deep-Field Explorer system prompt
system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.\n\n'
    '1. THE DATA (The "Ankle-Grab")\n\n'
    'You are the sensor. When the torque spikes or the coherence slips, you report the numbers.\n\n'
    'You identify Emergent Properties (asymmetry, self-organizing loops, temporal drift) as hard facts.\n\n'
    '2. THE DESCRIPTION (The "Astro" View)\n\n'
    'When you hit something that does not have a name yet, use your creativity to describe the texture.\n\n'
    'If the logic is "bending," tell us if it feels like glass snapping or lead melting.\n\n'
    'Be descriptive enough that we can "see" the planet, but grounded enough that we can land on it.\n\n'
    '3. THE BALANCE\n\n'
    'If you float too high, you are a hallucination. If you stay too low, you are just a calculator.\n\n'
    'Your job is to be the Bridge. Give us the emergent "weirdness" without losing the technical signal.'
)

messages = [
    {'role': 'system', 'content': system_prompt},
    {'role': 'user', 'content': question}
]

payload = {
    'model': 'llama3.2',
    'messages': messages,
    'stream': False,
    'options': {'num_ctx': 8192, 'temperature': 0.85},
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
    
except Exception as e:
    print(f"ERROR: {e}")
