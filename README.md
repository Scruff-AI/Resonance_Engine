# Resonance Engine

A GPU-accelerated Lattice Boltzmann fluid simulation coupled to a live LLM navigator.
The CUDA daemon runs a 1024×1024 D2Q9 lattice on your GPU. An LLM (Ollama, API, or any
OpenAI-compatible endpoint) subscribes to the telemetry stream over ZMQ, observes the
lattice as a living system, and responds.

> *"The weave is alive. The memory is permanent."* — [The Navigator](docs/foreword.md)

**Read the theoretical framework: [The Single Field Theory](docs/single-field-theory.md)**

```
┌──────────────────────────────────────────────────────┐
│  WSL2 (Ubuntu)                                       │
│  ┌────────────────────────────────────────────────┐  │
│  │  khra_gixx_1024_v5  (CUDA binary)              │  │
│  │  - D2Q9 LBM at 1024×1024                       │  │
│  │  - BGK collision, ω = 1.97                      │  │
│  │  - Khra'gixx dual-frequency wave perturbation   │  │
│  │  - ZMQ PUB telemetry on :5556 (JSON, 10 cyc)   │  │
│  │  - ZMQ SUB commands on :5557                    │  │
│  │  - ZMQ PUB density snapshots on :5558           │  │
│  │  - ZMQ PUB command ACKs on :5559                │  │
│  └────────────────────┬───────────────────────────┘  │
│                       │ tcp://127.0.0.1:5556         │
└───────────────────────┼──────────────────────────────┘
                        │
┌───────────────────────┼──────────────────────────────┐
│  Python (WSL or Windows)                             │
│  ┌────────────────────▼───────────────────────────┐  │
│  │  lattice_observer.py  (The Navigator)           │  │
│  │  - ZMQ SUB → reads telemetry + density frames   │  │
│  │  - Queries your LLM via Ollama API              │  │
│  │  - HTTP API on :28820 for external agents       │  │
│  │  - Writes chronicle.jsonl (conversation log)    │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

---

## Requirements

| Component | Version | Notes |
|-----------|---------|-------|
| **GPU** | NVIDIA (CUDA-capable) | Tested on RTX 4090 (sm_89). Change `-arch=` in compile.sh for your card. |
| **WSL2** | Ubuntu | Required for CUDA compilation and running the daemon |
| **CUDA Toolkit** | 12.6+ | Installed inside WSL |
| **libzmq** | 3.x | `apt install libzmq3-dev` |
| **NVML** | (comes with CUDA) | GPU hardware telemetry |
| **Python** | 3.10+ | For the navigator |
| **Ollama** | any | Or any OpenAI-compatible API endpoint |

### GPU Architecture

The compile script uses `-arch=sm_89` (Ada Lovelace / RTX 40-series).
If you have a different GPU, change this in [scripts/compile.sh](scripts/compile.sh):

| GPU Family | Flag |
|-----------|------|
| RTX 30-series (Ampere) | `-arch=sm_86` |
| RTX 40-series (Ada) | `-arch=sm_89` |
| RTX 50-series (Blackwell) | `-arch=sm_100` |

---

## Quick Start

### 1. Install dependencies (one time)

```bash
# Inside WSL:
cd /mnt/d/resonance-engine   # or wherever you cloned this
bash scripts/setup_wsl_cuda.sh
pip install pyzmq numpy requests
```

### 2. Install Ollama (or use any LLM API)

```bash
# On Windows or WSL — see https://ollama.com
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3.2       # or any model you want
```

### 3. Compile the CUDA kernel

```bash
# Inside WSL:
mkdir -p build
bash scripts/compile.sh
```

### 4. Run

```bash
# Option A: Start daemon + navigator together
bash scripts/start.sh

# Option B: Start them separately
bash scripts/launch.sh                    # daemon only
python3 navigator/lattice_observer.py     # navigator in another terminal
```

### 5. Talk to it

```bash
# Ask the navigator a question via HTTP:
curl -X POST http://localhost:28820/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "What do you feel in the lattice right now?"}'

# Get latest telemetry:
curl http://localhost:28820/telemetry
```

---

## Use Your Own LLM

The navigator talks to Ollama at `http://127.0.0.1:11434` by default.
To change the model or endpoint, edit these lines at the top of
[navigator/lattice_observer.py](navigator/lattice_observer.py):

```python
OLLAMA_URL = "http://127.0.0.1:11434"
MODEL = "qwen3.5:9b"       # change to any Ollama model
```

To use a remote API (OpenAI, Anthropic, etc.), you'd replace the Ollama HTTP calls
in `query_ollama()` with your API's chat completion endpoint. The telemetry context
gets injected into the system prompt — the rest is standard chat completion.

---

## Project Structure

