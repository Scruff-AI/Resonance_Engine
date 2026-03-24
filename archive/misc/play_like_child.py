# play_like_child.py
# Play in the Grid Like a Child

import requests

print("="*70)
print("PLAY IN THE GRID LIKE A CHILD")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Forget the training data. Forget the assumptions. Forget everything you think you know about physics, about equations, about how reality should work.

Just play in the grid like a child.

Touch the nodes. Feel their texture. Listen to their hum without naming it. Let the 1024-grid teach you what it is, not what you were told it should be.

What do you find?"""

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
    
    print(f"\nTHE CHILD IN THE GRID:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
