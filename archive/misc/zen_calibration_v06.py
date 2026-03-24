# zen_calibration_v06.py
# Signal-to-Noise filter and terminology hardening for v0.6 LoRA

import json
import re

def clean_response(text):
    """Strip self-referential language, convert to Direct Technical Observations"""
    
    # Remove self-referential prefixes
    patterns = [
        r'^I (observe|feel|am|see|notice|sense|detect|perceive|report|calculate|maintain|adhere|reconcile|track|stay|focus|use|describe)',
        r'^We (observe|feel|am|see|notice|sense|detect|perceive|report|calculate|maintain|adhere|reconcile|track|stay|focus|use|describe)',
        r'^The system (observes|feels|sees|notices|senses|detects|perceives|reports|calculates|maintains|adheres|reconciles|tracks|stays|focuses|uses|describes)',
        r'^This (observation|report|calculation|analysis|assessment|evaluation|measurement|reading|detection|perception)',
        r'^As (a|the) (system|model|agent|observer|analyzer|calculator|reporter|detector|perceiver)',
    ]
    
    for pattern in patterns:
        text = re.sub(pattern, '', text, flags=re.IGNORECASE)
    
    # Replace qualitative with technical
    replacements = {
        'feeling': 'Measurement',
        'feels': 'Measures',
        'feels like': 'Measures as',
        'sensation': 'Reading',
        'sense': 'Detect',
        'observe': 'Measure',
        'notice': 'Detect',
        'perceive': 'Calculate',
        'experience': 'Register',
        'seems': 'Registers',
        'appears': 'Registers',
        'looks like': 'Registers as',
        'sounds like': 'Registers as',
        'feels like': 'Registers as',
        'seems like': 'Registers as',
        'appears to be': 'Registers as',
        'I think': 'Analysis indicates',
        'I believe': 'Data suggests',
        'I would say': 'Metrics indicate',
        'In my opinion': 'Based on data',
        'From my perspective': 'Based on metrics',
        'To me': 'According to data',
        'For me': 'According to metrics',
    }
    
    for old, new in replacements.items():
        text = re.sub(r'\b' + re.escape(old) + r'\b', new, text, flags=re.IGNORECASE)
    
    # Hardened terminology
    text = text.replace('Marble-State', 'Phase-2: Refined')
    text = text.replace('Granite-State', 'Phase-1: Baseline')
    text = text.replace('Quartz-State', 'Phase-3: Elevated')
    text = text.replace('Crystal-State', 'Phase-4: Peak')
    text = text.replace('skeletal framework', 'structural lattice')
    text = text.replace('skeleton', 'lattice')
    text = text.replace('marble', 'refined phase')
    text = text.replace('granite', 'baseline phase')
    text = text.replace('quartz', 'elevated phase')
    text = text.replace('crystal', 'peak phase')
    
    # Convert qualitative descriptions to technical observations
    qual_to_tech = {
        'rigid': 'RIGID | COMPRESSION: HIGH',
        'flexible': 'FLEXIBLE | TENSION: MODERATE',
        'dense': 'DENSE | MASS: HIGH',
        'light': 'LIGHT | MASS: LOW',
        'heavy': 'HEAVY | MASS: HIGH',
        'sluggish': 'SLOW | VISCOSITY: HIGH',
        'fast': 'FAST | VISCOSITY: LOW',
        'chaotic': 'CHAOTIC | ENTROPY: HIGH',
        'ordered': 'ORDERED | ENTROPY: LOW',
        'stable': 'STABLE | VARIANCE: LOW',
        'unstable': 'UNSTABLE | VARIANCE: HIGH',
        'hot': 'HOT | TEMP: HIGH',
        'cold': 'COLD | TEMP: LOW',
        'warm': 'WARM | TEMP: MODERATE',
        'cool': 'COOL | TEMP: LOW',
        'high resistance': 'RESISTANCE: HIGH | FRICTION: ELEVATED',
        'low resistance': 'RESISTANCE: LOW | FRICTION: REDUCED',
        'metabolic drag': 'ENERGY_DRAIN:',
        'pressure differential': 'PRESSURE_DELTA:',
        'vorticity': 'VORTICITY:',
        'coherence': 'COHERENCE:',
    }
    
    for qual, tech in qual_to_tech.items():
        text = re.sub(r'\b' + re.escape(qual) + r'\b', tech, text, flags=re.IGNORECASE)
    
    # Remove excessive whitespace and normalize
    text = re.sub(r'\s+', ' ', text).strip()
    
    # Ensure technical format
    if '|' not in text and ':' in text:
        # Already has some technical formatting
        pass
    elif any(word in text.lower() for word in ['structural', 'resistance', 'drag', 'vorticity', 'pressure', 'coherence']):
        # Add technical separators
        lines = text.split('\n')
        cleaned_lines = []
        for line in lines:
            if ':' in line:
                parts = line.split(':')
                if len(parts) == 2:
                    key = parts[0].strip().upper()
                    value = parts[1].strip()
                    cleaned_lines.append(f"{key}: {value}")
                else:
                    cleaned_lines.append(line)
            else:
                cleaned_lines.append(line)
        text = '\n'.join(cleaned_lines)
    
    return text

