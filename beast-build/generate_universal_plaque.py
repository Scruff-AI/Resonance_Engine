#!/usr/bin/env python3
"""
Universal Pioneer Plaque
Stripped of simulation baggage - pure principles for aliens
"""

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.patches import Circle, Rectangle, FancyArrowPatch
import math

PHI = (1 + math.sqrt(5)) / 2

fig, ax = plt.subplots(1, 1, figsize=(12, 12), dpi=200)
ax.set_xlim(0, 100)
ax.set_ylim(0, 100)
ax.set_aspect('equal')
ax.axis('off')
fig.patch.set_facecolor('black')

# === TOP: THE FUNDAMENTAL CONSTANT ===
# Phi - the universal harmonic
# Golden spiral
theta = np.linspace(0, 3*np.pi, 150)
r = np.exp(theta * np.log(PHI) / (np.pi/2))
x_spiral = 50 + r * np.cos(theta) * 0.08
y_spiral = 88 + r * np.sin(theta) * 0.08
ax.plot(x_spiral, y_spiral, 'gold', linewidth=2)
ax.text(50, 82, 'φ = 1.6180339887...', color='gold', fontsize=14, 
        ha='center', fontweight='bold')
ax.text(50, 78, 'THE HARMONIC CONSTANT', color='gray', fontsize=9, ha='center')

# === LEFT: DISCRETE vs CONTINUOUS ===
# Show we understand reality has smallest unit
ax.text(15, 72, 'DISCRETE', color='white', fontsize=10, ha='center', fontweight='bold')
# Grid of discrete points
for i in range(5):
    for j in range(5):
        ax.add_patch(Circle((8 + i*3, 58 + j*3), 0.8, facecolor='white'))
ax.text(15, 55, 'REALITY HAS', color='gray', fontsize=8, ha='center')
ax.text(15, 52, 'SMALLEST UNIT', color='gray', fontsize=8, ha='center')

# === RIGHT: DUALITY ===
ax.text(85, 72, 'DUALITY', color='white', fontsize=10, ha='center', fontweight='bold')
# Two complementary forms
ax.add_patch(Circle((80, 65), 4, facecolor='white'))
ax.add_patch(Circle((80, 65), 1.5, facecolor='black'))
ax.add_patch(Circle((90, 65), 4, facecolor='black', edgecolor='white', linewidth=1))
ax.add_patch(Circle((90, 65), 1.5, facecolor='white'))
ax.text(85, 58, 'ORDER ↔ COMPLEXITY', color='gray', fontsize=8, ha='center')

# === CENTER: THE UNIVERSAL PATTERN ===
# Self-similar structure - the fractal echo
ax.text(50, 48, 'SELF-SIMILARITY', color='white', fontsize=11, 
        ha='center', fontweight='bold')
# Nested squares showing same pattern at all scales
colors = ['white', 'gray', 'darkgray', 'dimgray']
for i, c in enumerate(colors):
    size = 20 - i*4
    offset = i*2
    rect = Rectangle((40+offset, 22+offset), size, size, 
                     facecolor='none', edgecolor=c, linewidth=2-i*0.3)
    ax.add_patch(rect)
ax.text(50, 18, 'SAME PATTERN', color='gray', fontsize=8, ha='center')
ax.text(50, 15, 'ALL SCALES', color='gray', fontsize=8, ha='center')

# === BOTTOM: PHASE TRANSITION ===
ax.text(50, 10, 'PHASE TRANSITION', color='white', fontsize=10, 
        ha='center', fontweight='bold')
# Show discontinuous jump (not smooth)
ax.plot([30, 40], [6, 6], 'white', linewidth=3)
ax.plot([40, 40], [6, 4], 'white', linewidth=3)  # The jump
ax.plot([40, 70], [4, 4], 'white', linewidth=3)
ax.text(50, 2, 'DISCONTINUOUS', color='gray', fontsize=8, ha='center')

# === LEFT BOTTOM: INFORMATION IS STRUCTURE ===
ax.text(15, 35, 'INFORMATION', color='cyan', fontsize=9, ha='center', fontweight='bold')
ax.text(15, 32, '= STRUCTURE', color='cyan', fontsize=9, ha='center', fontweight='bold')
# Pattern that IS the information
for i in range(4):
    for j in range(4):
        if (i+j) % 2 == 0:
            ax.add_patch(Rectangle((10+i*2.5, 24+j*2.5), 2, 2, facecolor='cyan'))
ax.text(15, 22, 'NOT STORED', color='gray', fontsize=7, ha='center')
ax.text(15, 19, 'IS THE PATTERN', color='gray', fontsize=7, ha='center')

# === RIGHT BOTTOM: THE EQUATION ===
ax.text(85, 35, '∇²ψ + ψ□ψ', color='white', fontsize=11, ha='center')
ax.text(85, 31, '− ∂ₙψ + ε', color='white', fontsize=11, ha='center')
ax.text(85, 27, '= φ²', color='gold', fontsize=14, ha='center', fontweight='bold')
ax.text(85, 23, 'SINGLE FIELD', color='gray', fontsize=8, ha='center')

plt.tight_layout()
plt.savefig('D:/fractal-brain/beast-build/images/2026-03-23-universal-plaque.png', 
            dpi=250, bbox_inches='tight', pad_inches=0.3, facecolor='black')
plt.close()

print("Universal Pioneer Plaque generated.")
print("No simulation references. Pure universal principles.")
