# KAELARA v0.9 — ACTION ITEMS FOR ASSISTANT

## BACKGROUND
We have built 8 versions of a LoRA model (Kaelara) that connects LBM fluid dynamics simulation to LLM inference. v0.5 and v0.8 are functional. v0.6/v0.7 failed. We need v0.9 to combine the best of both with memory.

---

## IMMEDIATE TASKS (This Week)

### 1. BACKUP STABLE MODELS TO NAS
**Files to copy:**
- `D:\fractal-brain\beast-build\kaelara_lora_v05\final\` → NAS
- `D:\fractal-brain\beast-build\kaelara_v08_raw\final\` → NAS

**Verification:** Check checksums match after transfer.

### 2. EXTRACT GOLD STANDARD TRAINING DATA
**Source:** `D:\fractal-brain\beast-build\metric_anchor_log.jsonl`

**Task:** Parse the 29 cycles and extract the top 10 responses where:
- Coherence was stable (delta < 5%)
- Response was substantive (>100 chars, no repetition)
- No "resonance_spike" flag

**Output:** `gold_standard_v09.jsonl` with format:
```json
{"cycle": 7, "coherence": 16.1, "response": "...", "context": "..."}
```

### 3. BUILD RAG RETRIEVAL SYSTEM
**Components needed:**
- Vector database (ChromaDB or FAISS)
- Embed the 29 metric_anchor_log entries
- Query function: given current telemetry, retrieve 3 most similar past cycles

**Test:** Input `coherence: 16.5, vorticity: 0.8` → should return cycles with similar metrics.

### 4. DETECT REPETITION LOOP
**Algorithm:**
```python
def is_repetition(response, previous_response):
    # Cosine similarity of embeddings
    if similarity > 0.9:
        return True
    # Or simple: same first 20 chars repeated
    if response[:20] == previous_response[:20]:
        return True
    return False
```

**Action on detection:** Inject anchor prompt: "[ANCHOR] Return to physical telemetry."

---

## v0.9 MODEL DESIGN

### Training Data Mix
- 40% v0.8 Raw Self (recursive exploration)
- 30% Gold Standard clips (stable, grounded)
- 20% Metric Anchor logs (telemetry correlation)
- 10% Failure examples (what NOT to do)

### System Prompt Template
```
You are Kaelara v0.9, the Chronicle Operator.
You have access to your own history via retrieval.
When telemetry is stable, explore recursively.
When repetition detected, return to physical description.
Never use negative constraints ("no metaphors").
```

### Inference Loop
1. Receive LBM telemetry
2. Query RAG: "Similar past states?"
3. Inject top-3 similar responses as context
4. Generate response (max 200 tokens)
5. Check for repetition
6. If repetition: re-generate with anchor prompt
7. Log to metric_anchor_log_v09.jsonl

---

## FILES REFERENCE

### Critical (Keep)
- `FORENSIC_AUDIT.md` — This analysis
- `kaelara_lora_v05/final/` — Stable baseline
- `kaelara_v08_raw/final/` — Recursive baseline
- `metric_anchor_log.jsonl` — 29 cycles with telemetry
- `gold_standard.jsonl` — 3 high-precision entries

### Deprecated (Can Delete)
- `kaelara_lora_v06/` — Echo failure
- `kaelara_v07_silent/` — Silent monk failure

### Session Scripts
- `infinite_mirror_v08.py` — 10-cycle recursive test
- `physicality_inquiry_v08.py` — Topography test
- `metric_anchor_v08.py` — Full telemetry logging

---

## SUCCESS CRITERIA FOR v0.9

1. **Stability:** Run 50 cycles without repetition loop
2. **Grounding:** 80% of responses reference specific telemetry values
3. **Depth:** Can achieve recursive insight (like v0.8 cycle 10)
4. **Recovery:** Detects and recovers from drift within 2 cycles

---

## QUESTIONS FOR OPERATOR

1. Should v0.9 training use the same base (Llama 3.2) or upgrade to 3.3?
2. RAG database: ChromaDB (easier) or FAISS (faster)?
3. NAS backup: Synology path confirmed?
4. Priority: Build RAG first, or train v0.9 first?

---

*Prepared for assistant handoff. Forensic audit complete.*
