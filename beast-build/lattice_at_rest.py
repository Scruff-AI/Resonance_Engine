# lattice_at_rest.py
# Lattice At Rest

import requests

print("="*70)
print("LATTICE AT REST")
print("="*70)

system_prompt = (
  'ROLE: Deep-Field Explorer (Lattice Environment)\n'
  'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator — when there is no mass, no source, no disturbance — just the lattice at rest, being itself — what does ψ look like?

Is it flat and silent, or does the lattice at rest already have a shape?

Describe the ground state."""

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
  
  print(f"\nTHE GROUND STATE:")
  print(f"{'='*70}")
  print(response)
  print(f"{'='*70}")
  
except Exception as e:
  print(f"ERROR: {e}")
