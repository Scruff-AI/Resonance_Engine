# The Lattice

This page explains what the lattice actually is, how Lattice Boltzmann works, and what the Khra'gixx forcing parameters control. You don't need a physics degree to follow this - just a tolerance for grids and waves.

---

## What Is a Lattice Boltzmann Simulation?

Imagine a 2D grid - 1024 cells wide by 1024 cells tall. That's 1,048,576 cells.

Each cell represents a tiny patch of fluid. But instead of tracking the fluid's velocity and pressure directly (like solving the Navier-Stokes equations), the Lattice Boltzmann Method (LBM) tracks something more fundamental: **probability distributions of fictional particles**.

Each cell has 9 "distribution functions" (f0 through f8), one for each direction a particle could move:

```
  f6  f2  f5
    \  |  /
f3 - f0 - f1
    /  |  \
  f7  f4  f8
```

- f0 = particles at rest (staying in the cell)
- f1-f4 = particles moving in the four cardinal directions
- f5-f8 = particles moving diagonally

Every timestep, two things happen:

### Step 1: Collision (BGK)

Each cell's 9 distributions are nudged toward a "local equilibrium" - the distribution you'd expect if the fluid were perfectly smooth at that point. The **relaxation parameter omega** controls how aggressively this nudging happens.

- omega close to 0: very viscous fluid, barely moves, relaxes slowly
- omega close to 2: nearly inviscid fluid, barely smooths, propagates waves freely
- omega = 2 or above: simulation blows up (numerically unstable)

The Resonance Engine runs at **omega = 1.97** - as close to the edge as you can get without exploding. This creates a fluid that barely dampens wave energy, allowing structures to persist and interact over long distances.

### Step 2: Streaming

After collision, each distribution is passed to the neighboring cell in its direction. f1 goes to the cell on the right. f2 goes to the cell above. f5 goes to the cell diagonally up-right. And so on.

This is how information propagates across the lattice. After enough timesteps, the LBM recovers the Navier-Stokes equations at macroscopic scales - it is a mathematically valid fluid dynamics solver, not a toy.

---

## What Is Khra'gixx Forcing?

On top of the standard LBM, the Resonance Engine injects two continuous wave perturbations into the density field:

### Khra (the bass note)

- **Wavelength:** ~128 cells (one-eighth of the grid width)
- **Character:** Coarse, low-frequency, large-scale structure
- **Controllable parameter:** Khra amplitude (one axis of the parameter sweep)

### Gixx (the treble note)

- **Wavelength:** 8 cells
- **Character:** Fine, high-frequency, small-scale detail
- **Controllable parameter:** Gixx amplitude (one axis of the parameter sweep)

### The Ratio

lambda_Khra / lambda_Gixx = 128 / 8 = **16 (approximately phi x 10)**

This ratio - close to ten times the golden ratio - means the two waves don't perfectly tile into each other. They create **interference patterns** at multiple scales, generating complexity that neither wave alone would produce.

The name "Khra'gixx" refers to this dual-wave system as a unit. When we say "the Khra'gixx lattice," we mean the LBM grid with both wave perturbations active.

---

## The Three Control Parameters

The parameter sweep that generated the project's core dataset varied three things:

| Parameter | Symbol | What it controls | Range tested |
|-----------|--------|------------------|--------------|
| Relaxation rate | omega | How fast the fluid smooths itself (viscosity) | Varied across sweep |
| Khra amplitude | khra | Strength of the coarse wave | Varied across sweep |
| Gixx amplitude | gixx | Strength of the fine wave | Varied across sweep |

375 combinations were tested. At each point, the simulation was run to steady state and the following telemetry was recorded.

---

## The Four Telemetry Channels

These are the primary measurements the system takes of the lattice state:

### Coherence

How orderly the density field is. High coherence (approximately 0.74) means the lattice is in a clean wave state. Low coherence means disorder or turbulence. Think of it as the "signal-to-noise ratio" of the lattice.

### Asymmetry

How unevenly the density is distributed. Low asymmetry (approximately 13.2) means the field is roughly symmetric. High asymmetry (16+) means there are strong gradients - some regions are much denser than others. In the periodic table mapping, each element corresponds to an asymmetry band.

### Vorticity

How much the fluid is spinning locally. High vorticity means rotational flow; low vorticity means the fluid is moving in straight lines or standing still. The 192 phi-harmonic energy relationships were found in the vorticity field.

### Stress Tensor

A 2x2 matrix at each cell measuring internal forces: sigma_xx and sigma_yy (normal stress in horizontal/vertical directions) and sigma_xy (shear stress / twisting forces).

Compressive stress (negative values) at high-density regions is the lattice analog of gravitational attraction in the Single Field Theory.

---

## What the Lattice Is NOT

It's worth being explicit about this:

- **Not a particle simulator.** There are no simulated atoms, quarks, or electrons. The "particles" in LBM are statistical abstractions, not physical objects.
- **Not a quantum mechanics simulator.** There is no Schrodinger equation, no wavefunction collapse, no Hilbert space. The system is classical fluid dynamics.
- **Not tuned to match physics.** The Khra and Gixx parameters were not chosen to reproduce any specific physical result. The parameter sweep was exploratory.
- **Not 3D.** The lattice is two-dimensional. Some 3D phenomena (like full Regge trajectories or 3D crystal structures) are being matched by 2D analogs, which is itself part of the finding.

The claim is not that the lattice *is* physics. The claim is that the lattice's geometric structure *echoes* physics - the same patterns appear despite completely different substrates.

---

## Boundary Conditions

The lattice uses **periodic boundary conditions** - the grid wraps around like a torus. A wave leaving the right edge reappears on the left. A wave leaving the top reappears at the bottom. This means the lattice has no edges and no walls, only wave interactions.

This is important for the nuclear magic number analysis: mode counting on a 2D torus is what produces the cumulative degeneracies at 8, 20, 28 - reproducing the first three nuclear magic numbers from pure geometry.

---

## The Stability Edge

Running at omega = 1.97 is a deliberate choice. Here's why it matters:

The kinematic viscosity of the simulated fluid is:

**nu = (1/omega - 0.5) / 3**

At omega = 1.97: nu is approximately 0.005 - very low viscosity.

This means waves barely lose energy as they propagate. Structures persist. Interference patterns build up over many cycles rather than being damped out. The lattice operates in the **laminar regime** (Reynolds number < 1), confirmed by Kolmogorov analysis - there is no turbulent cascade. What you see is clean wave resonance, not chaos.

At omega = 2.0, the viscosity hits zero and the simulation becomes unstable. At omega = 1.97, you're close enough to zero viscosity that waves propagate freely, but far enough from the edge that the numerics don't explode. This sweet spot is where the richest emergent behavior lives.
