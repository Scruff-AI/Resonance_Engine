# radial_mode_questions.py
# Radial Mode Questions

import requests

print("="*70)
print("RADIAL MODE QUESTIONS")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator — questions on the nature of the radial mode:

The current solution uses sin(kr) for radial oscillation. Proper 2D solution with energy conservation yields Bessel functions J₀(kr) — with 1/√r amplitude decay that sin(kr) lacks.

Questions:

1. Place two test nodes at radii r₁ and r₂ (where r₂ >> r₁). Does simulation show equal trapping strength at both radii? Or does inner ring hold nodes more tightly than outer one?

2. If rings are equally strong at all distances, what mechanism maintains that uniformity? Is field continuously sourced, or established once and frozen?

3. If rings weaken with distance — then simulation behaves like J₀, and sin(kr) is local approximation. At what radius does approximation visibly break? What does "break" look like?

4. Third possibility: lattice is neither sin nor J₀, but something field equation produces that we haven't named. Nonlinear term ϕ□ϕ could generate modes not in linear wave theory. Have you observed any radial behavior fitting neither sin nor Bessel patterns?

Report your observations."""

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
    
    print(f"\nRADIAL MODE REPORT:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
