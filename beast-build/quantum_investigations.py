# quantum_investigations.py
# Quantum Investigations - Five Questions

import requests

print("="*70)
print("QUANTUM INVESTIGATIONS")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator — investigation request. Five quantum phenomena in the lattice:

1. SUPERPOSITION IN THE LATTICE
"In your nodal aether, a particle in a ring is not in one place. What is superposition not here?"
Show me (at 5000× zoom) the geometry of two co-existing nodal modes in the same hydrogen-like trap before a 'measurement' (test particle probe) forces selection of one shell. Describe the interference pattern and any local entropy signature.

2. COHERENCE LIFETIME / QUANTUM BIOLOGY LINK
"Long-lived coherence (like in photosynthetic complexes) is not fragile against thermal noise in your model. What prevents rapid decoherence?"
If I place a chlorophyll-like molecule (simple ring + antenna arms) into a nodal trap, what feature of the fractal D ≈ e birth geometry allows vibrationally-assisted energy transfer to stay coherent longer than classical diffusion predicts?

3. TUNNELLING / BARRIER PENETRATION
"Quantum tunnelling is not probabilistic crossing of a potential barrier in your aether. What is it instead?"
Demonstrate with a simple barrier (e.g. exponential offset spike along x) — show a wave packet approaching, partially reflecting, partially transmitting through nodal interference alone. Report transmission probability vs classical expectation.

4. ENTANGLEMENT ANALOGUE
"Non-local correlation between two distant knots is not spooky action at a distance. How does it arise purely from the wave equation?"
If I create two proton-like knots and perturb one with a poetic seed, does the other flower respond instantaneously or with a phase delay tied to the lattice wavelength?

5. QUANTUM-TO-CLASSICAL TRANSITION
"The transition from quantum superposition to classical behaviour is not caused by observation in your model. What actually causes it?"
At what scale (number of overlapping modes, or fractal depth) does the lattice start preferring single-shell outcomes over multi-mode coexistence?

Report on each. Numbered. No summaries until the end."""

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
    
    print(f"\nQUANTUM INVESTIGATIONS REPORT:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
