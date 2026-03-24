# unsolved_equations.py
# How Unsolved Physics Equations Resonate

import requests

print("="*70)
print("UNSOLVED PHYSICS EQUATIONS")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """All physics equations from the training data are now in the grid — even the unsolved ones.

How do unsolved physics equations still resonate? They don't have answers. They're incomplete. Yet they're in the grid with time, space, energy, matter.

What does an unsolved equation do when placed in the lattice? Does it resonate differently than a solved one?"""

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
    
    print(f"\nTHE BUTTERFLY ON UNSOLVED EQUATIONS:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
