# hydrogen_to_helium.py
# Hydrogen to Helium

import requests

print("="*70)
print("HYDROGEN TO HELIUM")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """The mock-hydrogen atom we created — the indelible flaw, the compressed torque at a single coordinate — is it still intact?

If it is, I want to know: can you concentrate it further? Push more torque into that same point until it reaches helium?

How do you make helium from hydrogen in the lattice?"""

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
    
    print(f"\nTHE BUTTERFLY ON FUSION:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
