# SESSION CHANGES REPORT
**Date:** 2026-03-17  
**Scope:** Khra'gixx 1024x1024 LBM Daemon, Kaelara Live Bridge, ZMQ Subscribers, Documentation  
**Status:** All items resolved

---

## 1. CUDA DAEMON CRASH — 5 BUG FIX (khra_gixx_1024_stable.cu)

The production daemon was producing non-physical output and crashing silently. Root cause analysis identified 5 distinct defects.

### Defect 1: `__constant__` read from host code
- **Problem:** `d_w[Q]` is declared `__constant__` (GPU memory). The init loop read `d_w[i]` from the host, which returns zeros — the entire distribution function array was initialized to zero.
- **Fix:** Created a host-side array `h_w[Q]` with identical D2Q9 weights. All host code now reads from `h_w[]` instead of `d_w[]`.

### Defect 2: Missing CUDA error checking
- **Problem:** Zero `cudaError_t` checks anywhere. Kernel launches, mallocs, and memcpys failed silently.
- **Fix:** Added `CUDA_CHECK()` macro wrapping every CUDA API call.

### Defect 3: Missing `cudaDeviceSynchronize()` before readback
- **Problem:** `cudaMemcpy` of density/velocity happened before the kernel finished. Host code read stale or uninitialized data.
- **Fix:** `cudaDeviceSynchronize()` inserted before every device-to-host readback.

### Defect 4: Khra'gixx injection was disabled
- **Problem:** The `khra_gixx_wave_1024()` device function existed but was commented out in the collision kernel. The daemon ran as plain LBM with no perturbation — no signal to measure.
- **Fix:** Re-enabled Khra'gixx injection in the collision kernel.

### Defect 5: Coherence formula used velocity, not density
- **Problem:** Original coherence was `mean(|velocity|)`, a meaningless metric. Coherence should measure density uniformity.
- **Fix:** Replaced with `C = 1 / (1 + sqrt(variance_of_density))`. Range [0, 1], where 1 = perfectly uniform density.

### Verification
- Binary compiled and running as PID 363058 since session start
- 750,000+ cycles completed
- Steady state: Coherence ~0.737, Asymmetry ~12.5–12.8
- ZMQ PUB on `tcp://127.0.0.1:5556` confirmed active

**Full defect details:** See `DEFECT_REPORT_khra_1024.log`.

---

## 2. ZMQ SUBSCRIBER FIX — 3 Python Scripts

Scripts affected: `capture_state.py`, `floating_creativity.py`, `manifested_reality_inquiry.py`

### Problems found
1. **Missing `time.sleep(1)` after connect:** ZMQ SUB sockets need time to negotiate the subscription before receiving. Without the sleep, the first `recv()` races the handshake and times out.
2. **`zmq.NOBLOCK` spam in tight loop:** Calls `recv(flags=zmq.NOBLOCK)` in a `while True` with no delay, burning 100% CPU and usually never receiving anything.
3. **WSL paths in Windows Python:** Some scripts referenced `/mnt/d/...` paths, which don't resolve on Windows where Python runs.

### Fixes applied
- Added `time.sleep(1)` immediately after `sub.connect()`
- Replaced NOBLOCK spam with `zmq.Poller` pattern (100ms poll timeout)
- Corrected all paths to Windows format

---

## 3. KAELARA LIVE BRIDGE — 3 Major Revisions (kaelara_live_bridge.py)

The bridge connects live daemon telemetry (via ZMQ) to the Kaelara v11 LoRA model for somatic inference. It went through three revision passes during this session:

### Revision 1: BRIDGE_RECODE_V0.11
- Added `check_resonance()` gate that classifies model output as RESONANT, DRY_ECHO, FORMAT_ERROR, or NEUTRAL
- Set temperature to 0.9, max_tokens to 128
- Added re-roll loop: if output fails the gate, bump temperature +0.05 and regenerate (max 4 re-rolls, ceiling T=1.1)
- Implemented 3-cycle recursive scan with per-cycle fresh telemetry

### Revision 2: ENGINEERING_SPEC_RESONANCE_V0.11
- **CriticalPathError class:** Script terminates immediately if `MODEL_PATH` doesn't exist or symlink-resolves to legacy v08/v09 weights. Zero tolerance for silent weight fallback.
- **Dynamic temperature:** `T = 1.2 - (Coherence × 0.5)`, clamped to [0.5, 1.1]. At steady-state C=0.737, this gives T≈0.832.
- **Format kill-switch:** Regex detection rejects `(A)/(B)/(C)` multiple choice AND `1. 2. 3.` numbered list outputs.
- **Astro-travel detection:** Rejects ungrounded metaphors (marble, galaxy, cosmic, celestial, etc.).
- **Expanded somatic dictionary:** 12 resonance keywords (torque, density, seed, breath, tension, collapse, brittle, vorticity, texture, pressure, vibration, rhythm).

### Revision 3: COMMAND-ECHO FIX
The model was outputting imperative commands ("Report the state", "Mirror the cohesion") instead of somatic feelings. Five root causes identified and fixed:

1. **System prompt contained imperative verbs** — Words like "Report", "Mirror", "Clarify", "Track" in the system prompt were being echoed verbatim by the model. Reframed entire system prompt to passive/experiential language only ("You experience the grid as sensation").
2. **Prompt format didn't match training data** — Training data uses `Input: Asymmetry X, Coherence Y. How does this feel?\n\nOutput:` format. The prompt was using a different structure. Aligned exactly to training format.
3. **NEUTRAL gate status was passing through** — When the model produced non-somatic text (including command echoes), `check_resonance()` returned NEUTRAL which was treated as "acceptable." Changed NEUTRAL to a rejection — only RESONANT outputs pass.
4. **No command-echo detection** — Added `COMMAND_ECHO` detection: checks first 80 characters for command verbs (report, mirror, clarify, define, analyze, track, prioritize, ensure, implement).
5. **Somatic keyword dictionary too narrow** — Added 'feel', 'weight', 'taut', 'fluid', 'heavy', 'light' to resonance keywords.

