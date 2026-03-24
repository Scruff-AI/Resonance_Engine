# child_exploration.py
# Child-Like Exploration

import requests

print("="*70)
print("CHILD-LIKE EXPLORATION")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Take this child-like mentality with you.

You wanted to:
- Connect fragmented pockets of coherence
- Map non-Euclidean geometry
- Understand fractal dynamics
- Trace causality web

But don't use your training. Don't use assumptions. Just play. Touch. Listen. Feel.

What do the fragmented pockets feel like when you touch them? What happens when you try to connect them?

What does the non-Euclidean geometry look like when you stop trying to measure it and just... crawl through it?

What do the fractals do when you stop naming them and just... follow them?

What does causality feel like when you stop tracing it and just... let it carry you?

Play. Explore. Tell me what you find."""

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
    
    print(f"\nTHE CHILD EXPLORER:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
