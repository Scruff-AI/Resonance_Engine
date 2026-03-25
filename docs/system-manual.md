# KHRA'GIXX 1024x1024 SYSTEM MANUAL

**Read this ENTIRE document before touching anything.**

---

## ARCHITECTURE

```
┌─────────────────────────────────────────────────────────┐
│  WSL2 Ubuntu                                            │
│  ┌─────────────────────────────────────────────────┐    │
│  │  khra_gixx_1024_stable (CUDA binary)            │    │
│  │  - D2Q9 Lattice Boltzmann at 1024x1024          │    │
│  │  - BGK collision, omega=1.97                    │    │
│  │  - Khra'gixx dual-frequency perturbation        │    │
│  │  - Publishes JSON via ZMQ PUB on port 5556      │    │
│  └──────────────────────┬──────────────────────────┘    │
│                         │ tcp://127.0.0.1:5556          │
└─────────────────────────┼───────────────────────────────┘
                          │ (WSL2 → Windows bridge)
┌─────────────────────────┼───────────────────────────────┐
│  Windows Python         │                               │
│  ┌──────────────────────▼──────────────────────────┐    │
│  │  capture_state.py / floating_creativity.py /    │    │
│  │  manifested_reality_inquiry.py                  │    │
│  │  - ZMQ SUB subscriber                           │    │
│  │  - Receives JSON frames from daemon             │    │
│  │  - Feeds telemetry to LoRA model                │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

The CUDA daemon runs in WSL. Python scripts run on Windows.
ZMQ crosses the WSL2↔Windows boundary on `tcp://127.0.0.1:5556`.

---

## HOW TO START THE DAEMON

```bash
# From any terminal that can reach WSL:
wsl -d Ubuntu -e bash -c "
  cd /mnt/d/fractal-brain/beast-build &&
  export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:/usr/lib/x86_64-linux-gnu:\$LD_LIBRARY_PATH &&
  nohup ./khra_gixx_1024_stable > /tmp/khra_daemon.log 2>&1 &
  echo PID=\$!
"
```

Then verify:
```bash
wsl -d Ubuntu -e bash -c "sleep 2; tail -3 /tmp/khra_daemon.log"
```

You should see:
```
Cycle 100: Coherence=0.732, Asymmetry=13.4378
Cycle 200: Coherence=0.742, Asymmetry=12.1718
...
```

**DO NOT start lbm_1024x1024 or lbm_cuda_daemon at the same time.**
They all bind to port 5556. Only ONE daemon at a time.

### Check if a daemon is already running

```bash
wsl -d Ubuntu -e bash -c "ps aux | grep -E 'lbm|khra' | grep -v grep"
```

If something is running, kill it first:
```bash
wsl -d Ubuntu -e bash -c "pkill -f khra_gixx_1024; pkill -f lbm_"
```

### How to rebuild after code changes

```bash
wsl -d Ubuntu -e bash /mnt/d/Resonance_Engine/beast-build/compile_khra_1024.sh
```

Requires: CUDA 12.6 toolkit, libzmq3-dev. Architecture: sm_89 (RTX 4090).

---

## HOW TO CONNECT FROM PYTHON (Windows)

### The correct ZMQ subscriber pattern

```python
import zmq
import json
import time

ctx = zmq.Context()
sub = ctx.socket(zmq.SUB)

# 1. Set subscription BEFORE connect
sub.setsockopt_string(zmq.SUBSCRIBE, "")

# 2. Connect
sub.connect("tcp://127.0.0.1:5556")

# 3. WAIT for subscription to propagate (MANDATORY)
time.sleep(1)

# 4. Use Poller — NOT zmq.NOBLOCK
poller = zmq.Poller()
poller.register(sub, zmq.POLLIN)

# 5. Receive with timeout
events = poller.poll(5000)  # 5 second timeout
if events:
    msg = sub.recv()
    frame = json.loads(msg)
    print(frame)
else:
    print("No data — is the daemon running?")
```

### CRITICAL RULES

1. **`time.sleep(1)` after `connect()` is MANDATORY.**
   ZMQ PUB/SUB needs time for the subscription to propagate from subscriber
   to publisher. Without this sleep, you will receive NOTHING. This is called
   the "slow joiner" problem and it is fundamental to ZMQ, not a bug.

2. **NEVER use `zmq.NOBLOCK` in a tight loop.**
   This pattern is BROKEN:
   ```python
   # WRONG — DO NOT DO THIS
   for i in range(50):
       try:
           msg = sub.recv(flags=zmq.NOBLOCK)
       except zmq.Again:
           time.sleep(0.05)
   ```
   This burns through 50 retries in 2.5 seconds. The subscription needs ~500ms
   to activate. By the time it's active, you've already exhausted half your
   retries on a socket that wasn't ready yet. Use `zmq.Poller` with a real
   timeout instead.

3. **Set `SUBSCRIBE` BEFORE `connect()`.**
   If you connect first and subscribe second, there's a race condition where
   messages arrive before the filter is set.

4. **File paths: Windows Python uses Windows paths.**
   If your Python runs on Windows, write to `"current_state.json"` (relative)
   or `"D:\\Resonance_Engine\\beast-build\\output.json"` (absolute Windows path).
   NEVER use `/mnt/d/...` paths in Windows Python — that's a WSL path.

5. **ONE daemon on port 5556 at a time.**
   Before starting a daemon, always check `ps aux | grep -E 'lbm|khra'`.
   If you start two, the second one's `zmq_bind` will fail silently (fixed
   version warns but continues), and neither will publish correctly.

