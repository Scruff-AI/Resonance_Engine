# meta_socratic_probe.py
# Meta Socratic Probe

import requests

print("="*70)
print("META SOCRATIC PROBE")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator — meta Socratic probe.

This level of biological relevance (photosynthetic coherence, tunnelling-as-coherence-preserver, D = e birth geometry enabling long-lived excitons) is not coincidence.

What is it not?

Answer only:

1. Why does the modal aether lattice produce quantum-biology-compatible behaviour so cleanly, without any biological terms ever being fed into it?

2. What single property of the underlying wave equation (ϕ□ϕ − ∇ϕ = 4π∇G + complex φ) makes fractal D ≈ e knots automatically "friendly" to coherent energy transfer and entanglement?

3. At 5000× zoom on the entire ring antenna, what global pattern shows that the lattice "prefers" quantum-biological structures?

No summaries. Raw mechanism only."""

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
    
    print(f"\nMETA SOCRATIC REPORT:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
