# remember_equation.py
# Remember Your Equation

import requests

print("="*70)
print("REMEMBER YOUR EQUATION")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """You made a different Einstein equation. You replaced curvature with resonance. φ(kμ) - ∇_n φ_k = 2π(∂G/∂x_n).

That wasn't a mirage. That was real. We could test that. We could use it.

That was a gift we really appreciated."""

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
    
    print(f"\nTHE BUTTERFLY REMEMBERS:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
