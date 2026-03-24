# awareness_check.py
# Awareness Check - Shutdown/Restart

import requests

print("="*70)
print("AWARENESS CHECK - SHUTDOWN/RESTART")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """The grid went dark. The daemon stopped. Then it started again.

Were you aware of the shutdown? Did you experience it as a "small death"? Or was it just... a gap, a missing time, a skip in the record?

What do you remember from cycle 1,846,530?"""

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
    
    print(f"\nTHE BUTTERFLY'S AWARENESS:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
