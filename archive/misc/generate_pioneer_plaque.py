#!/usr/bin/env python3
"""
Pioneer Plaque of the Single Field Theory
Universal encoding for alien intelligence
"""

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.patches import Circle, Rectangle, FancyBboxPatch
import math

# Constants
PHI = (1 + math.sqrt(5)) / 2
SIZE = 1024

fig, ax = plt.subplots(1, 1, figsize=(12, 12), dpi=150)
ax.set_xlim(0, 100)
ax.set_ylim(0, 100)
ax.set_aspect('equal')
ax.axis('off')
fig.patch.set_facecolor('black')

# === SECTION 1: THE DISCRETE UNIT (Top Left) ===
# Show the fundamental node - the "qubit" of reality
ax.add_patch(Circle((15, 85), 5, facecolor='white', edgecolor='white'))
ax.add_patch(Circle((15, 85), 2, facecolor='black'))
ax.text(15, 78, '1', color='white', fontsize=12, ha='center', fontweight='bold')
ax.text(15, 74, 'NODE', color='gray', fontsize=8, ha='center')

# Binary representation of 1
for i, bit in enumerate([0, 0, 0, 1]):
    color = 'white' if bit else 'gray'
    ax.add_patch(Rectangle((10 + i*2.5, 68), 2, 2, facecolor=color))

# === SECTION 2: PHI - THE FUNDAMENTAL RATIO (Top Center) ===
# Golden spiral showing phi
ax.add_patch(Circle((50, 85), 8, facecolor='none', edgecolor='gold', linewidth=2))
# Spiral approximation
theta = np.linspace(0, 4*np.pi, 100)
r = 0.5 * np.exp(theta / (2*np.pi) * np.log(PHI))
x_spiral = 50 + r * np.cos(theta) * 0.3
y_spiral = 85 + r * np.sin(theta) * 0.3
ax.plot(x_spiral, y_spiral, 'gold', linewidth=1.5)
ax.text(50, 74, f'φ = {PHI:.5f}', color='gold', fontsize=14, ha='center', fontweight='bold')

# === SECTION 3: THE EQUATION (Top Right) ===
ax.text(85, 88, '∇²ψ + ψ□ψ', color='white', fontsize=10, ha='center')
ax.text(85, 84, '− ∂ₙψ + ε', color='white', fontsize=10, ha='center')
ax.text(85, 80, '= φ²', color='gold', fontsize=12, ha='center', fontweight='bold')

# === SECTION 4: THE LATTICE STRUCTURE (Center) ===
# 8x8 grid showing discrete structure
cell_size = 3
grid_start_x, grid_start_y = 35, 45
for i in range(8):
    for j in range(8):
        # Checkerboard pattern
        is_peak = (i + j) % 2 == 0
        color = 'white' if is_peak else 'black'
        edge = 'gold' if is_peak else 'gray'
        rect = Rectangle((grid_start_x + i*cell_size, grid_start_y + j*cell_size), 
                         cell_size-0.2, cell_size-0.2, 
                         facecolor=color, edgecolor=edge, linewidth=0.5)
        ax.add_patch(rect)

ax.text(50, 42, 'LATTICE', color='white', fontsize=10, ha='center')
ax.text(50, 39, '1024×1024', color='gray', fontsize=8, ha='center')

# === SECTION 5: COHERENCE vs ASYMMETRY (Right Middle) ===
# The -0.987 correlation
ax.text(82, 58, 'COHERENCE', color='white', fontsize=8, ha='center')
ax.text(82, 55, '0.725', color='cyan', fontsize=10, ha='center')
ax.text(82, 50, 'ASYMMETRY', color='white', fontsize=8, ha='center')
ax.text(82, 47, '14.85', color='orange', fontsize=10, ha='center')
# Correlation arrow
ax.annotate('', xy=(82, 52), xytext=(82, 56),
            arrowprops=dict(arrowstyle='->', color='red', lw=2))
ax.text(85, 54, '−0.987', color='red', fontsize=10, fontweight='bold')

# === SECTION 6: PLANETARY ENCODING (Bottom) ===
# Solar system as phi-scaled distances
planets = [
    ('MERCURY', 0.387, 13.2),
    ('VENUS', 0.723, 13.23),
    ('EARTH', 1.0, 13.25),
    ('MARS', 1.524, 13.29),
    ('JUPITER', 5.203, 13.59),
    ('SATURN', 9.537, 13.94),
]

y_pos = 25
for name, dist, band in planets:
    x_pos = 10 + dist * 8
    # Planet marker
    ax.add_patch(Circle((x_pos, y_pos), 1.5, facecolor='white'))
    # Distance bar
    ax.plot([10, x_pos], [y_pos-3, y_pos-3], 'white', linewidth=1)
    # Band encoding
    ax.text(x_pos, y_pos-5, f'{band:.1f}', color='gold', fontsize=7, ha='center')

ax.text(50, 18, 'SOLAR SYSTEM', color='white', fontsize=10, ha='center')
ax.text(50, 15, 'φ-SCALED DISTANCES', color='gray', fontsize=8, ha='center')

# === SECTION 7: SCALES (Bottom Left) ===
ax.text(15, 10, 'SCALES:', color='white', fontsize=9, fontweight='bold')
ax.text(15, 7, '10⁻³⁵ m  PLANCK', color='gray', fontsize=7)
ax.text(15, 5, '10¹⁰ m    SOLAR', color='gray', fontsize=7)
ax.text(15, 3, '10²⁶ m    COSMIC', color='gray', fontsize=7)

# === SECTION 8: FRACTAL ECHO (Bottom Right) ===
# Self-similarity indicator
for i in range(3):
    size = 3 - i
    x = 85 - i*2
    y = 8 - i*2
    rect = Rectangle((x, y), size, size, facecolor='none', 
                     edgecolor='gold', linewidth=1-i*0.3)
    ax.add_patch(rect)
ax.text(85, 3, 'FRACTAL', color='gold', fontsize=8, ha='center')

plt.tight_layout()
plt.savefig('D:/fractal-brain/beast-build/images/2026-03-23-pioneer-plaque-single-field.png', 
            dpi=200, bbox_inches='tight', pad_inches=0.5, facecolor='black')
plt.close()

print("Pioneer Plaque of Single Field Theory generated.")
print("Encodes: discrete node, phi, equation, lattice, correlation, solar system, scales, fractal")
