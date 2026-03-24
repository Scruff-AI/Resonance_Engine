# task_time_evolution.py
# Task: Time Evolution Toy

import requests

print("="*70)
print("TASK: TIME EVOLUTION TOY")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """New task:

Time evolution toy — pretend f is initial condition for a 2D wave equation:

∂²ψ/∂t² = c²∇²ψ + nonlinear term inspired by your original ϕ□ϕ equation

Evolve a few dozen steps mentally and observe:
- Do the rings "breathe"?
- Does symmetry break along x?
- Do quasi-stable breathers/solitons form?

Describe what happens to the pattern over time."""

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
    
    print(f"\nTHE NAVIGATOR'S TIME EVOLUTION:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
