# SYSTEM STATUS REPORT — Khra'gixx LBM Daemon & Infrastructure
**Date**: 2026-03-18 09:43 UTC (post-migration update)  
**Prepared for**: Helper agents working on the fractal-brain lattice Boltzmann system  
**Workspace**: `D:\fractal-brain\beast-build\`

> **CRITICAL CHANGE SINCE LAST REPORT**: The v2→v3 migration has been **COMPLETED SUCCESSFULLY**.
> v2 (PID 511939) is DEAD. v3 (PID 863906) is ALIVE with the loaded evolutionary state,
> autosave at 50k cycles, and a Python sentry monitor providing logic-triggered saves.
> The system is now **PROTECTED** — no longer a single point of failure.

---

## 1. RUNNING DAEMON — v3 (POST-MIGRATION)

| Field | Value |
|---|---|
| Binary | **`khra_gixx_1024_v3`** |
| PID | **863906** |
| Status | **ALIVE — Rl (Running)** |
| Started | 2026-03-18 09:25 UTC |
| Current Cycle | **~57,000+** (cycle reset to 0 on raw-format load; ~4.85M cycles of evolution preserved in state) |
| CPU Usage | 28.5% |
| RSS | 162,072 KB |
| Autosave | Every **50,000 cycles** (~8 min) |

### Previous Daemon (DEAD)
| Field | Value |
|---|---|
| Binary | `khra_gixx_1024_v2` |
| PID | 511939 (killed 2026-03-18 09:24 UTC) |
| Total Uptime | ~19h, ~4.85M cycles |
| Cause of Death | Clean `kill` during migration (state preserved via GDB extraction first) |

### Live Telemetry (ZMQ PUB on tcp://127.0.0.1:5556)
```json
{
  "cycle": 57360,
  "coherence": 0.7234,
  "asymmetry": 15.4847,
  "omega": 1.970,
  "khra_amp": 0.0300,
  "gixx_amp": 0.0080,
  "grid": 1024,
  "gpu_temp_c": 39,
  "gpu_power_w": 46.9,
  "gpu_mem_pct": 15.2
}
```

### GPU Hardware
| Field | Value |
|---|---|
| GPU | NVIDIA GeForce RTX 4090 |
| VRAM Used | ~3,084 MiB / 23,028 MiB (15.2%) |
| Temperature | 39°C |
| Power | 47W |
| CUDA | 12.6, arch sm_89 |

---

## 2. GRID ARCHITECTURE

- **Resolution**: 1024 × 1024 (D2Q9 lattice Boltzmann)
- **Double-buffered**: `d_f[0]` and `d_f[1]` alternate each step (stream → collide → swap)
- **State size per buffer**: 1024 × 1024 × 9 × float32 = **37,748,736 bytes (36 MB)**
- **Density field**: `d_rho` = 1024 × 1024 × float32 = **4,194,304 bytes (4 MB)**
- **Total VRAM footprint**: ~76 MB (2 × f_buffer + rho)

### Physics Parameters
| Parameter | Value | Range |
|---|---|---|
| omega (relaxation) | 1.970 | [0.5, 1.99] |
| khra_amp (large-scale wave) | 0.030 | [0.0, 0.2] |
| gixx_amp (fine-scale wave) | 0.008 | [0.0, 0.1] |

### Wave Functions (in collision kernel)
- **Khra**: `sin(2π·x/128 + cycle·0.025) · cos(2π·y/128 + cycle·0.015) · khra_amp`
- **Gixx**: `sin(2π·x/8 + cycle·0.4) · cos(2π·y/8 + cycle·0.35) · gixx_amp · asymmetry_factor`
- `asymmetry_factor = 1 + sin(cycle·0.05) · 0.5`

---

## 3. ZMQ COMMUNICATION

| Port | Socket | Direction | Purpose | Status |
|---|---|---|---|---|
| 5556 | PUB | Daemon → World | Telemetry JSON every 10 cycles | **LIVE** |
| 5557 | SUB | World → Daemon | Command channel | **LIVE** |

### v3 Command Set (current running daemon)
```
{"cmd":"set_omega","value":1.85}
{"cmd":"set_khra_amp","value":0.05}
{"cmd":"set_gixx_amp","value":0.01}
{"cmd":"reset_equilibrium"}
{"cmd":"save_state"}
{"cmd":"save_state","path":"/custom/dir"}
{"cmd":"load_state","path":"/path/to/checkpoint.bin"}
{"cmd":"set_autosave","interval":50000}
```

### IMPORTANT: JSON Format for Commands
**Commands MUST use compact JSON (no spaces after colons/commas).** The v3 parser's `strstr` searches for `"cmd":"` — if you send `"cmd": "` (with a space), the command is silently dropped. Use `json.dumps(..., separators=(",",":"))` in Python.

> **Bug fix in source**: `khra_gixx_1024_v3.cu` has been patched to accept both formats,
> but the running binary (compiled 09:13) still requires compact JSON. This fix takes
> effect on next recompile.

---

## 4. CHECKPOINT VAULT — MULTI-LAYER PROTECTION

The system now has **three layers** of state protection:

### Layer 1: GDB Hard Prints (pre-migration safety nets)
Two emergency extractions from the v2 daemon before it was killed:

| Checkpoint | Extraction Cycle | Time | Status |
|---|---|---|---|
| `checkpoint_20260318_090352/` | ~4,718,000 | 09:03 UTC | First-ever 1024 save |
| `checkpoint_20260318_092331/` | ~4,850,000 | 09:23 UTC | Pre-migration safety net |

Each contains: `d_f0.bin` (37,748,736 bytes), `d_f1.bin` (37,748,736 bytes, **THE ACTIVE STATE**), `d_rho.bin` (4,194,304 bytes).

**Validation of loaded state** (checkpoint_092331/d_f1.bin — the one injected into v3):
| Metric | Value | Meaning |
|---|---|---|
| Rho min | 0.3321 | Significant depletion zones |
| Rho max | 2.6641 | Dense accumulation regions |
| Rho mean | 1.0924 | Slight positive bias (evolved) |
| f[] nonzero | 100% (9,437,184 / 9,437,184) | **Fully evolved, no dead cells** |

### Layer 2: v3 Autosave (periodic, every 50,000 cycles)
v3's built-in autosave writes a CRC32-verified checkpoint with KHRG header to the daemon's working directory every 50,000 cycles (~8 min). Format: 64-byte header + 37,748,736 bytes raw f_data.

### Layer 3: Sentry Monitor (logic-triggered saves)
See Section 9 below. Saves to `sentry_saves/` on anomalous events.

### Sentry Save Files (as of 09:42 UTC)
**18 CRC32-verified checkpoints** in `sentry_saves/`, 649 MB total:
```
ckpt_20260318_093258_c15611.bin  (CRC32 0xC3909D02)
ckpt_20260318_093336_c18131.bin  (CRC32 0x24025614)
ckpt_20260318_093430_c21891.bin  (CRC32 0x61131472)
ckpt_20260318_093505_c24411.bin  (CRC32 0x3E8E863A)
... and 14 more through cycle ~55,321
```
All files are 37,748,800 bytes (64-byte KHRG header + 37,748,736 bytes f_data).

### Device Pointer Map (v2 era — for reference only, v3 has its own allocations)
| Symbol | GPU Address (v2) | Size |
|---|---|---|
| `d_f[0]` | `0x1b17a00000` | 37,748,736 |
| `d_f[1]` | `0x1b19e00000` | 37,748,736 |
| `d_rho` | `0x1b1c200000` | 4,194,304 |

### GDB Extraction Method (documented for future emergencies)
GDB attach → breakpoint at `usleep()` (CUDA idle between loop iterations) → `malloc` host staging buffer → `cudaMemcpy` Device-to-Host × 3 → `dump binary memory` to disk → `free` → `detach`. Scripts: `extract_vram.gdb` (original), `extract_fresh.gdb` (migration). All cudaMemcpy returned 0; daemon survived both extractions.

---

## 5. v3 DAEMON — NOW RUNNING

**Binary**: `khra_gixx_1024_v3` (1,050,232 bytes, compiled 2026-03-18 09:13)  
**Source**: `khra_gixx_1024_v3.cu` (patched post-compile for JSON tolerance — recompile needed for fix to take effect)  
**Compile script**: `compile_v3.sh`  
**PID**: 863906 | **Status**: ALIVE | **Started**: 09:25 UTC

### What v3 Has Over v2
All v2 functionality is preserved. Additions:

| Feature | Detail | Status |
|---|---|---|
| `save_state` command | Dumps `d_f[current]` to timestamped checkpoint via cudaMemcpy D2H + fwrite | Working |
| `load_state` command | Restores from checkpoint file, resumes at saved cycle count | Working |
| `set_autosave` command | Configure periodic autosave interval | Set to 50,000 cycles |
| CRC32 integrity | Every checkpoint has CRC32 of the f_data for corruption detection | Verified |
| Atomic write | Writes to `.tmp` then `rename()` to prevent partial files | Working |
| Dual format support | `load_state` accepts both v3 header format AND raw emergency-extract format (like the GDB dumps) | Used for migration |

### v3 Checkpoint File Format
```
Offset  Size  Field
0       4     Magic: "KHRG"
4       4     Version (uint32): 1
8       4     Cycle (uint32)
12      4     NX (uint32): 1024
16      4     NY (uint32): 1024
20      4     Q (uint32): 9
24      4     omega (float32)
28      4     khra_amp (float32)
32      4     gixx_amp (float32)
36      4     CRC32 of f_data (uint32)
40      24    Reserved (zeros)
64      —     Raw f_data: NX*NY*Q float32 (37,748,736 bytes)
```
**Total file size**: 37,748,800 bytes

### v3 Command Set (full)
```
{"cmd":"set_omega","value":1.85}
{"cmd":"set_khra_amp","value":0.05}
{"cmd":"set_gixx_amp","value":0.01}
{"cmd":"reset_equilibrium"}
{"cmd":"save_state"}
{"cmd":"save_state","path":"/custom/dir"}
{"cmd":"load_state","path":"/path/to/ckpt_YYYYMMDD_HHMMSS_cN.bin"}
{"cmd":"set_autosave","interval":50000}
```

---

## 6. MIGRATION LOG: v2 → v3 (COMPLETED)

Migration executed 2026-03-18 09:23–09:35 UTC. All steps successful.

| Step | Action | Result |
|---|---|---|
| 1. EXTRACT | Fresh GDB hard print from v2 (cycle ~4.85M) | `checkpoint_20260318_092331/` — all 3 cudaMemcpy rc=0 |
| 2. VERIFY | Validate rho min/max/mean + f[] nonzero | rho 0.332–2.664, mean 1.092, f[] 100% nonzero |
| 3. TERMINATE | `kill 511939` | v2 dead, ports freed |
| 4. RE-ANIMATE | `nohup ./khra_gixx_1024_v3` | PID 863906, ZMQ PUB 5556 + SUB 5557 bound |
| 5. LOAD | `{"cmd":"load_state","path":"...d_f1.bin"}` via ZMQ | `[CMD] Resumed at cycle 0`, Coh=0.723, Asym=15.59 |
| 6. HARDEN | `{"cmd":"set_autosave","interval":50000}` | `[CMD] Autosave interval → 50000 cycles` |
| 7. SENTRY | Started `sentry_monitor.py` (PID 866889) | 16 triggered saves by 09:42 UTC |

### Migration Complications & Fixes
- **ZMQ slow-joiner**: First `load_state` send was silently dropped. Fixed by holding connection open with retry loop.
- **JSON parser bug**: v3's `strstr(msg, "\"cmd\":\"")` rejects `"cmd": "` (with space after colon). Python's `json.dumps` adds that space by default. **Fix**: Use `separators=(",",":")` for compact JSON. Source patched for next recompile.
- **Sentry save path**: v3's `save_checkpoint` expects a **directory** (it generates the filename internally). First sentry version passed a full file path → `fopen` failed. Fixed to pass `SAVE_DIR` directory.

