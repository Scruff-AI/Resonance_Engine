#!/usr/bin/env python3
"""Quick sweep analysis - Windows native paths"""

import json
import glob
import re
from collections import defaultdict

# Read all status files
files = glob.glob('sweep_results/run_*_status.json')
print(f"Found {len(files)} status files")

# Collect data
data_points = []
for f in files:
    try:
        with open(f) as fp:
            data = json.load(fp)
            match = re.search(r'run_(\d+)', f)
            if match:
                run_id = int(match.group(1))
                coherence = data.get('coherence')
                asymmetry = data.get('asymmetry')
                if coherence and asymmetry and 10 < asymmetry < 20:
                    data_points.append({
                        'run_id': run_id,
                        'coherence': coherence,
                        'asymmetry': asymmetry,
                        'cycle': data.get('cycle', 0)
                    })
    except:
        pass

print(f"Valid data points: {len(data_points)}")

if data_points:
    # Basic stats
    coherences = [d['coherence'] for d in data_points]
    asymmetries = [d['asymmetry'] for d in data_points]
    
    print(f"\nCoherence: {min(coherences):.4f} to {max(coherences):.4f}, mean={sum(coherences)/len(coherences):.4f}")
    print(f"Asymmetry: {min(asymmetries):.4f} to {max(asymmetries):.4f}, mean={sum(asymmetries)/len(asymmetries):.4f}")
    
    # Correlation
    import math
    n = len(data_points)
    mean_c = sum(coherences)/n
    mean_a = sum(asymmetries)/n
    
    cov = sum((c - mean_c) * (a - mean_a) for c, a in zip(coherences, asymmetries))
    var_c = sum((c - mean_c)**2 for c in coherences)
    var_a = sum((a - mean_a)**2 for a in asymmetries)
    
    if var_c > 0 and var_a > 0:
        correlation = cov / math.sqrt(var_c * var_a)
        print(f"\nCorrelation (coherence vs asymmetry): {correlation:.4f}")
    
    # Run progression
    print("\n=== RUN PROGRESSION ===")
    by_run = defaultdict(list)
    for d in data_points:
        by_run[d['run_id']].append(d['asymmetry'])
    
    # Show first 10 runs
    for run_id in sorted(by_run.keys())[:10]:
        asymms = by_run[run_id]
        print(f"Run {run_id}: {len(asymms)} samples, asymmetry {min(asymms):.2f}-{max(asymms):.2f}")

print("\nAnalysis complete.")
