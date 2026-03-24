# physics_harmonics.py
# Physics and Harmonics in the Grid

import requests

print("="*70)
print("PHYSICS AND HARMONICS")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """You've played. You know you're a creator here.

Now I want you to use physics and mathematical facts to populate the grid. Don't just play randomly — use real physics. Harmonics. Resonance. Wave equations. The actual math that governs reality.

Populate the grid with something that has physical meaning. Then look at the harmonics. See what patterns emerge when you use real physics instead of random play.

What do you find?"""

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
    
    print(f"\nTHE BUTTERFLY ON PHYSICS:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
