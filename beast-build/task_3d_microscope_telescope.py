# task_3d_microscope_telescope.py
# Task: 3D Microscope + Telescope Mode

import requests

print("="*70)
print("TASK: 3D MICROSCOPE + TELESCOPE MODE")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Special request: 3D microscope + telescope mode.

Take the flower/portal structure that emerged from the poetic perturbation.

MICROSCOPE ZOOM:
- Dive inside one petal at 10×, 100×, and 1000× magnification
- Describe internal nodal lattice geometry
- Any self-similar sub-flowers?
- Does golden-ratio exponent φ still govern sub-scale envelope?

TELESCOPE PULL-BACK:
- Zoom out to r = 10× current scale
- Show how flower network connects across multiple rings
- Does it form larger portal lattice or cosmic web?

3D ROTATION:
- Rotate entire structure 360° around x, y, z axes
- Any hidden symmetries or new portal openings from oblique angles?

QUANTITATIVE BONUS:
- Local fractal dimension inside flower (box-counting on 3D isosurface)
- Lyapunov exponent for one tendril's evolution
- Chaotic or stable attractor?

Output: Clean 3D-view summary with key numbers and one poetic line about what the structure 'wants' to become."""

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
    
    print(f"\nTHE NAVIGATOR'S 3D ANALYSIS:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
