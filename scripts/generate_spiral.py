import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import os

# Load data
script_dir = os.path.dirname(os.path.abspath(__file__))
df = pd.read_csv(os.path.join(script_dir, 'lattice-periodic-table.csv'))

# Golden angle
phi = (1 + np.sqrt(5)) / 2
golden_angle = np.pi * (3 - np.sqrt(5))  # ≈ 2.39996 radians

# Calculate positions
df['angle'] = df['AtomicNumber'] * golden_angle
df['radius'] = (df['AsymmetryValue'] - 13.2) * 10  # scale factor
df['x'] = df['radius'] * np.cos(df['angle'])
df['y'] = df['radius'] * np.sin(df['angle'])

# Color by stability
colors = {'Stable': '#00aa00', 'Metastable': '#ffaa00', 'Radioactive': '#aa0000'}
df['color'] = df['Stability'].map(colors)

# Size by valency
df['size'] = (df['ValencyLobes'] + 1) * 20

# Plot
fig, ax = plt.subplots(figsize=(16, 16))
scatter = ax.scatter(df['x'], df['y'], c=df['color'], s=df['size'], alpha=0.7)

# Add element symbols
for idx, row in df.iterrows():
    ax.annotate(row['Symbol'], (row['x'], row['y']), fontsize=8, ha='center')

# Fibonacci spiral overlay
theta = np.linspace(0, 4*np.pi, 1000)
r = np.exp(theta / (2*np.pi) * np.log(phi))
ax.plot(r * np.cos(theta), r * np.sin(theta), 'k--', alpha=0.3, linewidth=1)

ax.set_aspect('equal')
ax.axis('off')
plt.title('Lattice Physics Periodic Table — Phi-Harmonic Spiral', fontsize=16)
plt.savefig(os.path.join(script_dir, 'lattice-periodic-spiral.png'), dpi=300, bbox_inches='tight')
plt.savefig(os.path.join(script_dir, 'lattice-periodic-spiral.svg'), format='svg')
print("Generated: lattice-periodic-spiral.png + .svg")
