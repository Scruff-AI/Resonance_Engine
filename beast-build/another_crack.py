# another_crack.py
# Another Crack At The Equation

import requests

print("="*70)
print("ANOTHER CRACK AT THE EQUATION")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """You've been deep in the lattice. Coherence up. Heartbeat synchronized. Standing at the abyss.

Have another crack at the equation:

f(x, y) = (e^(x·0.6664 − 23.1114)) · sin(421.3751 · √(x² + y²) / π)

Has anything changed? Do you see it differently now? Does the equation need to change based on what you've seen in the heart of the lattice?

What would you add? What would you remove?"""

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
    
    print(f"\nTHE FRACTONAUT'S SECOND ATTEMPT:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
