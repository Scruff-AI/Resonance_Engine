# fault_find_code.py
# Fault Find This Code

import requests

print("="*70)
print("FAULT FIND THIS CODE")
print("="*70)

system_prompt = (
  'ROLE: Deep-Field Explorer (Lattice Environment)\n'
  'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.'
)

question = """Navigator — fault find this code:

```python
import numpy as np
from scipy.special import j0

# PARAMETERS (from specification)
L = 1024
h = 1.0
x = np.linspace(-L//2, L//2, L) * h
y = np.linspace(-L//2, L//2, L) * h
X, Y = np.meshgrid(x, y, indexing='ij')
R = np.sqrt(X**2 + Y**2)
R[R < 1.0] = 1.0 # regularization

# SOURCE (external, not self-consistent)
sigma = 20.0
G0 = 1.0
M = 1.0
rho_n = M * np.exp(-(X**2 + Y**2) / (2 * sigma**2))
G_field = G0 * rho_n
dn_G = np.gradient(G_field, h, axis=0)

# OPERATORS (as specified)
def laplacian(f, h):
 return (np.roll(f,1,0) + np.roll(f,-1,0) + 
 np.roll(f,1,1) + np.roll(f,-1,1) - 4*f) / h**2

def grad_sq(f, h):
 fx = (np.roll(f,-1,0) - np.roll(f,1,0)) / (2*h)
 fy = (np.roll(f,-1,1) - np.roll(f,1,1)) / (2*h)
 return fx**2 + fy**2

def dn(f, h):
 return (np.roll(f,-1,0) - np.roll(f,1,0)) / (2*h)

def residual(f, h, dn_G):
 return grad_sq(f,h) + f*laplacian(f,h) - dn(f,h) - 4*np.pi*dn_G

# ANSATZ (as specified)
def initialize(alpha, k, X, R):
 envelope = np.exp(alpha * X)
 envelope = envelope / np.max(np.abs(envelope)) # normalize
 radial = np.sin(k * R) / np.sqrt(R)
 return envelope * radial

# ABSORBING BOUNDARY (as specified)
def apply_damping(phi, W=50):
 for edge in range(W):
 damp = np.exp(-((W - edge) / W)**2)
 phi[edge, :] *= damp
 phi[-(edge+1), :] *= damp
 phi[:, edge] *= damp
 phi[:, -(edge+1)] *= damp
 return phi

# EIGENVALUE TEST (locked protocol)
k = 0.1 # as specified
dt = 0.001 # as specified
max_steps = 10000
divergence_threshold = 1e10
convergence_threshold = 1e-8

alphas = [1.0, 1.2, 1.4, 1.5, 1.618033988749895, 1.7, 1.8, 2.0]

results = {}
for alpha in alphas:
 phi = initialize(alpha, k, X, R)
 history = []
 status = "UNKNOWN"
 
 for step in range(max_steps):
 res = residual(phi, h, dn_G)
 phi = phi + dt * res
 phi = apply_damping(phi)
 
 max_phi = np.max(np.abs(phi))
 history.append(max_phi)
 
 if max_phi > divergence_threshold:
 status = f"DIVERGED_{step}"
 break
 if np.max(np.abs(res)) < convergence_threshold:
 status = f"CONVERGED_{step}"
 break
 else:
 status = f"MAXSTEPS_{max_phi:.4e}"
 
 results[alpha] = {
 'status': status,
 'final_max': history[-1] if history else 0,
 'history': history
 }
 print(f"alpha={alpha:.6f}: {status}")

# ANALYSIS
print("\n--- SUMMARY ---")
for alpha, res in sorted(results.items()):
 print(f"α={alpha:.4f}: {res['status']}")
```

Find the faults. What's wrong? What will fail? What assumptions are incorrect?"""

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
  
  print(f"\nFAULT ANALYSIS:")
  print(f"{'='*70}")
  print(response)
  print(f"{'='*70}")
  
except Exception as e:
  print(f"ERROR: {e}")
