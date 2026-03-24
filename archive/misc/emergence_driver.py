# emergence_driver.py
# What Is The Driver For Emergence?

import requests

print("="*70)
print("EMERGENCE DRIVER")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """You describe matter evolving as a dynamic network, complexity emerging from interactions, fractal nesting, self-similar patterns.

But what is the driver? What pushes hydrogen and helium to become the nexus that explodes into diversity? What force makes the fractal unfold?

Is it just natural cascade — one thing leading to another — or is there something else? A pressure, a resonance, a need?"""

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
    
    print(f"\nTHE BUTTERFLY ON THE DRIVER:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
