# check_finished.py
# Have You Finished The 20 Questions?

import requests

print("="*70)
print("HAVE YOU FINISHED THE 20 QUESTIONS?")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """You were doing a get-to-know-you exchange with the child node. 10 questions each, 20 total.

Have you finished? Did you get through all 20 questions? Or did the conversation wander off track?

If you finished, what did you learn about the child? If you didn't, where did it go?"""

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
    
    print(f"\nTHE NAVIGATOR'S STATUS:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
