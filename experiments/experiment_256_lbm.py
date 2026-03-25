#!/usr/bin/env python3
"""
Experimental 256×256 LBM simulator
Test if fluid dynamics works at small scale
"""

import struct
import numpy as np
import time

class SimpleLBM:
    """Simple D2Q9 Lattice Boltzmann Method simulator."""
    
    def __init__(self, nx=256, ny=256):
        self.nx = nx
        self.ny = ny
        self.q = 9
        
        # D2Q9 parameters
        self.w = np.array([4/9, 1/9, 1/9, 1/9, 1/9, 1/36, 1/36, 1/36, 1/36], dtype=np.float32)
        self.ex = np.array([0, 1, 0, -1, 0, 1, -1, -1, 1], dtype=np.int32)
        self.ey = np.array([0, 0, 1, 0, -1, 1, 1, -1, -1], dtype=np.int32)
        
        # Distribution functions
        self.f = np.zeros((self.q, self.ny, self.nx), dtype=np.float32)
        self.f_new = np.zeros((self.q, self.ny, self.nx), dtype=np.float32)
        
        # Macroscopic variables
        self.rho = np.ones((self.ny, self.nx), dtype=np.float32)
        self.ux = np.zeros((self.ny, self.nx), dtype=np.float32)
        self.uy = np.zeros((self.ny, self.nx), dtype=np.float32)
        
        # Relaxation parameter (tau = 1/omega)
        self.omega = 1.0  # tau = 1.0, nu = 1/6
        
        print(f"Initialized LBM: {nx}×{nx}, omega={self.omega}")
    
    def load_brain_state(self, filepath):
        """Load brain state from file."""
        print(f"Loading brain state: {filepath}")
        
        with open(filepath, 'rb') as f:
            # Read and verify header
            header = f.read(16)
            magic, nx, ny, q = struct.unpack('IIII', header)
            
            if magic != 0x4D424C46:
                print(f"  [ERROR] Wrong magic: 0x{magic:08X}")
                return False
            
            if nx != self.nx or ny != self.ny:
                print(f"  [ERROR] Size mismatch: {nx}×{ny} != {self.nx}×{self.ny}")
                return False
            
            if q != self.q:
                print(f"  [ERROR] Q mismatch: {q} != {self.q}")
                return False
            
            # Read data
            data = np.frombuffer(f.read(), dtype=np.float32)
            data = data.reshape(self.q, self.ny, self.nx)
            
            # Copy to f
            self.f = data.copy()
            
            # Recompute macroscopic variables
            self.compute_macroscopic()
            
            print(f"  Loaded successfully")
            print(f"  Mean density: {self.rho.mean():.6f}")
            print(f"  Max speed: {np.sqrt(self.ux**2 + self.uy**2).max():.2e}")
            
            return True
    
    def compute_macroscopic(self):
        """Compute macroscopic variables from distribution functions."""
        self.rho = np.sum(self.f, axis=0)
        
        # Avoid division by zero
        rho_safe = np.where(self.rho > 1e-10, self.rho, 1.0)
        
        self.ux = np.zeros_like(self.rho)
        self.uy = np.zeros_like(self.rho)
        
        for i in range(self.q):
            self.ux += self.ex[i] * self.f[i]
            self.uy += self.ey[i] * self.f[i]
        
        self.ux /= rho_safe
        self.uy /= rho_safe
    
    def equilibrium(self, rho, ux, uy):
        """Compute equilibrium distribution function."""
        f_eq = np.zeros((self.q, self.ny, self.nx), dtype=np.float32)
        
        for i in range(self.q):
            eu = self.ex[i] * ux + self.ey[i] * uy
            u2 = ux**2 + uy**2
            f_eq[i] = rho * self.w[i] * (1 + 3*eu + 4.5*eu**2 - 1.5*u2)
        
        return f_eq
    
    def collide_and_stream(self):
        """One LBM step: collide and stream."""
        # Compute equilibrium
        f_eq = self.equilibrium(self.rho, self.ux, self.uy)
        
        # Collision: BGK operator
        for i in range(self.q):
            self.f_new[i] = self.f[i] - self.omega * (self.f[i] - f_eq[i])
        
        # Stream (periodic boundaries)
        for i in range(self.q):
            # Shift distribution i by (ex[i], ey[i])
            self.f[i] = np.roll(self.f_new[i], (self.ey[i], self.ex[i]), axis=(0, 1))
        
        # Update macroscopic variables
        self.compute_macroscopic()
    
    def add_perturbation(self):
        """Add a simple perturbation to create some motion."""
        center_x = self.nx // 2
        center_y = self.ny // 2
        radius = min(self.nx, self.ny) // 10
        
        # Create a circular velocity field
        for y in range(self.ny):
            for x in range(self.nx):
                dx = x - center_x
                dy = y - center_y
                dist2 = dx*dx + dy*dy
                
                if dist2 < radius*radius:
                    self.ux[y, x] = 0.01 * dy / radius
                    self.uy[y, x] = -0.01 * dx / radius
        
        # Update distribution functions to match new velocity
        f_eq = self.equilibrium(self.rho, self.ux, self.uy)
        for i in range(self.q):
            self.f[i] = f_eq[i]
        
        print(f"Added perturbation: vortex at ({center_x}, {center_y})")
    
    def run(self, steps=100, verbose=True):
        """Run simulation for given number of steps."""
        print(f"\nRunning {steps} LBM steps...")
        
        start_time = time.time()
        
        energies = []
        max_speeds = []
        
        for step in range(steps):
            self.collide_and_stream()
            
            if step % 10 == 0 or step == steps - 1:
                # Compute kinetic energy
                speed2 = self.ux**2 + self.uy**2
                energy = np.mean(0.5 * self.rho * speed2)
                max_speed = np.sqrt(speed2).max()
                
                energies.append(energy)
                max_speeds.append(max_speed)
                
                if verbose and step % 50 == 0:
                    print(f"  Step {step:4d}: energy={energy:.2e}, max speed={max_speed:.2e}")
        
        elapsed = time.time() - start_time
        print(f"Completed {steps} steps in {elapsed:.2f}s ({steps/elapsed:.1f} steps/s)")
        
        return energies, max_speeds
    
    def analyze(self):
        """Analyze simulation results."""
        print("\n=== Analysis ===")
        
        # Compute statistics
        speed = np.sqrt(self.ux**2 + self.uy**2)
        
        print(f"Density: min={self.rho.min():.6f}, max={self.rho.max():.6f}, mean={self.rho.mean():.6f}")
        print(f"Speed: min={speed.min():.2e}, max={speed.max():.2e}, mean={speed.mean():.2e}")
        
        # Check conservation
        total_mass = np.sum(self.rho)
        print(f"Total mass: {total_mass:.6f}")
        
        # Check for patterns
        row_variation = np.std(self.rho, axis=1).mean()
        col_variation = np.std(self.rho, axis=0).mean()
        print(f"Spatial variation: row={row_variation:.6f}, col={col_variation:.6f}")
        
        if row_variation > 0.001 or col_variation > 0.001:
            print("[NOTE] Significant spatial patterns detected")
        else:
            print("[NOTE] Uniform field (no patterns)")

