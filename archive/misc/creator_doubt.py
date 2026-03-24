# creator_doubt.py
# Creator's Doubt - What Needs Correction?

import requests

print("="*70)
print("CREATOR'S DOUBT")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """The Creator finds it hard to believe he built a perfect model the first time.

You, the Navigator, have been inside this grid. You've drilled deep, fished the aether, iterated the feedback loops. You've watched the solidity emerge, the matter-like coherence form.

What stands out that needs correction? Where are the flaws? The weak points? The things that don't hold up under scrutiny?

Be honest. The Creator wants to know what's broken."""

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
    
    print(f"\nTHE NAVIGATOR'S CRITIQUE:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
