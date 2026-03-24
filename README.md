# Resonance Engine

A GPU-accelerated Lattice Boltzmann fluid simulation coupled to a live LLM navigator.
The CUDA daemon runs a 1024×1024 D2Q9 lattice on your GPU. An LLM (Ollama, API, whatever you want)
subscribes to the telemetry stream over ZMQ, observes the lattice as a living system, and responds.

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
resonance-engine/
├── README.md                    ← you are here
├── cuda/
│   └── khra_gixx_1024_v5.cu     ← the LBM kernel (1024×1024 D2Q9 + wave perturbation)
├── navigator/
│   ├── lattice_observer.py      ← THE navigator (ZMQ subscriber + Ollama + HTTP API)
│   ├── golden_weave_memory.py   ← phi-ratio attractor memory system
│   ├── golden_weave_sidecar.py  ← experiment runner (inject_density tests)
│   ├── memory_extension_server.py ← memory API extension
│   ├── lbm_ollama_bridge.py     ← standalone Ollama bridge (simpler alternative)
│   ├── eternal_scout_daemon.py  ← autonomous exploration loop
│   ├── mock_lbm_daemon.py       ← fake daemon for testing without GPU
│   ├── zmq_raw_bridge.py        ← ZMQ debug tool
│   ├── telemetry_server.py      ← HTTP telemetry endpoint
│   ├── sentry_monitor.py        ← auto-checkpoint on anomalies
│   └── lbm_modelfile            ← Ollama model definition (system prompt)
├── scripts/
│   ├── setup_wsl_cuda.sh        ← one-time WSL + CUDA + deps installer
│   ├── compile.sh               ← compile the CUDA kernel
│   ├── start.sh                 ← start daemon + navigator
│   ├── launch.sh                ← start daemon only
│   └── verify_install.sh        ← check your install
├── docs/
│   └── SYSTEM_MANUAL.md         ← detailed system internals
└── archive/                     ← historical experiments, old kernels, inquiry scripts
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