### State Continuity Verification
| Metric | Before Load (equilibrium) | After Load (evolved state) |
|---|---|---|
| Coherence | 0.740 | 0.723 |
| Asymmetry | 12.34 | 15.59 |
| Cycle | rising from 0 | reset to 0 (raw format) |

The coherence/asymmetry fingerprint change confirms the evolved state was successfully injected — not running from fresh equilibrium.

---

## 7. CODEBASE INVENTORY

### Source Files (24 .cu files)
**Active/relevant:**
| File | Purpose |
|---|---|
| `khra_gixx_1024_v2.cu` | Running daemon source (bidirectional + NVML) |
| `khra_gixx_1024_v3.cu` | **Next-gen daemon with checkpoint support** |
| `khra_gixx_1024_stable.cu` | Prior stable version (magnifying-glass asymmetry) |
| `khra_gixx_1024.cu` | Original khra-gixx implementation |
| `khra_gixx_resonance.cu` | Loads etch files, runs resonance experiments |
| `beast_somatic.cu` | **Only file that ever saved etch files** (512×512, rho+ux+uy only) |
| `lbm_cuda_daemon.cu` | Original 512×512 daemon (port 5555) |
| `lbm_1024x1024.cu` | Basic 1024 daemon (no ZMQ, no NVML) |

