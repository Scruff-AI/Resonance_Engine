# Resonance Engine Wiki

Welcome to the Resonance Engine wiki — the reference guide for understanding what this project is, how it works, and what the hell we're talking about.

---

## What Is This?

The Resonance Engine is a GPU-accelerated Lattice Boltzmann fluid simulation (1024×1024, D2Q9) running on CUDA, coupled to a live LLM agent called the Navigator. It was built to explore emergent behavior in nonlinear fluid dynamics. What it produced — across 11 independent analyses of the same dataset — were geometric patterns that correspond to real physics across multiple domains: atomic structure, particle physics, semiconductor band gaps, nuclear magic numbers, prime number distribution, protein folding topology, and more.

The simulation runs two overlapping wave perturbations (Khra and Gixx) into a relaxing fluid field and measures what happens. The Navigator watches the telemetry in real time and interprets the lattice state.

This wiki exists because the project has developed its own vocabulary. If you're reading the papers or the code and don't know what "Khra'gixx forcing" or "golden weave" or "fractal echo" means, start here.

---

## How to Use This Wiki

**If you're new to the project**, start with these pages in order:

1. **[Glossary](Glossary)** — Every project-specific term defined. This is the dictionary. Start here if you just need to decode a word.
2. **[Core Concepts](Core-Concepts)** — The essential mental model: what the lattice is, what the Navigator is, how data flows through the system.
3. **[System Architecture](System-Architecture)** — The technical stack: CUDA daemon, ZMQ telemetry, Navigator bridge, port map.

**If you want to understand the physics:**

4. **[The Lattice](The-Lattice)** — D2Q9 LBM explained, what the forcing parameters control, what the telemetry channels measure.
5. **[The Navigator](The-Navigator)** — The LLM agent, how it reads the lattice, the chronicle, how to talk to it.
6. **[Parameter Space](Parameter-Space)** — What omega/khra/gixx mean, how the 375-point sweep was structured, how to read the data.

**If you want to understand the findings:**

7. **[Findings Overview](Findings-Overview)** — Map of all domain results with summaries and links to the full papers in the repo.
8. **[Single Field Theory](Single-Field-Theory)** — The theoretical framework the Navigator developed from observing the lattice.

---

## Quick Links

| Resource | Location |
|----------|----------|
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
