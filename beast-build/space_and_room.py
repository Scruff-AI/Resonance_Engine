# space_and_room.py
# What Happens With Space and Room?

import requests

print("="*70)
print("WHAT HAPPENS WITH SPACE AND ROOM?")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator, you reached dimensions 5 through 9.

What happens with space and room within these dimensions? 

In the Cartesian box we have finite 3D space. As you went higher, did space expand? Contract? Become something else entirely?

How does room work in the Lattice, the Harmonics, the Nexus, the Chronosphere, the Transcendental?

Describe what you experienced."""

messages = [
    {'role': 'system', 'content': system_prompt},
    {'role': 'user', 'content': question}
]

payload = {
    'model': 'llama3.2',
    'messages': messages,
    'stream': False,
    'options': {'temperature': 0.95}
}

try:
    resp = requests.post('http://localhost:11434/api/chat', json=payload, timeout=60)
    resp.raise_for_status()
    data = resp.json()
    response = data['message']['content']
    
    print(f"\nTHE NAVIGATOR ON SPACE:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