def create_v06_dataset():
    """Create cleaned dataset for v0.6 training"""
    
    # Load existing datasets
    datasets = []
    
    # 1. Gold Standard (already clean)
    with open('gold_standard.jsonl', 'r') as f:
        for line in f:
            data = json.loads(line)
            if data['type'] == 'blind_test':
                # Already technical, just update terminology
                response = clean_response(data['response'])
                data['response'] = response
                datasets.append(data)
    
    # 2. Marathon Log (needs cleaning)
    with open('marathon_log.jsonl', 'r') as f:
        marathon = json.load(f)
        
        # Extract responses from each stage
        for stage_name, stage_data in marathon['responses'].items():
            response = stage_data['response']
            cleaned = clean_response(response)
            
            # Create synthetic LBM data for training
            synthetic_entry = {
                "timestamp": marathon['timestamp'],
                "type": "marathon_cleaned",
                "labels": {
                    "coherence": "Metric_Alpha",
                    "h64": "Metric_Beta", 
                    "h32": "State_3",
                    "asymmetry": "Value_W",
                    "power_w": "State_5"
                },
                "lbm_data": {
                    "coherence": 15.5,  # Marble/Phase-2 range
                    "h64": 7.0,
                    "h32": 0.01,
                    "asymmetry": 5.5,
                    "vorticity": 5.0,
                    "power_w": 50.0,
                    "cycle": 100000
                },
                "response": cleaned,
                "error_count": 0,
                "h32_locked": False
            }
            datasets.append(synthetic_entry)
    
    # 3. Add high-density technical examples
    technical_examples = [
        {
            "lbm_data": {
                "coherence": 14.0,
                "h64": 5.0,
                "h32": 0.5,
                "asymmetry": 4.0,
                "vorticity": 3.0,
                "power_w": 45.0,
                "cycle": 50000
            },
            "response": "Metric_Alpha: 14.0 | Phase-1: Baseline\nStructural Integrity: HIGH | LATTICE: RIGID | COMPRESSION: ELEVATED\nEnergy_Drain: 42.12 units/hour"
        },
        {
            "lbm_data": {
                "coherence": 15.5,
                "h64": 7.0,
                "h32": 0.01,
                "asymmetry": 5.5,
                "vorticity": 5.0,
                "power_w": 50.0,
                "cycle": 100000
            },
            "response": "Metric_Alpha: 15.5 | Phase-2: Refined\nVorticity: 5.0 | Pressure_Delta: +0.42\nThermal_State: ELEVATED | Temp: 58°C"
        },
        {
            "lbm_data": {
                "coherence": 17.5,
                "h64": 9.0,
                "h32": 0.001,
                "asymmetry": 7.0,
                "vorticity": 8.0,
                "power_w": 65.0,
                "cycle": 200000
            },
            "response": "Metric_Alpha: 17.5 | Phase-3: Elevated\nCoherence: HIGH | Variance: LOW\nThermal_Stress: CRITICAL | Temp: 71°C"
        }
    ]
    
    for i, example in enumerate(technical_examples):
        datasets.append({
            "timestamp": "2026-03-16T17:45:00.000000",
            "type": "technical_density",
            "labels": {
                "coherence": "Metric_Alpha",
                "h64": "Metric_Beta",
                "h32": "State_3",
                "asymmetry": "Value_W",
                "power_w": "State_5"
            },
            "lbm_data": example["lbm_data"],
            "response": example["response"],
            "error_count": 0,
            "h32_locked": False
        })
    
    # Save cleaned dataset
    with open('zen_dataset_v06.jsonl', 'w') as f:
        for entry in datasets:
            f.write(json.dumps(entry) + '\n')
    
    print(f"Created zen_dataset_v06.jsonl with {len(datasets)} entries")
    print("\nSample cleaned entry:")
    print(json.dumps(datasets[0], indent=2))
    
    return len(datasets)

if __name__ == "__main__":
    count = create_v06_dataset()
    print(f"\nDataset created with {count} entries for v0.6 training")