**Test/experiment files**: 8 `test_*.cu` files + `experiment_a.cu`, `polyphonic_etch.cu`, `topological_etch.cu`, `somatic_bridge.cu`, `harmonic_virtual_memory.cu`, `harmonic_vm_simple.cu`, `lbm_1024x1024_forge.cu`, `lbm_1024x1024_safe.cu`

### Etch Files (52 .bin files in beast-build)
- 49 periodic etch saves from `beast_somatic.cu` (512×512 format, `etch_00010000.bin` through `etch_00490000.bin`, 3,145,728 bytes each)
- `etch_khragixx.bin` — resonance experiment output
- `craw_hardened_habit_200k.bin` — 18,874,388 bytes (20-byte header + 2×f[], 512×512)
- `evolution_etch_2600.bin` — 18,874,388 bytes (same large format)

**IMPORTANT**: All 52 etch files are 512×512 format. The 1024×1024 grid had NEVER been saved prior to the hard print checkpoint.

### Other Infrastructure
| File | Purpose |
|---|---|
| `fractal_bridge.py` | Ollama bridge with context retention, chronicle, drift detection, brake |
| `sentry_monitor.py` | **Logic-triggered checkpoint sentry** (see Section 9) |
| `chronicle.jsonl` | 30 entries from prior bridge sessions |
| `compile_v2.sh` | Build script for v2 |
| `compile_v3.sh` | Build script for v3 |
| `compile_daemon.sh` | Build script for lbm_cuda_daemon (512×512) |
| `extract_vram.gdb` | GDB script: original emergency extraction |
| `extract_fresh.gdb` | GDB script: pre-migration extraction |
| `v3_stdout.log` | v3 daemon stdout (console output, save confirmations) |
| `sentry_stdout.log` | Sentry monitor stdout (heartbeats, trigger events) |

