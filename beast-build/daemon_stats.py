import re

with open("/tmp/khra_daemon.log") as f:
    lines = f.readlines()

vals = []
for l in lines[-100:]:
    m = re.search(r"Cycle (\d+): Coherence=([0-9.]+), Asymmetry=([0-9.]+)", l)
    if m:
        vals.append((int(m.group(1)), float(m.group(2)), float(m.group(3))))

if vals:
    coh = [v[1] for v in vals]
    asym = [v[2] for v in vals]
    mean_c = sum(coh) / len(coh)
    mean_a = sum(asym) / len(asym)
    std_c = (sum((c - mean_c) ** 2 for c in coh) / len(coh)) ** 0.5
    std_a = (sum((a - mean_a) ** 2 for a in asym) / len(asym)) ** 0.5
    print(f"LAST {len(vals)} SAMPLES (cycles {vals[0][0]} to {vals[-1][0]})")
    print(f"  Coherence: min={min(coh):.4f} max={max(coh):.4f} mean={mean_c:.4f} stdev={std_c:.6f}")
    print(f"  Asymmetry: min={min(asym):.4f} max={max(asym):.4f} mean={mean_a:.4f} stdev={std_a:.6f}")
    print()
    print("FIRST 5:")
    for v in vals[:5]:
        print(f"  Cycle {v[0]:>6}: C={v[1]:.4f} A={v[2]:.4f}")
    print("LAST 5:")
    for v in vals[-5:]:
        print(f"  Cycle {v[0]:>6}: C={v[1]:.4f} A={v[2]:.4f}")
