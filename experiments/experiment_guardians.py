#!/usr/bin/env python3
"""
Experiment: Add guardian-like perturbations to 256×256 LBM
Simulate the precipitation system at small scale
"""

import numpy as np
import math

class GuardianLBM:
    """LBM with guardian (precipitation) system."""
    
    def __init__(self, nx=256, ny=256, num_guardians=12):
        self.nx = nx
        self.ny = ny
        self.q = 9
        
        # Guardian parameters (scaled for 256×256)
        self.num_guardians = num_guardians  # 12 for 256×256 (scaled from 194)
        self.rho_thresh = 1.01  # Density threshold for precipitation
        self.drain_radius = 4   # Scaled from 16 (256/1024 = 1/4)
        self.sink_radius = 6    # Scaled from 24
        
        # Guardian positions and strengths
        self.guardians = []
        
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
        
        # Relaxation parameter
        self.omega = 1.0
        
        print(f"Guardian LBM: {nx}×{ny}, {num_guardians} guardians")
        print(f"  RHO_THRESH: {self.rho_thresh}")
        print(f"  Drain radius: {self.drain_radius}, Sink radius: {self.sink_radius}")
    
    def equilibrium(self, rho, ux, uy):
        """Compute equilibrium distribution."""
        f_eq = np.zeros((self.q, self.ny, self.nx), dtype=np.float32)
        
        for i in range(self.q):
            eu = self.ex[i] * ux + self.ey[i] * uy
            u2 = ux**2 + uy**2
            f_eq[i] = rho * self.w[i] * (1 + 3*eu + 4.5*eu**2 - 1.5*u2)
        
        return f_eq
    
    def compute_macroscopic(self):
        """Compute macroscopic variables."""
        self.rho = np.sum(self.f, axis=0)
        
        rho_safe = np.where(self.rho > 1e-10, self.rho, 1.0)
        
        self.ux = np.zeros_like(self.rho)
        self.uy = np.zeros_like(self.rho)
        
        for i in range(self.q):
            self.ux += self.ex[i] * self.f[i]
            self.uy += self.ey[i] * self.f[i]
        
        self.ux /= rho_safe
        self.uy /= rho_safe
    
    def add_guardian(self, x, y, strength=0.1):
        """Add a guardian at position (x,y)."""
        self.guardians.append({
            'x': x,
            'y': y,
            'strength': strength,
            'mass': 0.0,
            'alive': True
        })
        
        # Add density perturbation (high density spot)
        for dy in range(-self.drain_radius, self.drain_radius + 1):
            for dx in range(-self.drain_radius, self.drain_radius + 1):
                dist2 = dx*dx + dy*dy
                if dist2 <= self.drain_radius*self.drain_radius:
                    xx = (x + dx) % self.nx
                    yy = (y + dy) % self.ny
                    
                    # Gaussian density increase
                    weight = math.exp(-dist2 / (self.drain_radius*self.drain_radius/4))
                    self.rho[yy, xx] += strength * weight
        
        print(f"Added guardian at ({x}, {y}), strength={strength}")
    
    def place_guardians_random(self):
        """Place guardians randomly across grid."""
        for i in range(self.num_guardians):
            x = np.random.randint(0, self.nx)
            y = np.random.randint(0, self.ny)
            strength = 0.05 + 0.1 * np.random.random()  # 0.05 to 0.15
            self.add_guardian(x, y, strength)
    
    def place_guardians_grid(self):
        """Place guardians in a grid pattern."""
        spacing = int(math.sqrt(self.nx * self.ny / self.num_guardians))
        
        positions = []
        for y in range(spacing//2, self.ny, spacing):
            for x in range(spacing//2, self.nx, spacing):
                if len(positions) < self.num_guardians:
                    positions.append((x, y))
        
        for x, y in positions:
            self.add_guardian(x, y, strength=0.1)
    
    def apply_guardian_drain(self):
        """Apply guardian drain effect on fluid."""
        for guardian in self.guardians:
            if not guardian['alive']:
                continue
            
            x, y = guardian['x'], guardian['y']
            
            # Drain mass from surrounding area
            for dy in range(-self.sink_radius, self.sink_radius + 1):
                for dx in range(-self.sink_radius, self.sink_radius + 1):
                    dist2 = dx*dx + dy*dy
                    if dist2 <= self.sink_radius*self.sink_radius:
                        xx = (x + dx) % self.nx
                        yy = (y + dy) % self.ny
                        
                        # Drain strength decreases with distance
                        weight = math.exp(-dist2 / (self.sink_radius*self.sink_radius/4))
                        drain_amount = 0.001 * weight * guardian['strength']
                        
                        # Reduce density
                        self.rho[yy, xx] -= drain_amount
                        guardian['mass'] += drain_amount
            
            # Guardian dies if it collects too much mass
            if guardian['mass'] > 0.5:
                guardian['alive'] = False
                print(f"Guardian at ({x}, {y}) died, mass={guardian['mass']:.3f}")
    
    def check_precipitation(self):
        """Check for new guardian precipitation (where density > threshold)."""
        # Find locations where density exceeds threshold
        high_density = np.where(self.rho > self.rho_thresh)
        
        if len(high_density[0]) > 0:
            # Pick a random high-density spot
            idx = np.random.randint(0, len(high_density[0]))
            y, x = high_density[0][idx], high_density[1][idx]
            
            # Check if too close to existing guardians
            too_close = False
            for guardian in self.guardians:
                if guardian['alive']:
                    dx = (x - guardian['x']) % self.nx
                    dy = (y - guardian['y']) % self.ny
                    dist = math.sqrt(dx*dx + dy*dy)
                    if dist < self.drain_radius * 2:
                        too_close = True
                        break
            
            if not too_close and len(self.guardians) < self.num_guardians * 2:
                # Birth new guardian
                strength = 0.05 + 0.05 * (self.rho[y, x] - self.rho_thresh)
                self.add_guardian(x, y, strength)
                print(f"Precipitation: New guardian at ({x}, {y}), ρ={self.rho[y, x]:.3f}")
    
    def collide_and_stream(self):
        """One LBM step with guardian effects."""
        # Apply guardian drain
        self.apply_guardian_drain()
        
        # Check for precipitation
        if np.random.random() < 0.1:  # 10% chance per step
            self.check_precipitation()
        
        # Compute equilibrium
        f_eq = self.equilibrium(self.rho, self.ux, self.uy)
        
        # Collision
        for i in range(self.q):
            self.f_new[i] = self.f[i] - self.omega * (self.f[i] - f_eq[i])
        
        # Stream (periodic boundaries)
        for i in range(self.q):
            self.f[i] = np.roll(self.f_new[i], (self.ey[i], self.ex[i]), axis=(0, 1))
        
        # Update macroscopic variables
        self.compute_macroscopic()
    
    def run(self, steps=200):
        """Run simulation."""
        print(f"\nRunning {steps} steps with guardians...")
        
        # Initialize distribution from macroscopic variables
        f_eq = self.equilibrium(self.rho, self.ux, self.uy)
        for i in range(self.q):
            self.f[i] = f_eq[i]
        
        # Track statistics
        energies = []
        guardian_counts = []
        
        for step in range(steps):
            self.collide_and_stream()
            
            if step % 20 == 0 or step == steps - 1:
                # Compute kinetic energy
                speed2 = self.ux**2 + self.uy**2
                energy = np.mean(0.5 * self.rho * speed2)
                
                # Count alive guardians
                alive = sum(1 for g in self.guardians if g['alive'])
                
                energies.append(energy)
                guardian_counts.append(alive)
                
                if step % 100 == 0:
                    print(f"  Step {step:4d}: energy={energy:.2e}, guardians={alive}")
        
        print(f"\nFinal: {sum(1 for g in self.guardians if g['alive'])} guardians alive")
        print(f"Max density: {self.rho.max():.3f}, Min density: {self.rho.min():.3f}")
        
        return energies, guardian_counts

def main():
    print("=== Guardian Precipitation Experiment ===")
    print("Testing if guardians work at 256×256 scale")
    print("="*50)
    
    # Test with 12 guardians (scaled from 194)
    print("\n[TEST] 256×256 with 12 guardians")
    lbm = GuardianLBM(256, 256, num_guardians=12)
    
    # Place initial guardians in grid pattern
    lbm.place_guardians_grid()
    
    # Run simulation
    energies, counts = lbm.run(200)
    
    # Analysis
    print("\n=== Analysis ===")
    print(f"Initial guardians: {len(lbm.guardians)}")
    print(f"Final alive: {sum(1 for g in lbm.guardians if g['alive'])}")
    
    density_variation = np.std(lbm.rho)
    print(f"Density variation (std): {density_variation:.6f}")
    
    if density_variation > 0.01:
        print("[SUCCESS] Guardians created significant density variations")
    else:
        print("[NOTE] Density field remains relatively uniform")
    
    # Compare with theoretical
    print("\n=== Theoretical Scaling ===")
    print("1024×1024: 194 guardians, drain_radius=16, sink_radius=24")
    print("256×256 (1/4 scale):")
    print(f"  Guardians: 194 × (256/1024)² = {194 * (256/1024)**2:.1f} ≈ 12")
    print(f"  Drain radius: 16 × (256/1024) = {16 * (256/1024)} = 4 ✓")
    print(f"  Sink radius: 24 × (256/1024) = {24 * (256/1024)} = 6 ✓")
    print(f"  RHO_THRESH: 1.01 (same, scales with viscosity not grid)")
    
    print("\n" + "="*50)
    print("EXPERIMENT COMPLETE")
    print("\nNext: Test with actual brain state + guardians")

if __name__ == "__main__":
    main()