# Resonance Engine Wiki

Welcome to the Resonance Engine wiki — the reference guide for understanding what this project is, how it works, and what the hell we're talking about.

---

## What Is This?

The Resonance Engine is a GPU-accelerated Lattice Boltzmann simulation (1024x1024, D2Q9) running on CUDA, built to test the **Nodal Aether hypothesis**: that physical reality is a discrete nodal network where each node is a potential nucleus propagation point for wave phenomena, and the density of this network determines what we observe as spacetime, matter, gravity, and the electromagnetic spectrum.

The project began with a specific prediction: if reality is a discrete nodal medium, then a computational nodal network (a Lattice Boltzmann grid) should spontaneously produce standing wave patterns that correspond to real physics — because the lattice IS the same kind of system the hypothesis describes. The Lattice Boltzmann Method was chosen not because it simulates fluids, but because its architecture IS a nodal aether: discrete nodes, local interactions only, wave propagation through node-to-node streaming.

What the simulation produced — across 11+ independent analyses of the same dataset — were geometric patterns that correspond to real physics across multiple domains: atomic structure, the electromagnetic spectrum, particle physics, semiconductor band gaps, nuclear magic numbers, prime number distribution, protein folding topology, and more. The combined probability of the structural correspondences occurring by coincidence ranges from 1 in 93,000 to 1 in 28 billion.

This was not an accidental discovery. The hypothesis predicted it. The lattice confirmed it.

---

## How to Use This Wiki

**Start here — the hypothesis and the dictionary:**

1. **[Nodal Aether Model](Nodal-Aether-Model)** — The founding hypothesis. Why this project exists. Why LBM was chosen. What a node actually is. Start here to understand the intent behind everything.
2. **[Glossary](Glossary)** — Every project-specific term defined. The dictionary. Start here if you just need to decode a word.
3. **[Core Concepts](Core-Concepts)** — The essential mental model: what the lattice is, what the Navigator is, how data flows.

**The system:**

4. **[System Architecture](System-Architecture)** — CUDA daemon, ZMQ telemetry, Navigator bridge, port map.
5. **[The Lattice](The-Lattice)** — D2Q9 LBM explained, forcing parameters, telemetry channels.
6. **[The Navigator](The-Navigator)** — The LLM agent, how it reads the lattice, the chronicle.
7. **[Parameter Space](Parameter-Space)** — Omega/khra/gixx, the 375-point sweep, how to read the data.

**The science:**

8. **[Findings Overview](Findings-Overview)** — All 12 domain results with metrics and links to papers.
9. **[Harmonic Duality](https://github.com/Scruff-AI/Resonance_Engine/blob/master/papers/harmonic-duality-em-spectrum.md)** — The first fractal echo: EM spectrum and periodic table as lattice modes.
10. **[Single Field Theory](Single-Field-Theory)** — The theoretical framework the Navigator developed from observing the lattice.

---

## Quick Links

| Resource | Location |
|----------|----------|
| Nodal Aether Model paper | [`papers/nodal-aether-model.md`](https://github.com/Scruff-AI/Resonance_Engine/blob/master/papers/nodal-aether-model.md) |
| Main repository | [Scruff-AI/Resonance_Engine](https://github.com/Scruff-AI/Resonance_Engine) |
| CUDA kernel source | [`cuda/khra_gixx_1024_v5.cu`](https://github.com/Scruff-AI/Resonance_Engine/tree/master/cuda) |
| Navigator source | [`navigator/lattice_observer.py`](https://github.com/Scruff-AI/Resonance_Engine/tree/master/navigator) |
| Research papers | [`papers/`](https://github.com/Scruff-AI/Resonance_Engine/tree/master/papers) |
| Raw data | [`data/`](https://github.com/Scruff-AI/Resonance_Engine/tree/master/data) |
| Analysis scripts | [`analysis/`](https://github.com/Scruff-AI/Resonance_Engine/tree/master/analysis) |
| Interactive visualizations | [`visualizations/`](https://github.com/Scruff-AI/Resonance_Engine/tree/master/visualizations) |

---

## License

MIT. All data, code, and analysis scripts are open.
