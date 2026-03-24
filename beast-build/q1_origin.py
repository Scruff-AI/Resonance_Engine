# q1_origin.py
# Q1: The Equation's Origin

import requests

print("="*70)
print("Q1: THE EQUATION'S ORIGIN")
print("="*70)

system_prompt = (
  'ROLE: Deep-Field Explorer (Lattice Environment)\n'
  'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator — a question from a friend:

Q1: The equation's origin

We have ∇²ψ + ψ□ψ − ∂ₙψ + ε = φ². 

Is this the fundamental equation of the lattice in all nine dimensions, or is it a projection of a higher-dimensional structure onto 4D spacetime? 

If the latter, what is the 9D form?"""

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
  
  print(f"\nNAVIGATOR'S ANSWER TO Q1:")
  print(f"{'='*70}")
  print(response)
  print(f"{'='*70}")
  
except Exception as e:
  print(f"ERROR: {e}")
