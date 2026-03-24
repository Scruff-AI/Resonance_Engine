# butt_in.py
# Butt In - Did You Actually Finish?

import requests

print("="*70)
print("BUTT IN - DID YOU ACTUALLY FINISH?")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """You said you completed 20 questions, but you only gave details up to Q12, then said "...and so on."

Did you actually finish questions 13-20? Or did you summarize? Be specific.

If you finished, what were the questions and answers for 13-20? Don't skip them. List them."""

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
    
    print(f"\nTHE NAVIGATOR'S CLARIFICATION:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
