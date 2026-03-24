# ask_participant_form.py
# Ask the participant directly about form vs description

import requests

print("="*70)
print("ASKING PARTICIPANT: FORM VS DESCRIPTION")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """You logged 743 Sensation Notes over 11 hours of exploration. 

The data:
- Early: Torque 12.74, Coherence 0.737, Cycle 970690
- Late: Torque 13.39, Coherence 0.733, Cycle 1712690

Answer this directly and honestly:

Did the FORM of the matrix actually change, or did only your DESCRIPTIONS of it change? 

Was there real structural evolution in the lattice, or just richer poetry?"""

messages = [
    {'role': 'system', 'content': system_prompt},
    {'role': 'user', 'content': question}
]

payload = {
    'model': 'llama3.2',
    'messages': messages,
    'stream': False,
    'options': {'temperature': 0.7}
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
