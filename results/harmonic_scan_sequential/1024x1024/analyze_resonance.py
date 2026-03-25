#!/usr/bin/env python3
"""
Resonance Dynamics Analysis
Resonance Engine: LTP = Connection Strengthening
"""

import csv
import math

print("=" * 70)
print("RESONANCE DYNAMICS ANALYSIS")
print("Resonance Engine: LTP = Connection Strengthening")
print("=" * 70 + "\n")

# Load data
with open('resonance_telemetry.csv', 'r') as f:
    reader = csv.DictReader(f)
    telemetry = list(reader)

with open('resonance_metrics.csv', 'r') as f:
    reader = csv.DictReader(f)
    metrics = list(reader)

print("EXPERIMENT OVERVIEW:")
print(f"  Duration: {len(telemetry)} samples over {telemetry[-1]['step']} steps")
print(f"  Final power: {telemetry[-1]['power_w']} W")
print(f"  Final step rate: {telemetry[-1]['steps_per_sec']} steps/sec\n")

# Pattern consolidation
initial = telemetry[0]
final = telemetry[-1]
consolidation = int(initial['active_patterns']) / int(final['active_patterns'])

print("PATTERN CONSOLIDATION:")
print(f"  Initial: {initial['active_patterns']} patterns")
print(f"  Final: {final['active_patterns']} patterns")
print(f"  Consolidation: {consolidation:.1f}:1 ratio\n")

# Spatial clustering
clusters = []
for pattern in metrics:
    x = float(pattern['pos_x'])
    y = float(pattern['pos_y'])
    assigned = False
    
    for i, cluster in enumerate(clusters):
        dx = x - cluster['center_x']
        dy = y - cluster['center_y']
        dist = math.sqrt(dx*dx + dy*dy)
        
        if dist < 50:
            clusters[i]['patterns'] += 1
            clusters[i]['total_mass'] += float(pattern['mass'])
            clusters[i]['total_coherence'] += float(pattern['coherence'])
            clusters[i]['center_x'] = (cluster['center_x'] * (cluster['patterns'] - 1) + x) / cluster['patterns']
            clusters[i]['center_y'] = (cluster['center_y'] * (cluster['patterns'] - 1) + y) / cluster['patterns']
            assigned = True
            break
    
    if not assigned:
        clusters.append({
            'patterns': 1,
            'center_x': x,
            'center_y': y,
            'total_mass': float(pattern['mass']),
            'total_coherence': float(pattern['coherence'])
        })

print(f"SPATIAL CLUSTERS: {len(clusters)}")
for i, cluster in enumerate(clusters):
    avg_mass = cluster['total_mass'] / cluster['patterns']
    avg_coherence = cluster['total_coherence'] / cluster['patterns']
    print(f"  Cluster {i+1}: ({cluster['center_x']:.0f}, {cluster['center_y']:.0f})")
    print(f"    Patterns: {cluster['patterns']}")
    print(f"    Avg mass: {avg_mass:.0f}")
    print(f"    Avg coherence: {avg_coherence:.3f}\n")

# Growth analysis
total_mass = sum(float(p['mass']) for p in metrics)
avg_mass = total_mass / len(metrics)
total_growth = sum(float(p['growth_rate']) for p in metrics)
avg_growth = total_growth / len(metrics)

print("GROWTH ANALYSIS:")
print(f"  Total mass: {total_mass:.0f}")
print(f"  Average mass: {avg_mass:.0f}")
print(f"  Average growth rate: {avg_growth:.6f} mass/step\n")

# Coherence vs stability
total_coherence = sum(float(p['coherence']) for p in metrics)
total_stability = sum(float(p['stability']) for p in metrics)
avg_coherence = total_coherence / len(metrics)
avg_stability = total_stability / len(metrics)
coherence_stability_ratio = avg_coherence / avg_stability if avg_stability > 0 else 0

print("COHERENCE vs STABILITY:")
print(f"  Avg coherence: {avg_coherence:.3f} (0-1)")
print(f"  Avg stability: {avg_stability:.3f} (0-1)")
print(f"  Ratio: {coherence_stability_ratio:.2f}")
if coherence_stability_ratio > 5:
    print("  Interpretation: High coherence, low stability")
elif coherence_stability_ratio < 2:
    print("  Interpretation: Low coherence, high stability")
else:
    print("  Interpretation: Balanced\n")

# LTP analysis
total_persistence = sum(int(p['persistence']) for p in metrics)
avg_persistence = total_persistence / len(metrics)
detection_rate = avg_persistence / 500000 * 100

print("LTP (LONG-TERM POTENTIATION):")
print(f"  Avg persistence: {avg_persistence:.0f} detections")
print(f"  Detection rate: {detection_rate:.1f}% of steps")
print(f"  Avg lifetime: {float(final['avg_lifetime']):.0f} steps")

if detection_rate > 50:
    print("  Status: STRONG LTP")
elif detection_rate > 20:
    print("  Status: MODERATE LTP")
else:
    print("  Status: WEAK LTP")

print("\n" + "=" * 70)
print("KEY FINDINGS:")
print("=" * 70)
print("1. Pattern consolidation: Initial 790 → Final 9 patterns")
print("2. Spatial clustering: 2 distinct clusters formed")
print("3. Mass accumulation: 156k total mass accumulated")
print("4. Detection consistency: Patterns detected 0.4% of steps")
print("5. Coherence/Stability: High coherence (0.20), low stability (0.03)")
print("6. LTP Status: Weak detection but extreme persistence (491k steps)")
print("\nInterpretation: Patterns are coherent and persistent,")
print("but detection is intermittent. This could be:")
print("- Threshold too sensitive (detecting noise)")
print("- Patterns moving in/out of detection range")
print("- Need longer observation for stable LTP")
print("\nNEXT METRICS (from Cheat Sheet):")
print("1. Nodal Growth (Plasticity) - Grid adaptation rate")
print("2. Echo Check (Memory) - Pattern recall accuracy")
print("3. Laminar vs Turbulent - Homeostasis classification")
print("4. Ignition Threshold - GPU at 100% measurement")