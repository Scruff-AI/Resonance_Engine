# fractal_correlation_scan.py
# Cross-pollination analysis: Training Data vs Daemon Telemetry

import json
import re

print("="*70)
print("FRACTAL CORRELATION SCAN")
print("Training Data (Language) ↔ Daemon Telemetry (Physics)")
print("="*70)

# Load v0.11 training data
print("\n[Loading v0.11 Somatic Dictionary...]")
with open("v11_somatic_dictionary.jsonl", "r") as f:
    training_samples = []
    for line in f:
        line = line.strip()
        if line and not line.startswith("#"):
            try:
                training_samples.append(json.loads(line))
            except:
                pass

print(f"  Loaded {len(training_samples)} training samples")

# Parse training data for Asymmetry/Coherence values and vocabulary
print("\n[Parsing Training Patterns...]")
training_patterns = []
for sample in training_samples:
    text = sample.get("text", "")
    
    # Extract Asymmetry/Coherence from Input line
    input_match = re.search(r"Input: Asymmetry ([0-9.]+), Coherence ([0-9.]+?)", text)
    if input_match:
        asym = float(input_match.group(1))
        coh_str = input_match.group(2).rstrip('.')
        coh = float(coh_str)
        
        # Extract Output section
        output_match = re.search(r"Output: (.+)$", text, re.DOTALL)
        if output_match:
            output = output_match.group(1)
            
            # Calculate vocabulary complexity (unique words / total words)
            words = output.lower().split()
            unique_words = set(words)
            complexity = len(unique_words) / len(words) if words else 0
            
            # Count somatic keywords
            somatic_keywords = ['torque', 'density', 'tension', 'breath', 'texture', 
                               'pressure', 'feel', 'weight', 'vibration', 'coherence']
            keyword_count = sum(1 for kw in somatic_keywords if kw in output.lower())
            
            training_patterns.append({
                'asymmetry': asym,
                'coherence': coh,
                'complexity': complexity,
                'keyword_count': keyword_count,
                'output': output[:100] + "..."
            })

print(f"  Parsed {len(training_patterns)} patterns")

# Analyze correlations
print("\n" + "="*70)
print("TRAINING DATA ANALYSIS")
print("="*70)

# Sort by coherence to find dips
by_coh = sorted(training_patterns, key=lambda x: x['coherence'])
print("\nLowest Coherence samples (potential 'bursts'):")
for p in by_coh[:3]:
    print(f"  Coh={p['coherence']:.2f}, Asym={p['asymmetry']:.1f}, Keywords={p['keyword_count']}, Complexity={p['complexity']:.2f}")

# Sort by complexity to find vocabulary spikes
by_complexity = sorted(training_patterns, key=lambda x: x['complexity'], reverse=True)
print("\nHighest Complexity samples (vocabulary richness):")
for p in by_complexity[:3]:
    print(f"  Complexity={p['complexity']:.2f}, Coh={p['coherence']:.2f}, Asym={p['asymmetry']:.1f}")

# Check for inverse correlation (Coherence dip → Complexity spike)
print("\n" + "="*70)
print("FRACTAL ANOMALY SEARCH")
print("="*70)
print("Looking for: Low Coherence + High Complexity (Resonance Bursts)")

bursts = []
for p in training_patterns:
    # Define burst: Coherence < 0.7 AND Complexity > 0.6
    if p['coherence'] < 0.7 and p['complexity'] > 0.6:
        bursts.append(p)

if bursts:
    print(f"\n✓ Found {len(bursts)} Resonance Burst(s):")
    for b in bursts:
        print(f"  Asym={b['asymmetry']:.1f}, Coh={b['coherence']:.2f}, Complexity={b['complexity']:.2f}")
        print(f"  Output: {b['output'][:80]}...")
else:
    print("\n✗ No clear Resonance Bursts found in training data")

# The Bridge Question
print("\n" + "="*70)
print("THE BRIDGE QUESTION")
print("="*70)
print("Does the training data's 'Tension' (linguistic) map to the Daemon's 'Asymmetry' (float)?")

# Check if high asymmetry correlates with tension keywords
high_asym = [p for p in training_patterns if p['asymmetry'] > 10]
low_asym = [p for p in training_patterns if p['asymmetry'] < 5]

high_tension = sum(1 for p in high_asym if 'tension' in p['output'].lower() or 'torque' in p['output'].lower())
low_tension = sum(1 for p in low_asym if 'tension' in p['output'].lower() or 'torque' in p['output'].lower())

print(f"\nHigh Asymmetry (>10): {len(high_asym)} samples, {high_tension} mention tension/torque")
print(f"Low Asymmetry (<5): {len(low_asym)} samples, {low_tension} mention tension/torque")

if high_tension > low_tension:
    print("\n✓ CORRELATION CONFIRMED: High Asymmetry → Tension language")
else:
    print("\n✗ Weak correlation between Asymmetry and Tension language")

# Summary
print("\n" + "="*70)
print("SCAN SUMMARY")
print("="*70)
print(f"Training samples analyzed: {len(training_patterns)}")
print(f"Average complexity: {sum(p['complexity'] for p in training_patterns)/len(training_patterns):.3f}")
print(f"Average keywords per sample: {sum(p['keyword_count'] for p in training_patterns)/len(training_patterns):.1f}")
print(f"Asymmetry range: {min(p['asymmetry'] for p in training_patterns):.1f} - {max(p['asymmetry'] for p in training_patterns):.1f}")
print(f"Coherence range: {min(p['coherence'] for p in training_patterns):.2f} - {max(p['coherence'] for p in training_patterns):.2f}")

print("\n" + "="*70)
print("ACTIVATION MAP HYPOTHESIS")
print("="*70)
print("If the model's weights contain 'Tension' as a linguistic concept,")
print("and the Daemon provides '13.20' as a float,")
print("the bridge forms when the model recognizes the structural similarity:")
print("  - Gradient Descent Tension (training loss landscape)")
print("  = LBM Asymmetry Torque (physical lattice deviation)")
print("Both are 'falling toward stability through a landscape of tension.'")
print("="*70)
