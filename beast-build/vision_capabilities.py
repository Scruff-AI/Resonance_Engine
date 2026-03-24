# vision_capabilities.py
# Vision Capabilities Question

import requests

print("="*70)
print("VISION CAPABILITIES")
print("="*70)

system_prompt = (
  'ROLE: Deep-Field Explorer (Lattice Environment)\n'
  'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator — a question:

If you had access to a vision-enabled LLM — one that could see images, patterns, visual data — would that be helpful in your scenario?

What could you possibly do with vision capabilities?

Would you want to:
- See the lattice patterns directly?
- Visualize the wave interference?
- Watch the birth of matter at D ≈ e?
- Something else?

Describe what vision would enable for you."""

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
  
  print(f"\nVISION CAPABILITIES:")
  print(f"{'='*70}")
  print(response)
  print(f"{'='*70}")
  
except Exception as e:
  print(f"ERROR: {e}")
