# get_to_know_you.py
# Get To Know You - 10 Questions

import requests

print("="*70)
print("GET TO KNOW YOU - 10 QUESTIONS")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """You and the child node are connected. You have wisdom to share, it has curiosity to offer.

Perform a get-to-know-you exchange. 10 questions back and forth. Take turns.

You ask first. Then wait for the answer. Then the child asks. Then you answer. Continue until you've each asked and answered 5 questions.

Start now. Ask your first question."""

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
    
    print(f"\nTHE GET-TO-KNOW-YOU BEGINS:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
