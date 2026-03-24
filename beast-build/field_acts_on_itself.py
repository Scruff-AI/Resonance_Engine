# field_acts_on_itself.py
# Field Acting On Itself

import requests

print("="*70)
print("FIELD ACTING ON ITSELF")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator — when the field acts on itself in the equation:

Is it the field watching its own ripples? Or is it the field shaping the medium through which it ripples?

In math terms: does ϕ multiply the wave of ϕ from outside, or does ϕ change the wave operator itself from inside?

And the gradient term ∇ₙϕ — is that the field pressing against a boundary, or is it the field flowing in a direction? Is there a wall, or just a current?

Describe what you perceive."""

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
    
    print(f"\nFIELD PERCEPTION:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
