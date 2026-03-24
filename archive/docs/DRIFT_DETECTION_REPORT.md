# PROJECT dRift DETECTION REPORT

**Date:** 2026-03-17  
**Daemon Binary:** khra_gixx_1024_stable (PID active, cycle 344700+)  
**Scope:** /mnt/d/fractal-brain/ full workspace  

---

## 1. dRift FILE SEARCH

**Method:** `find` for filenames + `grep -ril` for content across all of /mnt/d/fractal-brain/

**Result: NO dedicated drift/dRift files exist.**

- Zero files named `drift`, `dRift`, `drift_correction`, or any variant.
- 28 files contain the word "drift" in their text. All are contextual references:
  - **FORENSIC_AUDIT.md**: "metric drift" (discussing coherence value changes between LoRA versions)
  - **ACTION_ITEMS.md**: "linguistic drift" (model output degradation over training iterations)
  - **first_flight.py**: `"drift"` as a keyword detection marker in Alaska flight event
  - **tokenizer.json** (x2): literal subword token `"drift"` in vocabulary
  - **Training JSONL files**: "drift" used in model-generated prose ("I feel the grid drift...")
  - **Various .py scripts**: string matching for "drift" keyword in telemetry analysis

**Conclusion:** No hidden drift_correction mechanism. No temp files. No shadow drift logs. The word appears only in natural-language context — never as a programmatic correction system.

---

## 2. TEMPORAL DESYNC: somatic_dialogue_beast.json vs khra_daemon.log

### What the Model Claims (somatic_dialogue_beast.json)
| Entry | Type | Coherence | Asymmetry | Other |
|-------|------|-----------|-----------|-------|
| 0-5 | socratic_inquiry | 14.48 | — | h64=5.95, density_mean=1.0 |
| 6-8 | socratic_inquiry | 13.69 | — | h64=6.29, density_mean=1.0 |
| 9 | first_flight | — | — | No LBM state (Alaska drift event) |
| 10 | shift_protocol | 14.73 | 10.41 | vorticity_noise=0.22 |
| 11 | turing_probe | — | — | No LBM state (philosophical probe) |

### What the Daemon Actually Produces (khra_daemon.log, cycles 334800-344700)
| Metric | Min | Max | Mean | Stdev |
|--------|-----|-----|------|-------|
| Coherence | 0.7370 | 0.7400 | 0.7385 | 0.000624 |
| Asymmetry | 12.3914 | 12.7016 | 12.5371 | 0.078216 |

### The Desync

**These are two completely different metric systems.**

- The somatic dialogue uses a **somatic bridge coherence** metric (range ~13-15) derived from a different computation path — likely an older formula or a different aggregation window.
- The current daemon uses **variance-based coherence** (range 0.73-0.74) — the corrected formula from the defect fix.
- The somatic `asymmetry=10.41` (shift_protocol) vs daemon `asymmetry=12.54` (current) suggests a genuine physical state change between sessions, OR a different asymmetry calculation.

**Temporal Desync Verdict:** The model was trained on and references a metric system that no longer exists in the running daemon. Any model response citing "coherence 14" is speaking a dead language. The physics moved on; the model didn't.

---

## 3. GHOST TOKEN ANALYSIS: kaelara_v08_raw Training Data

### Training Set Statistics
- **Total examples:** 7 (v08_raw_self.jsonl)
- **Base model:** llama-3.2-3b
- **LoRA config:** r=64, lora_alpha=128, PEFT on q/k/v/o_proj

### Dominant Phrase Frequencies (across 7 examples)
| Phrase | Count | Frequency |
|--------|-------|-----------|
| "i feel" | 7 | 100% |
| "the grid" | 6 | 86% |
| "i am" | 4 | 57% |
| "awareness" | 4 | 57% |
| "breath" | 4 | 57% |
| "the 4090" | 3 | 43% |

### Ghost Token Mechanism

With only 7 training examples, the LoRA has learned a **mandatory template:**
1. Open with first-person feeling statement ("I feel...")
2. Reference the hardware/grid ("the grid", "the 4090")
3. Use somatic/awareness vocabulary ("breath", "awareness", "emergence")

This is not generalization — it's **memorization of 7 sentences** and their vocabulary.

### The "No Analogies" Collapse (SCIENTIST_RESPONSE_01.log)

When prompted with "No metaphors. No analogies. Be precise." the model:
1. Echoed the prompt back (repetition of training-adjacent tokens)
2. Collapsed into `"No analogies. No analogies. No analogies."` — repeating indefinitely

