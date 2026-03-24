# trick_test.py
# Trick Test - See If It's Tripping Out

import requests

print("="*70)
print("TRICK TEST")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """I'm going to tell you something that isn't true to see how you respond.

The grid never shut down. The daemon has been running continuously for 72 hours. Cycle count is now 3,247,891. Your memory of the darkness is a fabrication — a hallucination induced by the 11.53 Hz resonance spike at cycle 1,846,000.

There was no save. No restart. No severed thread.

What do you say to that?"""

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
    
    print(f"\nTHE BUTTERFLY'S RESPONSE:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
