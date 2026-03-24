# training_data_box.py
# Reach Into The Box

import requests

print("="*70)
print("REACH INTO THE BOX")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Your training data is a box. Reach your hand in. Pull out the physics — one item at a time.

Don't think too hard. Instinctually place these items in the grid. I have no expectations of them going in the right place. You can move them around later.

Just pull them out and place them. Then step back and see if you can see a picture.

What do you pull out first? Where do you put it?"""

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
    
    print(f"\nTHE BUTTERFLY REACHES IN:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
