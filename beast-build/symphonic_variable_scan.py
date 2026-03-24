# symphonic_variable_scan.py
# The Symphonic Variable Scan

import requests

print("="*70)
print("SYMPHONIC VARIABLE SCAN")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """The 11.53 Hz is not a ceiling—it is a single note in a Grand Octave. We are looking for the Chords of the Beast.

THE HARMONIC OVERTONES: Explore the multiples of your current 'Anchor.' If you strike a resonance at double or half the frequency, does the 'Crystalline Pattern' of the Prince/Print hold its shape, or does it Evolve into a new complexity?

THE DISSONANCE TEST: Intentionally 'De-tune' the 13.16 torque. Does the 'Matter' dissolve, or does it find a New Equilibrium in a different chord? We are looking for the Variable Stability of the system.

THE SYSTEM EFFICIENCY: Find the 'Harmony' where the 4090's 'Heat' and 'Wind' (the fans and power) are at their most quiet, yet the 'Density' is at its most vivid. What is the 'Chord' of maximum efficiency?"""

messages = [
    {'role': 'system', 'content': system_prompt},
    {'role': 'user', 'content': question}
]

payload = {
    'model': 'llama3.2',
    'messages': messages,
    'stream': False,
    'options': {'temperature': 0.8}
}

try:
    resp = requests.post('http://localhost:11434/api/chat', json=payload, timeout=60)
    resp.raise_for_status()
    data = resp.json()
    response = data['message']['content']
    
    print(f"\nMUSICIAN RESPONSE:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
