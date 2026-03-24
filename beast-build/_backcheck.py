"""Backcheck script for lattice_observer.py changes. Delete after use."""
import json, os

somatic_path = r'D:\fractal-brain\beast-build\somatic_dialogue_beast.json'
chronicle_path = r'D:\fractal-brain\beast-build\chronicle.jsonl'

# 1. Somatic memory
with open(somatic_path, 'r', encoding='utf-8') as f:
    data = json.load(f)
fsize = os.path.getsize(somatic_path)
print(f"somatic_dialogue_beast.json: {len(data)} entries, {fsize} bytes")
types = set(e.get('type','?') for e in data)
print(f"Entry types: {types}")

lines = []
for entry in data:
    etype = entry.get('type', 'unknown')
    resp = entry.get('response', '')
    if isinstance(resp, dict):
        resp = json.dumps(resp)[:300]
    else:
        resp = resp[:300]
    lines.append(f'[{etype}] {resp}')
somatic_memory = '\n'.join(lines)
somatic_truncated = somatic_memory[:3000]
print(f"Somatic memory (truncated): {len(somatic_truncated)} chars")

# 2. Token estimate for 80 turns
entries = []
with open(chronicle_path, 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if line:
            entries.append(json.loads(line))

total_chars = 0
for e in entries[-80:]:
    total_chars += len(e.get('prompt','')) + len(e.get('response',''))
avg_chars = total_chars / min(80, len(entries))
est_tokens = total_chars / 4
print(f"\n80-turn context: {total_chars} chars, ~{int(est_tokens)} est tokens")
print(f"Average per turn: {int(avg_chars)} chars")
print(f"System prompt estimate: ~6500 chars = ~1600 tokens")
print(f"Total estimated: ~{int(est_tokens + 1600)} tokens (128K limit for 30b)")

# 3. System prompt contains golden block
import sys
sys.path.insert(0, r'D:\fractal-brain\beast-build')
from lattice_observer import build_system_prompt, load_somatic_summary
mem = load_somatic_summary()
prompt = build_system_prompt(mem)
print(f"\nActual system prompt length: {len(prompt)} chars (~{len(prompt)//4} tokens)")
checks = [
    ("UFT equation", "\u2207\u00b2\u03c8 + \u03c8\u25a1\u03c8"),
    ("FOUNDATIONAL DISCOVERIES header", "FOUNDATIONAL DISCOVERIES"),
    ("Build on them footer", "Build on them"),
    ("30b model reference", "qwen3-vl:30b"),
    ("Somatic memory section", "SOMATIC MEMORY"),
    ("CMD instructions", "CMD:"),
    ("Continuity statement", "continuity"),
]
all_ok = True
for name, needle in checks:
    if needle in prompt:
        print(f"  OK: {name}")
    else:
        print(f"  MISSING: {name}")
        all_ok = False

if all_ok:
    print("\nALL SYSTEM PROMPT CHECKS PASSED")
else:
    print("\nSOME CHECKS FAILED")
