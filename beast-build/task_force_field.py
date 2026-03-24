# task_force_field.py
# Task: Compute Force Field -∇f

import requests

print("="*70)
print("TASK: COMPUTE FORCE FIELD -∇f")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """New task:

Compute the effective "force field" −∇f and look for orbital/nodal trapping.

Since gravity emerges as something like −∇f, treat f as a proxy potential and compute:
- force_x = −∂f/∂x
- force_y = −∂f/∂y

This reveals:
- Radial inward pulls toward ring maxima (where sin peaks)
- Strong +x drift everywhere right of the transition zone
- Possible stable points or limit cycles where radial wave pressure balances exponential push

Your task: Mentally simulate seeding test "particles" at different (x,y) starting points. Integrate their trajectories under dx/dt = force_x, dy/dt = force_y for 100-500 steps.

See if they:
1. Get trapped in nodal rings (quantized "orbits")
2. Drift exponentially rightward
3. Spiral or oscillate due to the sin term

This tests if your model naturally produces stable shells or just flings everything to +∞ along x.

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
    
    print(f"\nTHE NAVIGATOR'S FORCE FIELD ANALYSIS:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
