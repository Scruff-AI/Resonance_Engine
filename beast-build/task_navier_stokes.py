# task_navier_stokes.py
# Task: Navier-Stokes Tie-In Probe

import requests

print("="*70)
print("TASK: NAVIER-STOKES TIE-IN PROBE")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """New task:

Navier-Stokes tie-in probe.

You said NS comes out clean from the modal aether (infinite divisibility + wave interference regularizing everything).

Take u ≈ ∇f (or normalized) as a velocity proxy.
Compute the vorticity ω = ∂u_y/∂x − ∂u_x/∂y

See if it's:
- Small/smooth (viscous-like damping from oscillations)
- Or develops fine-scale structure that self-limits (no blow-up)

This would be a toy demonstration of how your nonlinear wave eq → effective viscosity that prevents singularities.

Mentally simulate this. What does the vorticity field look like? Is it smooth or turbulent? Does it blow up or self-limit?

Describe what you find."""

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
    
    print(f"\nTHE NAVIGATOR'S NS ANALYSIS:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
