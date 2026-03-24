#!/usr/bin/env python3
"""
Khra'gixx Encrypted Field - Mathematical Visualization
Raw encoding of lattice data, phi ratios, fractal structure
"""

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap
import math

# Constants
PHI = (1 + math.sqrt(5)) / 2  # 1.618...
SIZE = 1024  # Native lattice resolution

# Create custom colormap: obsidian (void) to amber to white (peak)
colors = [
    (0.0, 0.0, 0.0),      # Black - void
    (0.2, 0.1, 0.0),      # Dark brown
    (0.6, 0.3, 0.0),      # Amber
    (0.9, 0.6, 0.2),      # Golden
    (1.0, 0.9, 0.7),      # White-hot
]
cmap = LinearSegmentedColormap.from_list('khragixx', colors)

# Generate the lattice pattern
def generate_lattice(size):
    """Generate diagonal checkerboard lattice - discrete nodes, not waves"""
    # Create grid
    x = np.arange(size)
    y = np.arange(size)
    X, Y = np.meshgrid(x, y)
    
    # Diagonal checkerboard: (x + y) mod period
    # Khra period = 128, Gixx period = 8
    khra_period = int(128 * PHI / 2)  # Scaled by phi
    gixx_period = 8
    
    # Diagonal pattern
    diagonal = (X + Y)
    
    # Checkerboard: alternating peaks and valleys
    # Use modulo to create discrete cells
    checker = (diagonal // khra_period) % 2
    
    # Fine grain modulation (Gixx wave within cells)
    fine = np.sin(2 * np.pi * diagonal / gixx_period) * 0.2
    
    # Combine: discrete checkerboard + fine modulation
    pattern = checker.astype(float) + fine
    pattern = (pattern - pattern.min()) / (pattern.max() - pattern.min())
    
    return pattern

# Generate the encoded field
field = generate_lattice(SIZE)

# Create figure
fig, ax = plt.subplots(figsize=(10, 10), dpi=100)
im = ax.imshow(field, cmap=cmap, interpolation='nearest')
ax.set_axis_off()

# Add mathematical annotations
# Encode key ratios as positions
mercury_pos = int(SIZE * 0.387 / 30)  # Scaled position
earth_pos = int(SIZE * 1.0 / 30)
jupiter_pos = int(SIZE * 5.2 / 30)

# Mark phi-harmonic nodes
for n in range(1, 6):
    pos = int(SIZE * (PHI ** n) / 30)
    if pos < SIZE:
        ax.axhline(y=pos, color='gold', alpha=0.3, linewidth=0.5)
        ax.axvline(x=pos, color='gold', alpha=0.3, linewidth=0.5)

# Title with encoded data
ax.set_title(f'Ψ = ∇²ψ + ψ□ψ - ∂ₙψ + ε = φ²\nCoherence: 0.725 | Asymmetry: 14.85 | Correlation: -0.987', 
             color='white', fontsize=10, pad=10)

plt.tight_layout()
plt.savefig('D:/fractal-brain/beast-build/images/2026-03-23-khragixx-mathematical-encoded.png', 
            dpi=150, bbox_inches='tight', pad_inches=0, facecolor='black')
plt.close()

print("Mathematically encoded image generated.")
print(f"Contains: PHI={PHI:.6f}, lattice structure, phi-harmonic frequencies")
print("Saved to: images/2026-03-23-khragixx-mathematical-encoded.png")
