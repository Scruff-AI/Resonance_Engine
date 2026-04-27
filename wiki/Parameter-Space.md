# Parameter Space

This page explains the three parameters that define the Resonance Engine's behavior, how the 375-point sweep was structured, and how to read the data files.

---

## The Three Axes

The Resonance Engine has three independent control parameters. Everything else - coherence, asymmetry, vorticity, stress - is an emergent result of these three inputs.

### Omega - Relaxation Rate

**What it is:** The BGK collision parameter. Controls how aggressively each cell's distributions are pushed toward local equilibrium every cycle.

**Physical meaning:** Determines the fluid's viscosity. Lower omega = thicker fluid. Higher omega = thinner fluid.

**Formula:** kinematic viscosity nu = (1/omega - 0.5) / 3

**Operating value:** omega = 1.97 (viscosity approximately 0.005, nearly inviscid)

**Why it matters:** At low omega, waves are damped quickly and nothing interesting accumulates. At high omega (near 2.0), waves propagate freely and interference patterns build up over many cycles. The Resonance Engine operates near the stability limit specifically because this is where the richest emergent behavior lives.

**Stability boundary:** omega >= 2.0 causes numerical explosion. The simulation cannot run above this value.

### Khra Amplitude - Coarse Wave Strength

**What it is:** The amplitude of the Khra wave perturbation injected into the density field each cycle.

**Physical meaning:** How strongly the large-scale (lambda = 128 cells) wave pushes the fluid. Higher amplitude = bigger density swings at the coarse scale.

**Character:** The "bass note" of the dual-wave system. Provides large-scale spatial structure.

### Gixx Amplitude - Fine Wave Strength

**What it is:** The amplitude of the Gixx wave perturbation injected into the density field each cycle.

**Physical meaning:** How strongly the small-scale (lambda = 8 cells) wave pushes the fluid. Higher amplitude = bigger density swings at the fine scale.

**Character:** The "treble note" of the dual-wave system. Provides small-scale detail and texture.

---

## How They Interact

The three parameters don't act independently - they interact nonlinearly:

**Omega x Khra:** At low omega, even strong Khra forcing is damped out. At high omega, moderate Khra forcing creates persistent large-scale standing waves. The Khra forcing is most effective near the stability edge.

**Omega x Gixx:** Same relationship but at the fine scale. High omega + moderate Gixx = persistent fine-scale interference.

**Khra x Gixx:** The two waves interfere with each other. Because their wavelengths don't divide evenly (128/8 = 16, not a power of 2), the interference pattern is complex and non-repeating at short scales. This is where the richness comes from - the mismatch between the two scales forces the lattice to find compromise states that turn out to match real physics.

---

## The 375-Point Sweep

The parameter sweep systematically explored the 3D parameter space. Each axis was sampled at multiple values. At each combination, the simulation was run until the telemetry stabilised (steady state). The steady-state values of coherence, asymmetry, vorticity, and stress tensor were recorded.

The result is a dataset of 375 rows, each representing one parameter combination and its emergent telemetry. This dataset is what all 11 cross-domain analyses were performed on.

### Data Files

| File | Description |
|------|-------------|
| `data/sweep_results_272.csv` | Initial sweep (272 points) |
| `data/lattice-periodic-table.csv` | All 118 elements mapped to lattice parameters |
| `data/phi_harmonic_spectrum.csv` | Energy level data from vorticity analysis |

### Reading the Sweep Data

Each row in the sweep CSV contains:

| Column | Meaning |
|--------|---------|
| omega | Relaxation parameter value |
| khra | Khra amplitude value |
| gixx | Gixx amplitude value |
| coherence | Steady-state coherence (0-1 scale) |
| asymmetry | Steady-state asymmetry |
| vorticity | Steady-state vorticity |
| stress_xx | Horizontal normal stress |
| stress_yy | Vertical normal stress |
| stress_xy | Shear stress |

---

## Key Regions of Parameter Space

The sweep revealed several notable regions:

### The Cognition Band (Asymmetry 14.0-14.2)
Where the Navigator reports optimal clarity. Coherence is high (~0.74), wave structure is clean, and the lattice is most responsive to perturbation. This band corresponds to Period 2 elements (Li through Ne) in the periodic table mapping.

### The Phase Gap (Asymmetry ~15.78)
The largest single resonance node - 32 elements cluster here. This is where wave complexity is maximised while coherence is still maintained. Transition metals from Tc through Rn sit at this threshold.

### The Stability Edge (omega > 1.95)
Where the most interesting phenomena emerge. Below omega = 1.5, the fluid is too viscous for complex wave interactions. Above omega = 1.95, the lattice enters a regime where wave energy persists indefinitely and interference patterns accumulate into structured standing waves.

### The Laminar Envelope (Re < 1)
Confirmed by Kolmogorov analysis - throughout the entire tested parameter space, the flow remains laminar (non-turbulent). The patterns are wave resonance, not turbulent eddies.
