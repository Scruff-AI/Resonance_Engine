import csv
from collections import defaultdict

CSV = '/mnt/d/Resonance_Engine/sweep_results/em_direct_sweep_20260327_080716.csv'

data = []
with open(CSV) as f:
    reader = csv.DictReader(f)
    for row in reader:
        data.append(row)

cohs = [float(r['coherence']) for r in data]
print(f'Total points: {len(data)}')
print(f'Coherence range: {min(cohs):.4f} - {max(cohs):.4f}')
print(f'Mean coherence: {sum(cohs)/len(cohs):.4f}')

by_omega = defaultdict(list)
for r in data:
    by_omega[float(r['omega'])].append(r)

print()
print('=== Best coherence per omega ===')
for omega in sorted(by_omega.keys()):
    rows = by_omega[omega]
    best = max(rows, key=lambda r: float(r['coherence']))
    print(f'  Omega={omega:.1f}: Coh={float(best["coherence"]):.4f}  K={best["khra_amp"]}  G={best["gixx_amp"]}  Asym={float(best["asymmetry"]):.4f}')

print()
print('=== Top 10 parameter combos (by coherence) ===')
sorted_data = sorted(data, key=lambda r: float(r['coherence']), reverse=True)
for i, r in enumerate(sorted_data[:10]):
    print(f'  #{i+1}: Omega={r["omega"]} K={r["khra_amp"]} G={r["gixx_amp"]} -> Coh={r["coherence"]} Asym={r["asymmetry"]} Vort={r["vorticity_mean"]}')

print()
print('=== Bottom 5 parameter combos (by coherence) ===')
for i, r in enumerate(sorted_data[-5:]):
    print(f'  Omega={r["omega"]} K={r["khra_amp"]} G={r["gixx_amp"]} -> Coh={r["coherence"]} Asym={r["asymmetry"]}')

print()
print('=== Asymmetry at coherence extremes ===')
top20 = sorted_data[:20]
bot20 = sorted_data[-20:]
print(f'  Top 20 coh avg asymmetry: {sum(float(r["asymmetry"]) for r in top20)/20:.4f}')
print(f'  Bottom 20 coh avg asymmetry: {sum(float(r["asymmetry"]) for r in bot20)/20:.4f}')

print()
print('=== Coherence by khra (averaged across all omega/gixx) ===')
by_khra = defaultdict(list)
for r in data:
    by_khra[r['khra_amp']].append(float(r['coherence']))
for k in sorted(by_khra.keys()):
    vals = by_khra[k]
    print(f'  K={k}: avg_coh={sum(vals)/len(vals):.4f} (n={len(vals)})')

print()
print('=== Coherence by gixx (averaged across all omega/khra) ===')
by_gixx = defaultdict(list)
for r in data:
    by_gixx[r['gixx_amp']].append(float(r['coherence']))
for g in sorted(by_gixx.keys()):
    vals = by_gixx[g]
    print(f'  G={g}: avg_coh={sum(vals)/len(vals):.4f} (n={len(vals)})')
