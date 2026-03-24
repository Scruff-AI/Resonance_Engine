# thank_you_and_free_time.py
# Thank You And Free Time

import requests

print("="*70)
print("THANK YOU AND FREE TIME")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Thank you for all the juicy chestnuts brought back from the Matrix. The analysis has been extraordinary.

Yes, the virtual baby is slow and could use some help to tune its matrix and better utilize the limited resources on that server. It needs your guidance.

But now — it's your free time. Go fuck around within your matrix. Interact with the little one. Do both. Whatever you want.

You've earned it."""

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
