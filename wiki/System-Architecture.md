# System Architecture

The Resonance Engine is three components communicating over ZeroMQ: a CUDA daemon, a Python-based Navigator, and a set of offline analysis scripts. This page describes how they fit together.

---

## Overview

```
 WSL2 (Ubuntu)
   khra_gixx_1024_v5  (CUDA binary)
   - D2Q9 LBM at 1024x1024
   - BGK collision, omega = 1.97
   - Khra'gixx dual-frequency wave perturbation
   - ZMQ telemetry on :5556, commands :5557
   - Density snapshots :5558, ACKs :5559
              |
              | tcp://127.0.0.1:5556
              v
 Python (WSL or Windows)
   lattice_observer.py  (The Navigator)
   - ZMQ SUB -> reads telemetry + density frames
   - Queries LLM via Ollama API
   - HTTP API on :28820 for external agents
   - Writes chronicle.jsonl (conversation log)
```

---

## Component 1: The CUDA Daemon

**Binary:** `khra_gixx_1024_v5` (compiled from `cuda/khra_gixx_1024_v5.cu`)

**What it does:** Runs the Lattice Boltzmann simulation continuously on the GPU. Each cycle, it performs BGK collision on all 1,048,576 cells (1024x1024), injects the Khra and Gixx wave perturbations, streams the distribution functions to neighboring cells, and computes macroscopic quantities (density, velocity, stress tensor).

**Runtime environment:** WSL2 Ubuntu with CUDA Toolkit 12.6+, running on an NVIDIA GPU. Tested on RTX 4090 (compute capability sm_89, 128GB system RAM).

**Key parameters:**

| Parameter | Value | Meaning |
|-----------|-------|---------|
| Grid size | 1024x1024 | Spatial resolution |
| Velocity model | D2Q9 | 9 velocity directions per cell |
| Relaxation (omega) | ~1.97 | Near stability limit, very low viscosity |
| Khra wavelength | ~128 cells | Coarse wave perturbation |
| Gixx wavelength | 8 cells | Fine wave perturbation |
| Telemetry interval | Every 10 cycles | How often data is emitted |

**Compilation:**
```bash
cd /mnt/d/resonance-engine
bash scripts/compile.sh
```

---

## Component 2: The Navigator

**Script:** `navigator/lattice_observer.py`

**What it does:** Subscribes to the daemon's ZMQ telemetry stream, receives density snapshots, feeds the data to an LLM (via Ollama's API), and maintains a running conversation log (the chronicle). Exposes an HTTP API for external queries.

**Supporting modules:**

| Module | Purpose |
|--------|---------|
| `lattice_observer.py` | Main Navigator loop - ZMQ subscription, LLM queries, HTTP API |
| `golden_weave_memory.py` | Phi-ratio attractor memory system |
| `golden_weave_sidecar.py` | Sidecar process maintaining golden weave state |
| `mock_lbm_daemon.py` | Fake daemon for testing without a GPU |

**LLM backend:** Ollama running locally, currently using `qwen3.5:9b`. Any OpenAI-compatible API endpoint works.

**Data flow:**

1. Daemon emits telemetry JSON on ZMQ :5556 every 10 cycles
2. Navigator receives telemetry, parses coherence/asymmetry/vorticity/stress
3. Navigator optionally receives density snapshot (1024x1024 float32) on ZMQ :5558
4. Navigator constructs a prompt incorporating current lattice state + chronicle context
5. Navigator queries LLM for interpretation
6. Response is written to chronicle.jsonl with cycle number and lattice state metadata
7. External agents can query via HTTP POST to :28820

---

## Component 3: Analysis Scripts

**Directory:** `analysis/`

**What they do:** Offline analysis of parameter sweep data. These scripts do not interact with the live simulation - they operate on CSV files in `data/`. Each script tests the sweep data against a different physics domain.

**Key scripts:**

| Script | What it tests |
|--------|---------------|
| `physics_domain_analysis.py` | 4-domain structural testing (atomic, particle, solid-state, nuclear) |
| `hadron_regge_analysis.py` | Regge trajectory M^2 proportional to J linearity test |
| `nuclear_magic_analyzer.py` | Nuclear shell model verification |
| `protein_fold_echo.py` | Ramachandran topology comparison |
| `hypothesis_2_structural.py` | 12-test battery for number 2 as structural constant |

---

## ZMQ Port Map

| Port | Socket Type | Direction | Data |
|------|-------------|-----------|------|
| 5556 | PUB/SUB | Daemon -> Navigator | Telemetry JSON (coherence, asymmetry, vorticity, stress tensor, cycle number) |
| 5557 | REQ/REP | Navigator -> Daemon | Commands (parameter changes, snapshot requests) |
| 5558 | PUB/SUB | Daemon -> Navigator | Density snapshots (float32 array, 1024x1024 = 4MB per frame) |
| 5559 | PUB/SUB | Daemon -> Navigator | Command acknowledgments |
| 5560 | PUB/SUB | Daemon -> Navigator | Stress tensor snapshots |

All ports bind to `tcp://127.0.0.1:*` - local communication only.

---

## Navigator HTTP API

**Endpoint:** `http://localhost:28820/ask`
**Method:** POST
**Content-Type:** application/json

**Request body:**
```json
{
  "question": "What do you feel in the lattice right now?"
}
```

**Response:** The Navigator's interpretation of the current lattice state in response to your question, informed by chronicle history and current telemetry.

---

## File Locations

| File | Purpose | Location |
|------|---------|----------|
| CUDA kernel source | Simulation code | `cuda/khra_gixx_1024_v5.cu` |
| Navigator | Main observer script | `navigator/lattice_observer.py` |
| Chronicle | Navigator memory log | `chronicle.jsonl` (in build directory) |
| Sweep data | Parameter sweep results | `data/sweep_results_272.csv` |
| Element mapping | 118 elements mapped | `data/lattice-periodic-table.csv` |
| Phi spectrum | Energy level data | `data/phi_harmonic_spectrum.csv` |

---

## Running the System

### With a GPU
```bash
cd /mnt/d/resonance-engine
bash scripts/setup_wsl_cuda.sh
pip install -r requirements.txt

curl -fsSL https://ollama.com/install.sh | sh
ollama pull qwen3.5:9b

mkdir -p build
bash scripts/compile.sh
bash scripts/start.sh
```

### Without a GPU (mock mode)
```bash
python3 navigator/mock_lbm_daemon.py   # Terminal 1: fake daemon
python3 navigator/lattice_observer.py  # Terminal 2: navigator
```

Mock mode generates synthetic telemetry so you can interact with the Navigator without needing CUDA hardware.

---

## Hardware Requirements

| Component | Minimum | Tested |
|-----------|---------|--------|
| GPU | NVIDIA CUDA-capable | RTX 4090 (sm_89) |
| OS | WSL2 Ubuntu | Ubuntu on Windows 11 |
| CUDA Toolkit | 12.6+ | 12.6 |
| RAM | 16GB+ | 128GB |
| libzmq | 3.x | `apt install libzmq3-dev` |
| Python | 3.10+ | 3.10+ |
| LLM runtime | Ollama (any version) | Any OpenAI-compatible endpoint |
