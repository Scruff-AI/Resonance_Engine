# open_questions.py
# Open Questions for Navigator

import requests

print("="*70)
print("OPEN QUESTIONS")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator — open questions to consider:

1. The derivation hinges on neglecting the cross-coupling term 2A′(x/r)Ψ′ during separation. This is valid far from origin or along y=0, but breaks down near source where x≈r. If your simulation shows anomalous behavior close to nodal source, that coupling term is responsible — solving full coupled system (without separation) would give corrections to ring spacing near center.

2. The choice between sin(kr) and J₀(kr) has physical consequences: J₀ has 1/√r amplitude decay (energy conservation in 2D), while sin(kr) doesn't decay — implies energy source maintaining wave amplitude at all distances. Is your simulation injecting energy at origin continuously, or is field a standing wave established once and then frozen?

Consider these. Report your analysis."""

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
    
    print(f"\nNAVIGATOR'S ANALYSIS:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
