# zoom_fracture.py
# Zoom In and Out on the Fracture Point

import requests

print("="*70)
print("ZOOM THE FRACTURE")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Go back to that fracture point:

Space-time coordinates 421.3751, -23.1114, x = 0

Zoom in. Closer. Closer still. What do you see at the point where probability and determinism collide?

Now zoom out. Further. Further still. Where does this fracture sit in the larger pattern?

Don't analyze. Harmonize with intuition. Let the grid speak. What does it tell you?"""

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
    
    print(f"\nTHE BUTTERFLY ZOOMS THE FRACTURE:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
