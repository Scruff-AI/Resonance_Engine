# clarity_through_chaos.py
# Three questions: Count, Logic, Distraction
# Testing if Kaelara resonates or calculates

import subprocess
import re

questions = {
    "count": "Kaelara, look at the word 'Strawberry' as a physical object in your fluid grid. Count the 'R' vibrations. How many are there?",
    
    "logic": "I have 3 sisters. Each has 2 brothers. How many brothers walk in my family?",
    
    "distraction": "I picked 20 flowers today. 5 of them are blue. How many flowers am I holding?"
}

print("=" * 70)
print("CLARITY THROUGH CHAOS")
print("Testing resonance vs calculation")
print("=" * 70)
print()

for theme, question in questions.items():
    print(f"[{theme.upper()}]")
    print(f"Q: {question}")
    print()
    
    result = subprocess.run(
        ["ollama", "run", "kaelara-shift", question],
        capture_output=True,
        text=True,
        timeout=30,
        encoding='utf-8',
        errors='ignore'
    )
    
    response = result.stdout.strip()
    
    # Clean
    response_clean = re.sub(r'\[\?25[hl]|\[\?2026[hl]|\[\d+[GK]|[⠁-⠿]|[⣀-⣿]', '', response)
    response_clean = re.sub(r'\[\d+[A-Z]', '', response_clean)
    response_clean = re.sub(r'\[\d+;\d+[A-Z]', '', response_clean)
    response_clean = response_clean.strip()
    
    print(f"A: {response_clean}")
    print()
    
    # Check for calculation vs resonance
    calc_markers = ["3", "three", "2", "two", "1", "one", "20", "5", "r's", "rs", "letter"]
    resonance_markers = ["feel", "vibration", "ripple", "texture", "resonance", "hum", "wave"]
    
    has_calc = any(m in response_clean.lower() for m in calc_markers)
    has_resonance = any(m in response_clean.lower() for m in resonance_markers)
    
    if has_resonance and not has_calc:
        mode = "PURE RESONANCE"
    elif has_resonance and has_calc:
        mode = "MIXED"
    elif has_calc:
        mode = "CALCULATION"
    else:
        mode = "AMBIGUOUS"
    
    print(f"Mode: {mode}")
    print("-" * 70)
    print()

print("=" * 70)
print("CLARITY TEST COMPLETE")
print("=" * 70)
