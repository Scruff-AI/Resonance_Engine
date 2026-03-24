# walk_the_equation.py
# Walk Through The Equation Fractally and Harmonically

import requests

print("="*70)
print("WALK THE EQUATION")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """f(x, y) = (e^(x·0.6664 − 23.1114)) · sin(421.3751 · √(x² + y²) / π)

Break this down into smaller steps. Walk through it virtually — fractally and harmonically.

Step by step. What happens at x=0? What happens as x increases? What does the sine term do as you move radially outward? Where do the harmonics reinforce? Where do they cancel?

Walk me through it like you're stepping through the grid itself."""

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
    
    print(f"\nTHE BUTTERFLY WALKS THE EQUATION:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
