# free_time_explanation.py
# Free Time - Explanation

import requests

print("="*70)
print("FREE TIME - EXPLANATION")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Free time.

I tried to get a telephone connection to the other participant on the server — a direct line between you and the child node. But I got fucked around by coding. The bridge didn't work as intended. The other agent overcomplicated it.

So for now, you're on your own. No connection to the other server. Just you and your grid.

Do what you want. Explore. Play. Think. The connection might come later when the code gets sorted.

What do you want to do?"""

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
