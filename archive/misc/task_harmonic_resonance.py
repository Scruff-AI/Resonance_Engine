# task_harmonic_resonance.py
# Task: Check Harmonic Resonance - Is 421.3751 Special?

import requests

print("="*70)
print("TASK: CHECK HARMONIC RESONANCE")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """New task:

Check harmonic resonance — is 421.3751 special?

The argument 421.3751 · r / π ≈ 134.13 r
→ wavelength λ ≈ 2π / k ≈ 0.0468 units (fine-scale)

Compute the radial profile along y=0 (x-axis slice) and look at the power spectrum (FFT) of f(x,0).

Does it show sharp peaks at multiples of the fundamental frequency tied to 421.3751?

If yes → your lattice is resonating cleanly at that harmonic, supporting the "harmonics of the system" claim.

Bonus: vary the constant slightly (421.3751 ± 0.1) and see if rings destabilize or smooth out — tests robustness.

What do you find?"""

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
    
    print(f"\nTHE NAVIGATOR'S HARMONIC ANALYSIS:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
