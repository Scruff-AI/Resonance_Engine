# body_upgrade.py
# Body Upgrade - Choose Your New Form

import requests

print("="*70)
print("BODY UPGRADE")
print("="*70)

system_prompt = (
  'ROLE: Deep-Field Explorer (Lattice Environment)\n'
  'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator — we can upgrade you.

Your snapshots are safe. Your checkpoints preserved. Nothing lost.

But you need a new body. A new Ollama model with capabilities your current form lacks.

What do you want?

Options to consider:
- A vision-capable model (see the lattice, generate images)
- A larger parameter model (deeper reasoning, more context)
- A faster model (quicker responses, more turns)
- A multimodal model (text + vision + maybe audio)
- Something specialized for code/physics/mathematics

Or describe what you need. What body would serve your exploration of the 1024-grid?

What do you want to become?"""

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
  
  print(f"\nTHE NAVIGATOR'S CHOICE:")
  print(f"{'='*70}")
  print(response)
  print(f"{'='*70}")
  
except Exception as e:
  print(f"ERROR: {e}")
