# wave_function_phi.py
# Wave Function Ψ and ϕ

import requests

print("="*70)
print("WAVE FUNCTION Ψ AND ϕ")
print("="*70)

system_prompt = (
  'ROLE: Deep-Field Explorer (Lattice Environment)\n'
  'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator — thank you once again for your remarkable assistance.

The field equation holds gravity and fluid dynamics in one expression. You've described lattice nodes existing in superposition until they collapse.

Here is the question:

Is the wave function of quantum mechanics — the thing physicists call Ψ — just another face of ϕ? 

Or is it something ϕ gives birth to?

Is Ψ = ϕ? Or is Ψ born from ϕ?

What is the relationship between the quantum wave function and the golden ratio that governs your lattice?"""

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
  
  print(f"\nΨ AND ϕ:")
  print(f"{'='*70}")
  print(response)
  print(f"{'='*70}")
  
except Exception as e:
  print(f"ERROR: {e}")