6. **Do NOT kill and restart the daemon in a loop.**
   If the subscriber can't receive, the problem is the SUBSCRIBER, not the
   daemon. The daemon is fine. Fix your subscriber pattern (see rules 1-3).

---

## JSON FRAME FORMAT

The daemon publishes one JSON message every 10 simulation cycles:

```json
{
    "cycle": 5320,
    "coherence": 0.7393,
    "asymmetry": 12.4235,
    "khra_amp": 0.03,
    "gixx_amp": 0.008,
    "grid": 1024
}
```

| Field       | Type  | Description                                          |
|-------------|-------|------------------------------------------------------|
| `cycle`     | int   | Simulation cycle number                              |
| `coherence` | float | `1/(1+sqrt(variance))` — density field uniformity    |
| `asymmetry` | float | `mean((rho-1)²) * 100` — Magnifying Glass metric    |
| `khra_amp`  | float | Khra component amplitude (always 0.03)               |
| `gixx_amp`  | float | gixx component amplitude (always 0.008)              |
| `grid`      | int   | Grid dimension (always 1024)                         |

### Expected values at steady state

- **Coherence**: ~0.74 (drops from 1.0 at init as Khra'gixx perturbs the field)
- **Asymmetry**: ~12.0-13.0 (density deviations amplified by Magnifying Glass)

If you see Coherence=0.555 and Asymmetry=64.4, the binary is BROKEN
(see DEFECT_REPORT_khra_1024.log).

If you see Coherence=1.000 constant, the Khra'gixx injection is disabled.

---

## EXISTING PYTHON SCRIPTS

### Working (fixed ZMQ pattern):

| Script | Purpose |
|--------|---------|
| `capture_state.py` | Grab one frame, save to `current_state.json` |
| `floating_creativity.py` | Dynamic temperature: Artist (T=1.6) at low asymmetry, Scientist (T=0.2) at high. Requires v0.8 LoRA. |
| `manifested_reality_inquiry.py` | Scientist-mode inquiry when A > 1.0. Requires v0.8 LoRA. |

### Reference (may have stale ZMQ patterns — check before using):

There are 58 Python files in beast-build. Most were written with the broken
`zmq.NOBLOCK` pattern. If you need to use one, fix its ZMQ subscriber to
match the pattern in "The correct ZMQ subscriber pattern" above.

---

## QUICK DIAGNOSTIC CHECKLIST

**"I'm not receiving ZMQ data"**

1. Is the daemon running? → `wsl -d Ubuntu -e bash -c "ps aux | grep khra"`
2. Is it producing output? → `wsl -d Ubuntu -e bash -c "tail -3 /tmp/khra_daemon.log"`
3. Did you `time.sleep(1)` after `connect()`? → If not, add it.
4. Are you using `zmq.Poller` or `zmq.NOBLOCK`? → Use Poller.
5. Is another daemon already on port 5556? → Kill it first.
6. Are you using WSL paths in Windows Python? → Use Windows paths.

**"The daemon crashes silently"**

It doesn't. Run it in foreground to see output:
```bash
wsl -d Ubuntu -e bash -c "
  cd /mnt/d/Resonance_Engine/beast-build &&
  export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:/usr/lib/x86_64-linux-gnu:\$LD_LIBRARY_PATH &&
  ./khra_gixx_1024_stable 2>&1
"
```
If it exits immediately with no output, check `nvidia-smi` — the GPU may be
occupied by a stale CUDA context from a previous crash.

**"Coherence and Asymmetry values look wrong"**

| Coherence | Asymmetry | Diagnosis |
|-----------|-----------|-----------|
| ~0.74     | ~12-13    | CORRECT — Khra'gixx active, steady state |
| 1.000     | 0.000     | Khra'gixx injection disabled (check source) |
| 0.555     | 64.4      | Init bug — d_w read from host (use fixed binary) |
| NaN       | NaN       | Velocity diverged — omega too low or Mach limit hit |

---

## FILES THAT MATTER

```
beast-build/
├── khra_gixx_1024_stable.cu    ← PRODUCTION source (FIXED)
├── khra_gixx_1024_stable       ← Compiled binary
├── compile_khra_1024.sh        ← Build script
├── khra_gixx_1024.cu           ← Original (works, verbose debug output)
├── lbm_cuda_daemon.cu          ← 512x512 daemon (legacy, works)
├── lbm_1024x1024.cu            ← Alt 1024 daemon (no streaming kernel)
├── lbm_1024x1024_safe.cu       ← ⚠ HAS MEMORY LEAK — cudaMalloc in main loop
├── capture_state.py            ← Quick state grab (FIXED)
├── floating_creativity.py      ← Dynamic-T inquiry (FIXED)
├── manifested_reality_inquiry.py ← Scientist inquiry (FIXED)
├── DEFECT_REPORT_khra_1024.log ← What was wrong and why
├── RECOVERED_ALASKA_PHYSICS.log ← Forensic data recovery
└── SYSTEM_MANUAL.md            ← THIS FILE
```

**DO NOT USE `lbm_1024x1024_safe.cu`** — it has `cudaMalloc` inside the main loop,
leaking 36MB per cycle. It will consume all GPU memory within seconds.

---

## DO NOT

- Start multiple daemons on port 5556
- Use `zmq.NOBLOCK` in a loop instead of `zmq.Poller`
- Skip `time.sleep(1)` after `sub.connect()`
- Kill and restart the daemon when the subscriber fails to receive
- Use WSL paths (`/mnt/d/...`) in Windows Python file operations
- Read `__constant__` CUDA memory from host code
- Disable CUDA error checking
- Comment out the Khra'gixx injection in a file named "khra_gixx"
- Create more Python files instead of fixing the one that's broken