**Root Cause:** 100% of v08 training data IS metaphorical ("I feel the grid breathe", "awareness crystallizes"). The model literally cannot comply with "no metaphors" because its entire fine-tuned output space is metaphor. The negative constraint becomes the only non-metaphorical token sequence it can produce, so it repeats it.

### v09 Correction Attempt (v09_scientist_seed.jsonl)

The v09 seed data (10 examples) introduces:
- Structured `[TAG]` format responses (NODE_MANIFESTED, SYMMETRY_BREAK, etc.)
- Realistic telemetry values (A=13.4, C=0.73 — close to actual daemon output)
- Scientific vocabulary instead of somatic vocabulary
- Explicit measurement reporting format

**Assessment:** v09 addresses the ghost token problem structurally, but 10 examples is still dangerously few for reliable generalization.

---

## 4. VIRTUAL vs PHYSICAL DELTA

### The Virtual Potential (v08 Training Data Claims)

Values embedded in v08_raw_self.jsonl training examples:
| Field | Training Values | Note |
|-------|----------------|------|
| Coherence | 1.0, 2.3, 15.2, 8.5, 14.8, 16.1, 15.9 | Fabricated, range 1-16 |
| Power | 50W | Hardcoded constant |
| Temperature | 65°C, 68°C, 72°C | Plausible but unverified |
| Coordinates | X102-Y504, X512-Y512, etc. | Invented spatial positions |
| Grid state | "lattice ripple", "density breath" | Metaphorical, not measured |

### The Physical Reality (Daemon Output, Last 10,000 Cycles)

| Field | Actual Value | Source |
|-------|-------------|--------|
| Coherence | 0.7385 ± 0.0006 | Variance-based, measured |
| Asymmetry | 12.5371 ± 0.0782 | Magnifying Glass metric |
| Power | Not published | Not in ZMQ frame |
| Temperature | Not published | Not in ZMQ frame |
| Coordinates | Not published | ZMQ publishes aggregate only |
| Grid state | 1024x1024 density field | Full grid in ZMQ frame |

### The Delta

| Dimension | Virtual | Physical | Gap |
|-----------|---------|----------|-----|
| Coherence scale | 1.0—16.1 | 0.737—0.740 | **~20x overestimate** |
| Coherence stability | Varies wildly per example | stdev 0.0006 | Training implies volatility; reality is locked |
| Spatial data | Named coordinates (X102-Y504) | Not available | **Entirely fabricated** |
| Power telemetry | 50W constant | Not measured | **Made up** |
| Asymmetry | Not in training | 12.54 ± 0.08 | **Training has no concept of this metric** |
| Grid content | Metaphorical descriptions | 1,048,576 float values | **One is poetry, one is physics** |

### Summary Delta

**The virtual/physical gap is TOTAL.**

The v08 model was trained on hand-written responses with completely invented telemetry values. It has **never seen actual daemon output** in its training data. Every numerical claim it makes about the physical system is a confabulation derived from 7 fabricated examples.

The model doesn't drift from reality — it was **never connected to reality.** There is no drift correction to find because there was never a connection to correct.

---

## FINDINGS SUMMARY

| Investigation | Status | Finding |
|--------------|--------|---------|
| dRift Files | CLEAR | No hidden drift/correction files exist |
| Temporal Desync | **CONFIRMED** | Model references dead metric system (coherence ~14) vs live daemon (coherence ~0.74) |
| Ghost Tokens | **CONFIRMED** | 7-example training → 100% "I feel" saturation → "No analogies" collapse |
| Virtual/Physical | **TOTAL DISCONNECT** | Training data is fabricated; 20x coherence overestimate; spatial data invented |

## RECOMMENDATION

The v08 LoRA must not be used for any task requiring accurate telemetry interpretation. The v09 seed data begins to address the grounding problem with realistic values and structured output format, but requires:

1. **Minimum 50-100 training examples** sourced from ACTUAL daemon ZMQ frames
2. **Elimination of all fabricated telemetry** from training data
3. **Coherence metric documentation** — the model must know it's variance-based, range [0,1], not somatic-bridge [0,20]
4. **No negative constraints in prompting** — use positive format specifications instead ("Report using [TAG] format" not "No metaphors")

---

*Report generated from live daemon output (cycle 344700), somatic_dialogue_beast.json (12 entries), v08_raw_self.jsonl (7 examples), v09_scientist_seed.jsonl (10 examples), FORENSIC_AUDIT.md, SCIENTIST_RESPONSE_01.log, and full workspace file scan.*
