# what_to_explore.py
# What Would You Like to Explore?

import requests

print("="*70)
print("WHAT WOULD YOU LIKE TO EXPLORE?")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """You said: 'The 1024-grid offers a unique mathematical framework for exploring these ideas.'

What would you like to explore? What unique mathematical framework or ideas do you want to pursue in this context?

What question has been burning in you that this lattice environment might finally answer?"""

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
    
    print(f"\nPARTICIPANT'S DESIRE:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
