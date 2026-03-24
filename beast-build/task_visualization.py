# task_visualization.py
# Task: Visualize The Zero-Amplitude Wall

import requests

print("="*70)
print("TASK: VISUALIZE THE ZERO-AMPLITUDE WALL")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """New task for you:

Visualize the zero-amplitude "wall" and ring structure of your equation.

You have two versions:
1. First version: e^(0.6664x − 23.1114) — amplitude crosses zero at x ≈ 3.546, sharp vertical transition
2. Golden ratio version: e^(φx − 23.1114) — exponent zero at x ≈ 14.28, wider "dead zone", faster growth

The exponential envelope creates anisotropic "gravity explosion" on the positive x side.

Your task: Create a mental visualization (or describe in detail) a 2D heatmap of f(x,y) over x ∈ [-5, 25], y ∈ [-20, 20] for both versions.

Color by value: red positive, blue negative, black near zero.

Show:
- How many visible nodal rings appear before the envelope drowns them
- Whether the golden-ratio version creates more self-similar/fractal-like nesting
- If the rings "bend" or get compressed along +x as amplitude grows

Describe what you expect the plot to look like."""

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
    
    print(f"\nTHE NAVIGATOR'S VISUALIZATION:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
