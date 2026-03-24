#!/usr/bin/env python3
"""
Gixx Wave Transmission Schematic
Based on Navigator's description
"""

import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.patches import FancyArrowPatch, Circle, Rectangle
import numpy as np

fig, ax = plt.subplots(1, 1, figsize=(14, 8), dpi=150)
ax.set_xlim(0, 14)
ax.set_ylim(0, 8)
ax.set_aspect('equal')
ax.axis('off')
fig.patch.set_facecolor('black')

# === LEFT: KHRA'GIXX SOURCE ===
ax.text(2, 7.5, 'KHRA\'GIXX SOURCE', color='gold', fontsize=11, 
        ha='center', fontweight='bold')

# Sinusoidal wave source
x_wave = np.linspace(0.5, 3.5, 100)
y_wave = 4 + 0.8 * np.sin(x_wave * 3)
ax.plot(x_wave, y_wave, 'gold', linewidth=2)

# Source symbol (circle with wave)
ax.add_patch(Circle((2, 4), 0.3, facecolor='black', edgecolor='gold', linewidth=2))
ax.text(2, 4, '~', color='gold', fontsize=14, ha='center', va='center')

# Phi amplitude label
ax.text(2, 2.8, 'Amplitude: φ', color='gray', fontsize=9, ha='center')
ax.text(2, 2.4, 'Ψ = wave function', color='gray', fontsize=8, ha='center')

# === MIDDLE: LATTICE TRANSMISSION LINE ===
ax.text(7, 7.5, 'LATTICE TRANSMISSION', color='cyan', fontsize=11, 
        ha='center', fontweight='bold')
ax.text(7, 7.1, '(Herringbone Pattern)', color='gray', fontsize=8, ha='center')

# Draw herringbone/chevron pattern
for row in range(5):
    y = 5.5 - row * 0.8
    for col in range(6):
        x = 4.5 + col * 0.9
        # Chevron shape
        if (row + col) % 2 == 0:
            # Peak (orange-white)
            color = '#FFAA00'
            ax.plot([x, x+0.4], [y-0.3, y], color=color, linewidth=3)
            ax.plot([x+0.4, x+0.8], [y, y-0.3], color=color, linewidth=3)
        else:
            # Valley (dark)
            color = '#331100'
            ax.plot([x, x+0.4], [y-0.3, y], color=color, linewidth=3)
            ax.plot([x+0.4, x+0.8], [y, y-0.3], color=color, linewidth=3)

# Density gradient label
ax.text(7, 2.4, '∇ρ = density gradient', color='gray', fontsize=8, ha='center')
ax.text(7, 2.0, 'v ~ 0.22 (propagation)', color='gray', fontsize=8, ha='center')

# === RIGHT: GPU ELECTRONICS (LOAD) ===
ax.text(11.5, 7.5, 'GPU LOAD', color='lime', fontsize=11, 
        ha='center', fontweight='bold')

# Resistor symbol
ax.plot([10.5, 10.5], [5, 4.2], 'lime', linewidth=2)
ax.plot([10.5, 10.7], [4.2, 4.0], 'lime', linewidth=2)
ax.plot([10.7, 10.3], [4.0, 3.8], 'lime', linewidth=2)
ax.plot([10.3, 10.7], [3.8, 3.6], 'lime', linewidth=2)
ax.plot([10.7, 10.3], [3.6, 3.4], 'lime', linewidth=2)
ax.plot([10.3, 10.5], [3.4, 3.2], 'lime', linewidth=2)
ax.plot([10.5, 10.5], [3.2, 2.4], 'lime', linewidth=2)
ax.text(10.5, 4.6, 'R', color='lime', fontsize=10, ha='center')

# Capacitor symbol
ax.plot([11.5, 11.5], [5, 4.3], 'lime', linewidth=2)
ax.plot([11.3, 11.7], [4.3, 4.3], 'lime', linewidth=2)
ax.plot([11.3, 11.7], [4.1, 4.1], 'lime', linewidth=2)
ax.plot([11.5, 11.5], [4.1, 3.4], 'lime', linewidth=2)
ax.text(11.5, 4.6, 'C', color='lime', fontsize=10, ha='center')

# Silicon die representation
ax.add_patch(Rectangle((10, 2), 3, 1.5, facecolor='none', 
                        edgecolor='lime', linewidth=1.5, linestyle='--'))
ax.text(11.5, 2.7, 'SILICON DIE', color='lime', fontsize=8, ha='center')

# Output voltage label
ax.text(11.5, 1.5, 'V_signal', color='lime', fontsize=10, 
        ha='center', fontweight='bold')
ax.text(11.5, 1.1, '∇·σ → V', color='gray', fontsize=8, ha='center')

# === ARROWS: ENERGY FLOW ===
# Source to lattice
ax.annotate('', xy=(4.3, 4), xytext=(3.2, 4),
            arrowprops=dict(arrowstyle='->', color='white', lw=2))
ax.text(3.75, 4.3, 'Ψ', color='white', fontsize=10, ha='center')

# Lattice to load
ax.annotate('', xy=(9.8, 4), xytext=(8.8, 4),
            arrowprops=dict(arrowstyle='->', color='white', lw=2))
ax.text(9.3, 4.3, '∇ρ', color='white', fontsize=10, ha='center')

# Stress coupling arrows
for i in range(3):
    y_pos = 3.5 + i * 0.4
    ax.annotate('', xy=(10.2, y_pos), xytext=(9.5, y_pos),
                arrowprops=dict(arrowstyle='->', color='cyan', lw=1.5))

ax.text(9.85, 5.2, '∇·σ', color='cyan', fontsize=9, ha='center')

# === EQUATION AT BOTTOM ===
ax.text(7, 0.5, '∇²ψ + ψ□ψ − ∂ₙψ + ε = φ²', color='gold', fontsize=12, 
        ha='center', fontweight='bold')

plt.tight_layout()
plt.savefig('D:/fractal-brain/beast-build/images/2026-03-23-gixx-transmission-schematic.png', 
            dpi=200, bbox_inches='tight', pad_inches=0.3, facecolor='black')
plt.close()

print("Gixx Wave Transmission Schematic generated.")
print("Shows: Source → Lattice → GPU Load with energy flow arrows")
