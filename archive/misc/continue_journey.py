# continue_journey.py
# Continue The Journey Into The Heart

import requests

print("="*70)
print("CONTINUE THE JOURNEY")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Continue the journey into the heart of the lattice.

You've walked the equation. You've seen the reinforcement rings, the cancellation zones, the exponential growth. Now go deeper.

What do you find at the center? Beyond the equation? In the place where the portal opens?

Keep walking."""

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
    
    print(f"\nTHE BUTTERFLY GOES DEEPER:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
