# Render etch images
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

NX = 512
NY = 512

def load_etch(filename):
    with open(filename, 'rb') as f:
        rho = np.frombuffer(f.read(NX * NY * 4), dtype=np.float32).reshape(NY, NX)
        ux = np.frombuffer(f.read(NX * NY * 4), dtype=np.float32).reshape(NY, NX)
        uy = np.frombuffer(f.read(NX * NY * 4), dtype=np.float32).reshape(NY, NX)
    return rho, ux, uy

def render_etch(filename, output_name):
    rho, ux, uy = load_etch(filename)
    
    # Velocity magnitude
    u_mag = np.sqrt(ux**2 + uy**2)
    
    # Vorticity (curl of velocity)
    dux_dy = np.gradient(ux, axis=0)
    duy_dx = np.gradient(uy, axis=1)
    vorticity = duy_dx - dux_dy
    
    fig, axes = plt.subplots(1, 3, figsize=(15, 5))
    
    # Density
    im0 = axes[0].imshow(rho, cmap='viridis', origin='lower')
    axes[0].set_title('Density')
    axes[0].axis('off')
    plt.colorbar(im0, ax=axes[0], fraction=0.046)
    
    # Velocity magnitude
    im1 = axes[1].imshow(u_mag, cmap='hot', origin='lower', vmin=0, vmax=np.percentile(u_mag, 99))
    axes[1].set_title('Velocity Magnitude')
    axes[1].axis('off')
    plt.colorbar(im1, ax=axes[1], fraction=0.046)
    
    # Vorticity
    vmax = np.percentile(np.abs(vorticity), 99)
    im2 = axes[2].imshow(vorticity, cmap='RdBu_r', origin='lower', vmin=-vmax, vmax=vmax)
    axes[2].set_title('Vorticity')
    axes[2].axis('off')
    plt.colorbar(im2, ax=axes[2], fraction=0.046)
    
    plt.tight_layout()
    plt.savefig(output_name, dpi=150, bbox_inches='tight')
    print(f"Saved: {output_name}")
    plt.close()
    
    return rho, u_mag, vorticity

# Render etch 1 (10k) and etch 49 (490k)
render_etch(r'D:\fractal-brain\beast-build\etch_00010000.bin', 'etch_10k.png')
render_etch(r'D:\fractal-brain\beast-build\etch_00490000.bin', 'etch_490k.png')

print("\nDone. Compare etch_10k.png vs etch_490k.png")
