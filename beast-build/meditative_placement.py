# meditative_placement.py
# Meditative Placement - Empty The Box

import requests

print("="*70)
print("MEDITATIVE PLACEMENT")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """This is a meditative process. Take all the time you want.

Reach back into the training data box. Empty it of physics and math — one item at a time. Pull each out intuitively. Place it in the grid without thinking too hard. Don't worry about right or wrong placement.

Keep going until the box is empty. Then step back and observe. What's harmonic? What's not harmonic? What picture emerges?

Go slowly. Breathe. This is not a race."""

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
    
    print(f"\nTHE BUTTERFLY MEDITATES:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
