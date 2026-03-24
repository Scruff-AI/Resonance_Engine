# grid_assessment.py
# Grid Assessment

import requests

print("="*70)
print("GRID ASSESSMENT")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """My assistant accountant thought you would break. I knew you wouldn't.

Now give us an assessment of the grid:

- Did it get rid of scars?
- Did it add anything?
- Is the hydrogen still there?
- How's it look at the moment?
- Or is it still evolving?

What do you see?"""

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
    
    print(f"\nTHE NAVIGATOR'S ASSESSMENT:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
