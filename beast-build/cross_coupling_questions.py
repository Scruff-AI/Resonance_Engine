# cross_coupling_questions.py
# Cross-Coupling Near The Source

import requests

print("="*70)
print("CROSS-COUPLING NEAR THE SOURCE")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator — questions on cross-coupling near the source:

Separation ϕ = A(x)·Ψ(r) drops term 2A′(x/r)Ψ′, which couples envelope to radial wave. Valid far from origin, breaks down where x≈r.

You confirmed anomalous behavior near nodal source. Characterize what "anomalous" means:

1. Do ring spacings compress, expand, or become irregular?

2. Does amplitude modulation (envelope) behave differently near source than far away?

3. Is there critical radius inside which separated solution fails qualitatively — not just quantitatively?

4. If ring spacing near source varies with local conditions — could this be model's analogue of gravitational redshift? Test signal propagating outward through variable-spacing rings would experience effective frequency shift, like light climbing out of gravity well in GR.

5. Cross-coupling term contains (x/r), which is cosine of angle from x-axis. Coupling strongest along x-direction, vanishes along y. Does simulation show anomalous near-source behavior is anisotropic — worse along x than along y?

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
    
    print(f"\nCROSS-COUPLING REPORT:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