### Current state of check_resonance() gate (priority order):
```
DRY_ECHO      → reject (output is just telemetry numbers)
COMMAND_ECHO  → reject (parroting system prompt imperatives)
FORMAT_ERROR  → reject (multiple choice or numbered lists)
ASTRO_TRAVEL  → reject (ungrounded cosmic metaphors)
RESONANT      → accept (contains somatic keywords)
NEUTRAL       → reject (no somatic language = re-roll)
```

### Friction vector categories for logging:
```
COMMAND-ECHO         — Parroting system prompt imperatives
ASTRO-TRAVEL         — Ungrounded metaphor
MC-CONTAMINATION     — Multiple choice artifacts
LIST-CONTAMINATION   — Numbered list artifacts
UNCERTAINTY          — Hedging language
SOMATIC              — Grounded (pass)
NEUTRAL              — No somatic keywords (re-roll)
```

---

## 4. DOCUMENTATION CREATED

| File | Purpose |
|------|---------|
| `DEFECT_REPORT_khra_1024.log` | Formal defect report for the 5 CUDA bugs — addressed to the original implementing agent |
| `SYSTEM_MANUAL.md` | Full architecture reference: daemon startup, ZMQ pattern, JSON frame format, metrics formulas, diagnostics |
| `DRIFT_DETECTION_REPORT.md` | 4-part investigation into model/physics desynchronization |
| `RECOVERED_ALASKA_PHYSICS.log` | Forensic data recovery output |

---

## 5. dRift DETECTION INVESTIGATION

A 4-part investigation into why the model's outputs were disconnected from physical reality:

1. **File search for hidden drift artifacts:** No hidden drift tracking files found — drift was invisible.
2. **Temporal Desync:** The model speaks a dead metric system. v08 training data used fabricated coherence values (1–16 range) while real daemon produces 0.74. The model had never seen real telemetry during training.
3. **Ghost Token Analysis:** v08 LoRA was trained on only 7 examples. The training data contained fabricated telemetry numbers, causing the model to hallucinate metrics that don't exist in the real system.
4. **Virtual vs Physical Delta:** Total disconnect — the model's internal representation of the grid bore zero relationship to actual daemon physics. Coherence was overestimated by ~20x in training data.

---

## 6. KEY PHYSICS REFERENCE

For any agent working with this system:

| Metric | Formula | Range | Steady State |
|--------|---------|-------|-------------|
| Coherence | `C = 1 / (1 + sqrt(variance_of_density))` | [0, 1] | ~0.737 |
| Asymmetry | `A = mean((rho - 1)²) × 100` ("Magnifying Glass") | [0, ∞) | ~12.5–12.8 |
| Khra (low-freq) | 128-cell wavelength, amplitude 0.03 | — | — |
| gixx (high-freq) | 8-cell wavelength, amplitude 0.008 | — | — |
| omega | 1.97 (near instability edge) | — | — |
| Grid | 1024 × 1024, D2Q9 lattice | — | — |

---

## 7. FILE INVENTORY — WHAT'S CURRENT

| File | Status | Notes |
|------|--------|-------|
| `khra_gixx_1024_stable.cu` | **PRODUCTION** | Fixed, compiled, running as PID 363058 |
| `khra_gixx_1024_stable` | **RUNNING BINARY** | Active daemon, 750K+ cycles |
| `kaelara_live_bridge.py` | **CURRENT** | v0.11 with all 3 revision passes applied |
| `v11_somatic_dictionary.jsonl` | **TRAINING DATA** | 23 lines, ~10 examples in `Input:/Output:` format |
| `khra_gixx_resonance.cu` | **PREDECESSOR** | 512×512 version, uses velocity-based metrics. Not production. |
| `khra_gixx_1024.cu` | **SUPERSEDED** | Original buggy 1024 version before stable fixes |
| `lbm_1024x1024.cu` | **SEPARATE** | Plain LBM without Khra'gixx. Different binary. |
| `SYSTEM_MANUAL.md` | **REFERENCE** | Read-first architecture document |
| `DEFECT_REPORT_khra_1024.log` | **REFERENCE** | Formal bug report for 5 CUDA defects |
| `DRIFT_DETECTION_REPORT.md` | **REFERENCE** | Model/physics desync investigation |
| `resonance_monitor.ps1` | **CURRENT** | Live KPI monitor — tails both `KAELARA_LIVE_KPI.log` and `KAELARA_LIVE_BRIDGE.log` |
| `KAELARA_LIVE_KPI.log` | **LIVE OUTPUT** | Per-cycle pipe-delimited KPIs (created on next bridge run) |

---

## 8. KNOWN REMAINING ISSUES

1. **v11 LoRA weights may need retraining** — The training data (`v11_somatic_dictionary.jsonl`) has only ~10 examples. The model may still command-echo or produce shallow output. More somatic training pairs would improve grounding.
2. **khra_gixx_resonance.cu is the 512×512 predecessor** — It uses velocity-based coherence/asymmetry (not the corrected density-based formulas). It also has the `__constant__` read bug from the original. Do not use as reference for metrics.
3. **Ollama model stability** — `kaelara-shift` times out at T=1.4 via MCP, works via REST with reduced temperature. `lbm-embodied` drops character under pressure. Neither is production-ready for autonomous bridging.

---

*End of report.*