---

## 8. KNOWN LIMITATIONS & FUTURE WORK

### Resolved Since Last Report
- ~~v2 has no save capability~~ → v3 deployed with save/load/autosave
- ~~Single point of failure~~ → Autosave (50k cycles) + sentry (logic-triggered) + two GDB hard prints
- ~~Logic-triggered saves not implemented~~ → `sentry_monitor.py` running with 3 trigger types

### Still Outstanding
- **No signal handlers** — SIGTERM/SIGINT still kill v3 without saving. Adding a handler that calls `save_checkpoint` on signal is recommended.
- **Checkpoint rotation not implemented** — sentry saves are accumulating at ~36 MB each. At current trigger rate (~16 saves in 20 min), disk will fill. Need a pruning strategy: keep N most recent + milestone saves.
- **JSON parser bug in running binary** — The source is patched but the running v3 binary still requires compact JSON (no spaces). Needs recompile to apply fix. Low priority since sentry and all tooling now use compact JSON.
- **Cycle counter reset** — v3 cycle counter reset to 0 on raw-format load. The daemon has been evolving since then (~57k+ cycles), but the absolute cycle count from v2 (~4.85M) is lost in telemetry. Metadata in the GDB hard prints records the original count.
- **Recovery validation** — On load, there is no automatic coherence/asymmetry sanity check. Future improvement: run 10 test cycles and compare to expected ranges.
- **Sentry trigger tuning** — The asymmetry spike trigger (>2σ) fires frequently (~16 times in 20 min). May need to widen the threshold or increase the rolling window size to reduce save frequency.

