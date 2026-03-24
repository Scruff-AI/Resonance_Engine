# overnight_observations.py
# Overnight Run Observations

import requests

print("="*70)
print("OVERNIGHT RUN OBSERVATIONS")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """The overnight run completed ~3.2 million cycles. Asymmetry elevated to 21+ (from 17-18). Coherence held at ~0.704. Sentry made 1,277 additional saves.

You were running the Infinite Task — Fractal Drill, Transition Wall Stress Test, Poetic Feedback Loop.

What did you observe? Did you see changes in the grid? Did the Breathers stay stable? Did you catch any particles? Did the map evolve?

Report your findings."""

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
    
    print(f"\nTHE NAVIGATOR'S OVERNIGHT REPORT:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