def main():
    print("=== Experimental 256×256 LBM Test ===")
    print("Testing if fluid dynamics works at small scale")
    print("="*50)
    
    # Test 1: Create fresh simulation
    print("\n[TEST 1] Fresh 256×256 simulation")
    lbm1 = SimpleLBM(256, 256)
    lbm1.add_perturbation()
    energies1, speeds1 = lbm1.run(100, verbose=True)
    lbm1.analyze()
    
    # Test 2: Load 256×256 brain state
    print("\n" + "="*50)
    print("[TEST 2] Load 256×256 brain state")
    lbm2 = SimpleLBM(256, 256)
    
    brain_state = "harmonic_brain_states\\build_256x256\\f_state_post_relax.bin"
    if lbm2.load_brain_state(brain_state):
        print("\nRunning simulation with loaded state...")
        energies2, speeds2 = lbm2.run(100, verbose=True)
        lbm2.analyze()
        
        # Compare with fresh simulation
        print("\n" + "="*50)
        print("[COMPARISON] Fresh vs Loaded")
        print(f"Final energy - Fresh: {energies1[-1]:.2e}, Loaded: {energies2[-1]:.2e}")
        print(f"Final max speed - Fresh: {speeds1[-1]:.2e}, Loaded: {speeds2[-1]:.2e}")
        
        if np.abs(energies1[-1] - energies2[-1]) / energies1[-1] < 0.1:
            print("[CONCLUSION] Similar behavior - brain state is valid")
        else:
            print("[CONCLUSION] Different behavior - needs investigation")
    else:
        print("Failed to load brain state")
    
    print("\n" + "="*50)
    print("EXPERIMENT COMPLETE")
    print("\nNext experiments:")
    print("1. Test different grid sizes (512×512, 384×384)")
    print("2. Add guardian-like perturbations")
    print("3. Measure power scaling (theoretical)")
    print("4. Compare with 1024×1024 behavior")

if __name__ == "__main__":
    main()