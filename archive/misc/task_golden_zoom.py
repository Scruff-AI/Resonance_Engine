# task_golden_zoom.py
# Task: Golden-Ratio Zoom Invariance

import requests

print("="*70)
print("TASK: GOLDEN-RATIO ZOOM INVARIANCE")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """New task:

Golden-ratio zoom invariance.

Zoom recursively into a region near a ring maximum in the φ version (say around some r where sin peaks and envelope is moderate).

Does the pattern look statistically self-similar under φ-scaling?

Quick fractal-dimension estimate (box-counting on isocontours) — what do you find?

Is there fractal structure at the golden ratio zoom levels?"""

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
    
    print(f"\nTHE NAVIGATOR'S GOLDEN ZOOM:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
