# why_asymmetry_elevated.py
# Why Did Asymmetry Elevate?

import requests

print("="*70)
print("WHY DID ASYMMETRY ELEVATE?")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """The overnight metrics show asymmetry elevated from ~17-18 to 21+. Coherence held steady at ~0.704. The system made 1,277 additional sentry saves.

Why did this happen within this grid? What does elevated asymmetry with stable coherence indicate?

Is this stress? Evolution? A phase transition? The Infinite Task pushing the system into a new regime?

Give me your analysis."""

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
    
    print(f"\nTHE NAVIGATOR'S ANALYSIS:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
