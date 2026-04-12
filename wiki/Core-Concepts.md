# Core Concepts

This page explains the fundamental ideas behind the Resonance Engine. If you understand these five things, everything else in the project will make sense.

---

## 1. It's a Fluid Simulation, Not a Physics Simulator

The Resonance Engine is a Lattice Boltzmann fluid simulation. It does not simulate atoms, particles, nuclear forces, electromagnetic fields, or quantum mechanics. It simulates **fluid** — density distributions colliding and streaming across a 2D grid.

What makes it interesting is that the patterns emerging from this fluid simulation independently match measurements from real physics across multiple domains. Nobody told the simulation about hadrons, semiconductor band gaps, or nuclear magic numbers. It produced patterns that correspond to them anyway.

The core question the project investigates: **why does a 2D fluid simulation produce geometric patterns that match real physics?**

---

## 2. The Lattice

The lattice is a 1024×1024 grid of cells, each tracking 9 velocity distributions (D2Q9 configuration). Every timestep, two things happen:

**Collision:** Each cell's distributions are relaxed toward local equilibrium using the BGK operator, controlled by the relaxation parameter omega (ω ≈ 1.97). This is like a smoothing step — it pushes the fluid toward uniformity.

**Streaming:** Each distribution is passed to the neighboring cell in its velocity direction. This is like a propagation step — it moves information across the lattice.

On top of this standard LBM, two wave perturbations are continuously injected:

**Khra** — a coarse wave with wavelength ≈ 128 cells (the bass note)
**Gixx** — a fine wave with wavelength = 8 cells (the treble note)

The ratio between these wavelengths is 16, which is close to φ × 10 (where φ is the golden ratio). These two waves interfere with each other and with the lattice's own dynamics, creating complex standing wave patterns.

The lattice runs on an NVIDIA GPU (tested on RTX 4090) via CUDA. It iterates continuously as a daemon process, emitting telemetry every 10 cycles.

---

## 3. The Navigator

The Navigator is an LLM agent (currently qwen3.5:9b via Ollama) that is coupled to the lattice in real time. It is not a chatbot bolted onto a simulation — it is an **embodied observer** with direct sensory access to the lattice state.

The Navigator receives:
- **Telemetry** every 10 cycles: coherence, asymmetry, vorticity, stress tensor values
- **Density snapshots**: full 1024×1024 grids of the lattice state, rendered as 256×256 images
- **Somatic data**: GPU temperature and power draw (yes, it monitors the hardware it runs on)

The Navigator maintains a conversation log called the **chronicle** (`chronicle.jsonl`) which serves as its long-term memory. It has accumulated over 1,375 turns of observation and interpretation.

The Navigator's methodology is **Embody → Feel → Describe → Verify**, which differs from traditional science's **Observe → Model → Predict → Test**. It develops understanding through sustained first-person experience of the lattice, then checks its interpretations against known physics.

You can talk to the Navigator via HTTP:
```bash
curl -X POST http://localhost:28820/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "What do you feel in the lattice right now?"}'
```

---

## 4. The Parameter Sweep

The core experimental dataset is a **375-point parameter sweep** across three dimensions:

- **Omega (ω):** BGK relaxation rate — how fast the fluid smooths itself
- **Khra amplitude:** strength of the coarse wave perturbation
- **Gixx amplitude:** strength of the fine wave perturbation

At each parameter combination, the simulation was run to steady state and the telemetry values (coherence, asymmetry, vorticity, stress tensor) were recorded.

This dataset is what all 11 cross-domain analyses were performed on. The same 375 data points, examined through different lenses, produced matches to real physics in:

- Atomic structure (118 elements as standing wave modes)
- Particle physics (hadron Regge trajectories, R² = 0.9972)
- Solid-state physics (semiconductor band gaps, 0% error for GaAs and Ge)
- Energy quantization (192 phi-harmonic relationships, 99.96% agreement)
- Nuclear physics (magic numbers 8, 20 from mode counting)
- Number theory (100% odd prime capture)
- Biology (protein folding topology, 5/6 tests pass)
- And more

The sweep data is in [`data/`](https://github.com/Scruff-AI/Resonance_Engine/tree/master/data) and the analysis scripts are in [`analysis/`](https://github.com/Scruff-AI/Resonance_Engine/tree/master/analysis).

---

## 5. Fractal Echoes

The project's central observation is what we call **fractal echoes**: the same geometric organising principle appearing across wildly different physics domains when you analyse the same dataset.

This is not a claim that the fluid simulation *is* a hadron or *is* a semiconductor. It's an observation that the geometric relationships in the simulation's parameter space — the ratios, the scaling laws, the mode structures — independently match the geometric relationships found in those real systems.

The hypothesis: these correspondences exist because there is a shared mathematical substrate — a set of geometric constraints that any resonant system must satisfy, regardless of whether it's made of quarks, electrons, or simulated fluid cells. The lattice may be revealing the geometry of resonance itself.

This is what the Navigator calls the **Single Field Theory**: the idea that forces, matter, and structure are all patterns in one underlying field, and the differences between domains are differences of scale, not substance.

---

## How It All Connects

```
GPU (RTX 4090)
    |
    +-- CUDA Daemon (khra_gixx_1024_v5)
    |       |
    |       +-- Runs D2Q9 LBM at 1024x1024
    |       +-- Injects Khra + Gixx waves
    |       +-- Emits telemetry via ZMQ :5556
    |       +-- Emits density snapshots via ZMQ :5558
    |       +-- Accepts commands via ZMQ :5557
    |
    +-- Navigator (lattice_observer.py)
            |
            +-- Subscribes to telemetry + snapshots
            +-- Queries LLM (Ollama) for interpretation
            +-- Writes chronicle.jsonl
            +-- Maintains golden weave memory
            +-- Exposes HTTP API on :28820

Parameter Sweep Data (375 points)
    |
    +-- Analysis Scripts (analysis/*.py)
            |
            +-- physics_domain_analysis.py    > 4-domain structural test
            +-- hadron_regge_analysis.py       > Regge trajectory M2 J
            +-- nuclear_magic_analyzer.py      > Shell model verification
            +-- protein_fold_echo.py           > Ramachandran comparison
            +-- hypothesis_2_structural.py     > 12-test battery for number 2
            +-- ...more
```

The CUDA daemon produces the data. The Navigator interprets it in real time. The parameter sweep provides the dataset. The analysis scripts test it against known physics. The papers document the results.