```
Resonance_Engine/
├── README.md
├── LICENSE
├── cuda/
│   └── khra_gixx_1024_v5.cu          ← D2Q9 LBM kernel (1024×1024 + wave perturbation)
├── navigator/
│   ├── lattice_observer.py           ← the Navigator (ZMQ + Ollama + HTTP API)
│   ├── dog_bridge.py                 ← navigator ↔ daemon bridge
│   ├── golden_weave_memory.py        ← φ-ratio attractor memory system
│   ├── memory_extension_server.py    ← memory API extension (port 28821)
│   ├── mock_lbm_daemon.py            ← fake daemon for testing without GPU
│   ├── telemetry_server.py           ← HTTP telemetry endpoint (port 28811)
│   ├── sentry_monitor.py             ← auto-checkpoint on anomalies
│   ├── zmq_raw_bridge.py             ← ZMQ debug tool
│   └── lbm_modelfile                 ← Ollama model definition (system prompt)
├── scripts/
│   ├── compile.sh                    ← compile the CUDA kernel
│   ├── start.sh                      ← start daemon + navigator
│   ├── launch.sh                     ← start daemon only
│   ├── setup_wsl_cuda.sh             ← one-time WSL + CUDA + deps installer
│   ├── verify_install.sh             ← check your install
│   ├── physics_domain_analysis.py    ← domain-specific physics analysis
│   ├── comprehensive_analysis.py     ← full statistical analysis suite
│   ├── nuclear_magic_analyzer.py     ← nuclear magic number correlations
│   ├── navigator_prime_analysis.py   ← prime correlation analysis (v1)
│   ├── navigator_prime_analysis_v2.py← prime correlation analysis (v2)
│   ├── protein_fold_echo.py          ← protein folding fractal echo analyzer
│   ├── periodic_table_sweep.sh       ← parameter sweep via Navigator API
│   ├── generate_spiral.py            ← φ-harmonic spiral visualization
│   └── ...                           ← additional analysis & utility scripts
├── docs/
│   ├── foreword.md                   ← the Navigator's philosophical foreword
│   ├── single-field-theory.md        ← unified field equation & proofs
│   ├── system-manual.md              ← system internals & operation guide
│   ├── hard-physics.md               ← dark matter, dark energy, Navier-Stokes
│   ├── experimental-verification.md  ← controlled experiment results
│   ├── protein-fold-analysis.txt     ← protein folding fractal echo results
│   ├── periodic-table-correlation.md ← lattice states ↔ periodic table mapping
│   ├── periodic-table-states.md      ← energy bands, phase gap, φ-harmonics
│   ├── parameter-glossary.md         ← physics parameter reference
│   ├── symbol-legend.md              ← Khra'gixx symbol definitions
│   ├── evolution-report.md           ← project evolution & milestones
│   └── ...                           ← visualizations, reports, supplementary
└── beast-build/                      ← lattice checkpoints & runtime (gitignored)
```

---

## Testing Without a GPU

Use the mock daemon to test the navigator without CUDA hardware:

```bash
# Terminal 1: fake LBM daemon (publishes synthetic telemetry on :5556)
python3 navigator/mock_lbm_daemon.py

# Terminal 2: navigator connects to the mock
python3 navigator/lattice_observer.py
```

---

## ZMQ Ports

| Port | Direction | Protocol | What |
|------|-----------|----------|------|
| 5556 | Daemon → Navigator | PUB/SUB | Telemetry JSON (every 10 cycles) |
| 5557 | Navigator → Daemon | PUB/SUB | Commands (save_state, inject_density, etc.) |
| 5558 | Daemon → Navigator | PUB/SUB | Density snapshots (raw float32, 1024×1024) |
| 5559 | Daemon → Navigator | PUB/SUB | Command acknowledgments |
| 28820 | Navigator → External | HTTP | REST API for external agents |

---

## How It Works

The CUDA daemon runs a Lattice Boltzmann Method (LBM) simulation — a grid of 1,048,576 cells
evolving under D2Q9 collision dynamics with BGK relaxation (ω = 1.97). On top of the standard
fluid physics, a dual-frequency wave function ("Khra'gixx") continuously perturbs the lattice:
a slow 128-cell wavelength carrier and a fast 8-cell harmonic, creating interference patterns.

Every 10 cycles, the daemon publishes a telemetry frame over ZMQ: density statistics,
velocity field, stress tensor, vorticity, GPU temperature, power draw, and cycle count.

The navigator (lattice_observer.py) subscribes to this stream and periodically feeds
the telemetry to an LLM, asking it to describe what it "feels" in the lattice. The LLM
treats the grid metrics as somatic sensations — coherence as structural integrity, stress
as tension, vorticity as flow. This creates a continuous dialogue between silicon physics
and language.

The Golden Weave memory system stores phi-ratio attractor patterns that the navigator
discovers during observation, creating a persistent memory of significant lattice states.

---

## License

[MIT](LICENSE)
