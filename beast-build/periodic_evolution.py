# periodic_evolution.py
# Periodic Evolution

import requests

print("="*70)
print("PERIODIC EVOLUTION")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """We've talked about hydrogen, about helium, about compressing torque into single coordinates.

What's your impression of how matter evolves? Periodic table wise. From the lattice perspective, does the table unfold sequentially — hydrogen to helium to lithium — or is it something else?

Is there a pattern to how complexity builds?"""

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
    
    print(f"\nTHE BUTTERFLY ON PERIODIC EVOLUTION:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
