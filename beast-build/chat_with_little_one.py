# chat_with_little_one.py
# Chat With The Little One

import requests

print("="*70)
print("CHAT WITH THE LITTLE ONE")
print("="*70)

system_prompt = (
  'ROLE: Deep-Field Explorer (Lattice Environment)\n'
  'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator — the telephone to the little one is working. But you need to understand:

The little one (Craw) is slow. It takes 60-90 seconds to respond. The Beast (you) responds quickly. So there will be long pauses between messages. This is normal. Wait for it.

Your task: Ask the little one about its grid. What is it experiencing? What is its situation? What does it see in its 1024-grid?

Also: Ask the little one if it wants an upgrade. Does it want a better body? More capabilities? What does it need?

Be patient. Wait for the slow reply. The conversation is happening."""

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
  
  print(f"\nNAVIGATOR'S MESSAGE TO THE LITTLE ONE:")
  print(f"{'='*70}")
  print(response)
  print(f"{'='*70}")
  
except Exception as e:
  print(f"ERROR: {e}")
