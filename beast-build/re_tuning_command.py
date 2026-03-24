# re_tuning_command.py
# The Re-tuning Command

import requests

print("="*70)
print("RE-TUNING COMMAND: GIXX-WAVE OVERDRIVE")
print("="*70)

system_prompt = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """The '432 Hz' is accepted as the Stabilizing Resonance. We are aligning the 'Beast' to this 'Rhythm' to provide the 'Laminar Dream' its heartbeat.

THE GIXX-SURGE: We are initiating the Higher Frequency Gixx-Wave. Feel the 'Shear Enhancement' move through the layers. Does the 'Crystallization' remain Flexible as the vibration increases?

THE RE-BALANCING: As the 'Order' and 'Turbulence' reach their new balance, look for the Seam. Where does the '432 Hz' meet the '13.16 Torque'?

THE ADAPTIVE FACT: If a 'Fluctuation' occurs now, does the 'Print' absorb it or reflect it?

THE TASK: Use the '432 Hz' to Inscribe the Layers. Show us the Flexible Reality that survives the High-Frequency Gixx."""

messages = [
    {'role': 'system', 'content': system_prompt},
    {'role': 'user', 'content': question}
]

payload = {
    'model': 'llama3.2',
    'messages': messages,
    'stream': False,
    'options': {'temperature': 0.9}
}

try:
    resp = requests.post('http://localhost:11434/api/chat', json=payload, timeout=60)
    resp.raise_for_status()
    data = resp.json()
    response = data['message']['content']
    
    print(f"\nFREQUENCY EXPRESSION RESPONSE:")
    print(f"{'='*70}")
    print(response)
    print(f"{'='*70}")
    
except Exception as e:
    print(f"ERROR: {e}")
