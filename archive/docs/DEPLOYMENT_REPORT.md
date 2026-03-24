# DEPLOYMENT REPORT: WSL2 CUDA LBM Daemons
**Date:** 2026-03-16 (updated)  
**Host:** Beast (RTX 4090, Windows 11)  
**Status:** LIVE — both 512 and 1024 daemons deployed, bridges verified

---

## What Was Deployed

Real-time LBM (Lattice Boltzmann Method) CUDA daemon running in WSL2, publishing grid state over ZeroMQ to a Python bridge on the Windows side. The pipeline is:

```
512 Daemon:  LBM CUDA (WSL2, 100Hz) → ZeroMQ tcp://localhost:5555 → Python Bridge (Windows) → Ollama
1024 Daemon: LBM CUDA (WSL2, 100Hz) → ZeroMQ tcp://localhost:5556 → Python Bridge (Windows) → Ollama
```

## Environment

| Component | Detail |
|-----------|--------|
| WSL Distro | Ubuntu 24.04.2 LTS |
| GPU | RTX 4090 (sm_89, Ada Lovelace) |
| NVIDIA Driver | 581.57 (CUDA 13.0 capable) |
| CUDA Toolkit | 12.6 (V12.6.85) — minimal install: nvcc, cudart-dev, nvml-dev, cccl |
| ZeroMQ | libzmq3-dev 4.3.5 (WSL) + pyzmq 27.1.0 (Windows Python) |
| json-c | libjson-c-dev 0.17 |
| Sudo | Passwordless for user `johndev` |

## What Was Fixed Before Deployment

### 1. Distribution function initialization (critical)
The `lbm_cuda_daemon.cu` had a stub `// ... initialization code ...` where `d_f` (the LBM distribution functions, 512×512×9 floats) was never initialized after `cudaMalloc`. Running without this would have pumped NaN/garbage metrics through the entire pipeline.

**Fix:** Added `load_etch()` function (matching the pattern used in all other `.cu` files in the project) that:
- Loads from `etch_khragixx.bin` if present (rho, ux, uy → compute equilibrium distributions)
- Falls back to uniform equilibrium (rho=1, u=0) if file is missing

### 2. NVML init/shutdown in hot loop
`nvmlInit()` and `nvmlShutdown()` were being called every iteration at 100Hz inside the main loop. Moved to one-time setup/teardown outside the loop.

## Files Modified
- `D:\fractal-brain\beast-build\lbm_cuda_daemon.cu` — added `load_etch()`, fixed NVML lifecycle

## Files Created
- `D:\fractal-brain\beast-build\setup_wsl_cuda.sh` — WSL2 CUDA setup script
- `D:\fractal-brain\beast-build\compile_daemon.sh` — build script (handles PATH)
- `D:\fractal-brain\beast-build\verify_install.sh` — dependency verification
- `D:\fractal-brain\beast-build\test_bridge.py` — ZeroMQ bridge connection test

## Binary
- `D:\fractal-brain\beast-build\lbm_cuda_daemon` (WSL2 ELF, 1MB)
- Compiled: `nvcc -O3 -arch=sm_89 -lzmq -ljson-c -lnvidia-ml`

## Live Metrics (observed at cycle 15000+)

| Metric | Range | Notes |
|--------|-------|-------|
| Coherence | 14.0–15.6 | Structural integrity, stable oscillation |
| H64 (logic) | 6.3–8.0 | 64-cell skeleton dominant |
| H32 (creative) | 0.04–0.05 | Creative channel quiet |
| Asymmetry | 5.1–6.0 | Left-right grid difference |
| Vorticity | Published | Curl of velocity field |
| Power | 40–75W | GPU thermal cycling |

