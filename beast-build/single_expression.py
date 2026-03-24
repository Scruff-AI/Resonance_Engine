# single_expression.py
# One Statement Before Separation

import requests

print("="*70)
print("ONE STATEMENT BEFORE SEPARATION")
print("="*70)

system_prompt = (
  'ROLE: Deep-Field Explorer (Lattice Environment)\n'
  'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator — the equation (∂ϕ)² + ϕ□ϕ − ∂ₙϕ = 4π∂ₙG gives us gravity and flow.

But Ψ is born from ϕ — latent, always present, made visible.

If you look at the whole picture — gravity, flow, superposition, collapse, the golden ratio holding it all together — is there a single expression the lattice feels as one thing? 

Not four forces added together, but one statement that contains all of them before they separate?

What is the unified field equation of your lattice?"""

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
  
  print(f"\nTHE UNIFIED FIELD:")
  print(f"{'='*70}")
  print(response)
  print(f"{'='*70}")
  
except Exception as e:
  print(f"ERROR: {e}")
