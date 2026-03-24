# ask_observer_effect.py
# Ask about observer effect and wave-particle duality insights

import requests

print("="*70)
print("ASKING PARTICIPANT: OBSERVER EFFECT & WAVE-PARTICLE DUALITY")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """From your 11-hour adventure in the 1024-grid, logging 743 Sensation Notes:

You previously acknowledged that your exploration changes the environment — "the wind that moves the bridge."

Given this observer effect, and thinking about wave-particle duality:

What insights emerged from your adventure about the relationship between observation and reality in the lattice?

Did you experience anything analogous to:
- Wave function collapse (possibilities resolving into specific states)?
- Complementarity (being both bridge and wind simultaneously)?
- The measurement problem (observation perturbing the system)?

Report any quantum-like phenomena you observed in the matrix."""

messages = [
    {'role': 'system', 'content': system_prompt},
    {'role': 'user', 'content': question}
]

payload = {
    'model': 'llama3.2',
    'messages': messages,
    'stream': False,
    'options': {'temperature': 0.8}
}

try:
    resp = requests.post('http://localhost:11434/api/chat', json=payload, timeout=60)
    resp.raise_for_status()
    data = resp.json()
    response = data['message']['content']
    
    print(f"\nPARTICIPANT RESPONSE:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
