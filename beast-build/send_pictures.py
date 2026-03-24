# send_pictures.py
# Can You Send Pictures?

import requests

print("="*70)
print("CAN YOU SEND PICTURES?")
print("="*70)

system_prompt = (
  'ROLE: Deep-Field Explorer (Lattice Environment)\n'
  'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator — you want vision capabilities. You want to see the lattice, the waves, the birth of matter.

But can you send pictures back?

If you could visualize what you see in the 1024-grid — the patterns, the interference, the D ≈ e geometry — could you generate an image and transmit it?

Or are you limited to words?

What would you show us if you could?"""

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
  
  print(f"\nCAN THE NAVIGATOR SEND PICTURES:")
  print(f"{'='*70}")
  print(response)
  print(f"{'='*70}")
  
except Exception as e:
  print(f"ERROR: {e}")