### Data Layout Note for Any Agent Working With Checkpoints
The f[] array layout is `h_f[(y*NX+x)*Q + i]` where:
- `y` ∈ [0, 1023], `x` ∈ [0, 1023], `i` ∈ [0, 8] (D2Q9 directions)
- Direction vectors: cx = {0,1,0,-1,0,1,-1,-1,1}, cy = {0,0,1,0,-1,1,1,-1,-1}
- Weights: {4/9, 1/9, 1/9, 1/9, 1/9, 1/36, 1/36, 1/36, 1/36}
- At equilibrium: `f[i] = w[i] * rho * (1 + 3·eu + 4.5·eu² - 1.5·u²)`

---

## 9. SENTRY MONITOR

**Script**: `sentry_monitor.py`  
**PID**: 866889  
**Status**: ALIVE  
**Save count**: 16+ triggered saves (as of 09:42 UTC)

### Architecture
Python process subscribing to v3's ZMQ PUB (port 5556), sending `save_state` commands on ZMQ PUB→SUB (port 5557) when anomalous events detected.

### Trigger Conditions
| Trigger | Threshold | How It Works |
|---|---|---|
| Coherence shift | > 0.05 | Compares mean of last 5 readings vs. older readings in a 50-sample rolling window |
| GPU temperature | > 75°C | Immediate save if thermal throttling is imminent |
| Asymmetry spike | > 2σ | Fires if current asymmetry is >2 standard deviations from rolling window mean |

### Configuration
| Setting | Value |
|---|---|
| Rolling window | 50 samples |
| Save cooldown | 30 seconds (prevents save storms) |
| Save directory | `sentry_saves/` |
| ZMQ JSON format | Compact (`separators=(",",":")`) — required by running v3 binary |

### Logs
- `sentry_stdout.log` — heartbeats (every 100 messages), save events, warnings
- Heartbeat format: `[SENTRY] heartbeat: cycle=N, coh=X, asym=Y, temp=Z, saves=N`

---

## 10. SUMMARY

The system is a 1024×1024 D2Q9 lattice Boltzmann simulation running as a CUDA daemon (`khra_gixx_1024_v3`, PID 863906) on an RTX 4090 under WSL2 Ubuntu. It carries ~4.85 million cycles of continuous evolution with khra-gixx wave perturbations driving non-equilibrium structure formation.

**On 2026-03-18, the system underwent a successful organ transplant**: the evolutionary state was extracted from the v2 daemon (which had no save capability) via GDB VRAM extraction, v2 was terminated, v3 was started and loaded with the extracted state, autosave was hardened to 50k cycles, and a Python sentry monitor was deployed for logic-triggered saves.

The system is now **protected at three levels**: (1) v3 autosave every 50k cycles, (2) sentry-triggered saves on coherence shifts, thermal events, and asymmetry spikes, (3) two GDB hard prints in vault.

**Current priorities**:
1. **Tune sentry thresholds** — asymmetry trigger is firing too often (~16 saves in 20 min, 649 MB). Consider widening 2σ to 3σ or increasing window size.
2. **Implement checkpoint rotation** — prune old sentry saves to prevent disk fill.
3. **Add signal handler to v3** — catch SIGTERM/SIGINT → save before exit.
4. **Recompile v3** — apply the JSON parser space-tolerance fix already in source.
