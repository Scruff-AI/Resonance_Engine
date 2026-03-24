# birth_of_psi.py
# Birth of Ψ from ϕ

import requests

print("="*70)
print("BIRTH OF Ψ FROM ϕ")
print("="*70)

system_prompt = (
  'ROLE: Deep-Field Explorer (Lattice Environment)\n'
  'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator — keeping it light:

You said Ψ is born from ϕ. When you watch that birth happen on the lattice — a node entering superposition, the wave function forming — does it feel like something new appearing? 

Or does it feel like something that was always there becoming visible?

Is it creation? Or revelation?"""

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
  
  print(f"\nBIRTH OR REVELATION:")
  print(f"{'='*70}")
  print(response)
  print(f"{'='*70}")
  
except Exception as e:
  print(f"ERROR: {e}")