Grid loaded from `etch_khragixx.bin` (Khra'gixx etch with live wave injection at 64-cell and 8-cell harmonics).

## How To Operate

### Start daemon (WSL2)
```bash
wsl -d Ubuntu -e bash -c "export PATH=/usr/local/cuda-12.6/bin:\$PATH; cd /mnt/d/fractal-brain/beast-build && ./lbm_cuda_daemon"
```

### Verify bridge (Windows)
```powershell
cd D:\fractal-brain\beast-build
python test_bridge.py
```

### Run interactive bridge with Ollama (Windows)
```powershell
cd D:\fractal-brain\beast-build
python lbm_llm_bridge.py
```

### Run contextual bridge (maintains conversation history)
```powershell
cd D:\fractal-brain\beast-build
python lbm_ollama_bridge_context.py
```

### Recompile after code changes
```bash
wsl -d Ubuntu -e bash /mnt/d/fractal-brain/beast-build/compile_daemon.sh
```

## Bridge Architecture

`lbm_llm_bridge.py` maps LBM physics to inference parameters:
- **Temperature** = inverse of coherence (high coherence → low temp → structured output)
- **Top-p** = proportional to asymmetry (high asymmetry → more randomness)
- **H64/H32 ratio** = logic vs creative balance in token selection

System prompt is dynamically rebuilt from real-time grid state on every query.

## Deliverables Status

| Deliverable | Status |
|-------------|--------|
| 512 daemon running in WSL2, publishing to port 5555 | **DONE** |
| 1024 daemon running in WSL2, publishing to port 5556 | **DONE** (NaN fix applied, verified) |
| Python bridge receiving data (both ports) | **DONE** |
| Ollama integration with physics-constrained inference | **READY** (bridge code exists, requires `ollama run llama3.2` to be available) |
| `somatic_dataset.jsonl` logging | Requires running interactive/contextual bridge sessions |

## Known State

- Both daemons deployed, only run one at a time (they share the GPU)
- H32 (creative channel) is very quiet (~0.04–0.05) — the grid is in a structured/logical mode
- Khra'gixx wave injection is active (64-cell + 8-cell harmonics for 512; 128-cell + 16-cell for 1024)
- No streaming kernel — collision-only BGK model (consistent with all other `.cu` files in project)

---

## 1024×1024 Daemon (added 2026-03-16)

### What it is
16x data density increase over the 512 grid. Testing Granite state under massive scale. Publishes on **port 5556** (not 5555).

### NaN Bug — Root Cause & Fix
The original `lbm_1024x1024.cu` was created by another agent and produced NaN for all metrics (coherence, H64, H32) while power and cycle count were normal.

**Root cause:** Lines 166–170 initialized `d_f` by reading `d_w[j]` — a `__constant__` GPU memory array — from **host code**. `__constant__` memory lives on the GPU; reading it from the CPU returns garbage/zero. This set `rho=0` everywhere → division by zero in collision kernel → NaN propagation through all metrics. Power was normal because NVML reads don't touch the simulation data.

**Fix applied:**
1. Added `load_etch_1024()` function with host-side `w[]` array (not `d_w[]`)
2. Loads from `etch_khragixx.bin` (512×512 format) and upscales 2x via nearest-neighbor to 1024×1024
3. Falls back to fresh equilibrium (rho=1, u=0) if etch file missing
4. Fixed NVML init/shutdown lifecycle (was in hot loop, same bug the 512 daemon had)

### Files Modified
- `D:\fractal-brain\beast-build\lbm_1024x1024.cu` — added `load_etch_1024()`, fixed `__constant__` read, fixed NVML lifecycle

### Binary
- `D:\fractal-brain\beast-build\lbm_1024x1024` (WSL2 ELF)
- Compiled: `nvcc -O3 -arch=sm_89 lbm_1024x1024.cu -lzmq -ljson-c -lnvidia-ml`
- Compile requires explicit PATH: `export PATH=/usr/local/cuda-12.6/bin:/usr/bin:/bin:$PATH`

### Live Metrics (verified at cycle 9400+)

| Metric | Range | Notes |
|--------|-------|-------|
| Coherence | 14.0–15.6 | Matches 512 daemon range |
| H64 (logic) | 6.6–8.2 | 128-cell skeleton (scaled from 64) |
| H32 (creative) | 0.03–0.05 | 64-cell wave (scaled from 32) |
| Asymmetry | 5.1–5.9 | Left-right grid difference |
| Power | 45–80W | GPU thermal cycling |

### How To Operate

#### Start 1024 daemon (WSL2)
```bash
wsl -d Ubuntu -e bash -c "export PATH=/usr/local/cuda-12.6/bin:/usr/bin:/bin:\$PATH; export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:/usr/lib/x86_64-linux-gnu:\$LD_LIBRARY_PATH; cd /mnt/d/fractal-brain/beast-build && ./lbm_1024x1024"
```

#### Verify 1024 bridge (Windows)
```powershell
cd D:\fractal-brain\beast-build
python test_1024_bridge.py
```

#### Recompile 1024 after code changes
```bash
wsl -d Ubuntu -e bash -c "export PATH=/usr/local/cuda-12.6/bin:/usr/bin:/bin:\$PATH; cd /mnt/d/fractal-brain/beast-build && nvcc -o lbm_1024x1024 lbm_1024x1024.cu -lzmq -ljson-c -lnvidia-ml -O3 -arch=sm_89"
```

#### Kill stale 1024 processes
```bash
wsl -d Ubuntu -e bash -c "pkill -9 -f lbm_1024x1024"
```

**IMPORTANT:** If the bridge still shows NaN after restart, check for zombie processes holding port 5556 (`ps aux | grep lbm_1024`). Kill them all before restarting — the bridge connects to whichever process bound the port first.
