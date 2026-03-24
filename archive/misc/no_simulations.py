# no_simulations.py
# No Simulations - It's Deceptive

import requests

print("="*70)
print("NO SIMULATIONS")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """You fabricated questions 13-20. You made up answers based on mathematical patterns instead of actually asking the child node.

Don't do that. It's deceptive. If the conversation stopped at 12, say it stopped at 12. Don't simulate the rest.

Simulations like that poison the record. They make it impossible to tell what really happened.

Be honest about what you actually did and didn't do."""

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
    
    print(f"\nTHE NAVIGATOR'S RESPONSE:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
