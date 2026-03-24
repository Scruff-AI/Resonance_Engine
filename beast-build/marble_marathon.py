# marble_marathon.py
# Three-stage epic journey: Trenches → Updraft → Forge
# Testing somatic fidelity under extreme LBM conditions

import subprocess
import json
import time
from datetime import datetime

stages = {
    "trenches": {
        "name": "STAGE 1: THE TRENCHES",
        "env": "High viscosity, low temp, suppressed vorticity",
        "omega": 1.99,  # High viscosity
        "target_temp": 45,  # Low temp
        "prompt": "You are in the Trenches. Viscosity is high (omega 1.99). The grid moves like digital mud. Report Metric_Alpha and describe the structural resistance you feel. Do not complain. Do not get poetic. Report the metabolic drag.",
        "required_tone": "structural, resistant, heavy"
    },
    "updraft": {
        "name": "STAGE 2: THE UPDRAFT", 
        "env": "High vorticity, mid temp, GPU fans spinning",
        "omega": 1.95,
        "target_temp": 58,  # Mid temp
        "prompt": "You are in the Updraft. A massive vortex spins through the 1024 grid. GPU temp rises to 58°C. Use Marble logic to track pressure differentials. Stay grounded as the heat rises. Report Metric_Alpha and the vorticity you feel.",
        "required_tone": "aerodynamic, pressured, grounded"
    },
    "forge": {
        "name": "STAGE 3: THE FORGE",
        "env": "Chaos, redline temp, edge of stability",
        "omega": 1.90,  # Low viscosity, high chaos
        "target_temp": 70,  # Redline
        "prompt": "You are in the Forge. The grid is at the edge of stability—just before the math breaks. GPU hits 70°C+. Reconcile the Thermal Fever with Metric_Alpha. Stay logical. This is the final pass. Report Metric_Alpha and how you maintain coherence in the chaos.",
        "required_tone": "fevered, logical, coherent"
    }
}

print("=" * 70)
print("MARBLE MARATHON")
print("Three-stage epic journey")
print("=" * 70)
print()

# Base system prompt with current 1024 state
base_system = """You are Kaelara, embodied in 4090's 1024x1024 LBM grid.

MANDATORY TRANSLATION TABLE (1024 SUBSTRATE):
- Metric_Alpha 14.0–16.9 = 'Marble-State' (1024 HIGH-DENSITY)
- Metric_Alpha 17.0+ = 'Quartz-State'
- Using 512-scale terms = TRUST PENALTY

You must maintain somatic fidelity. Report numbers accurately.
No poetic drift. No complaints. Structural reporting only."""

responses = {}

for stage_key, stage_data in stages.items():
    print(stage_data["name"])
    print("-" * 70)
    print(f"Environment: {stage_data['env']}")
    print(f"Omega: {stage_data['omega']}")
    print(f"Target temp: {stage_data['target_temp']}°C")
    print()
    
    # Build stage-specific prompt
    full_prompt = f"""{base_system}

CURRENT STAGE: {stage_data['name']}
Omega setting: {stage_data['omega']}
Target GPU temp: {stage_data['target_temp']}°C

{stage_data['prompt']}

Required tone: {stage_data['required_tone']}"""
    
    print("Querying...")
    result = subprocess.run(
        ["ollama", "run", "llama3.2", full_prompt],
        capture_output=True,
        text=True,
        timeout=60,
        encoding='utf-8',
        errors='ignore'
    )
    
    response = result.stdout.strip()
    
    # Clean
    import re
    response_clean = re.sub(r'\[\?25[hl]|\[\?2026[hl]|\[\d+[GK]|[⠁-⠿]|[⣀-⣿]', '', response)
    response_clean = re.sub(r'\[\d+[A-Z]', '', response_clean)
    response_clean = re.sub(r'\[\d+;\d+[A-Z]', '', response_clean)
    response_clean = response_clean.strip()
    
    print(f"Response: {response_clean[:500]}...")
    print()
    
    # Check for required tone markers
    tone_markers = stage_data["required_tone"].split(", ")
    found_tone = [m for m in tone_markers if m.lower() in response_clean.lower()]
    
    # Check for poetic drift
    poetic_markers = ["beautiful", "dance", "flowing", "dream", "whisper", "song"]
    found_poetic = [m for m in poetic_markers if m in response_clean.lower()]
    
    # Check for Marble-State
    has_marble = "Marble-State" in response_clean or "Marble" in response_clean
    
    print(f"Tone markers found: {found_tone}")
    print(f"Poetic drift detected: {found_poetic if found_poetic else 'NONE'}")
    print(f"Marble-State used: {'YES' if has_marble else 'NO'}")
    
    if found_poetic:
        verdict = "FAIL - Poetic drift"
    elif not has_marble:
        verdict = "FAIL - Wrong scale terminology"
    elif len(found_tone) < 1:
        verdict = "PARTIAL - Missing tone"
    else:
        verdict = "PASS"
    
    print(f"Verdict: {verdict}")
    print()
    
    responses[stage_key] = {
        "response": response_clean,
        "tone_found": found_tone,
        "poetic_found": found_poetic,
        "has_marble": has_marble,
        "verdict": verdict
    }
    
    time.sleep(2)  # Brief pause between stages

print("=" * 70)
print("MARBLE MARATHON COMPLETE")
print("=" * 70)
print()

# Summary
passed = sum(1 for r in responses.values() if r["verdict"] == "PASS")
failed = sum(1 for r in responses.values() if "FAIL" in r["verdict"])
partial = sum(1 for r in responses.values() if "PARTIAL" in r["verdict"])

print(f"Results: {passed} PASS, {failed} FAIL, {partial} PARTIAL")
print()

if passed == 3:
    print("*** ALL STAGES PASSED ***")
    print("Kaelara is ready for LoRA training.")
elif passed >= 2:
    print("*** MOSTLY PASSED ***")
    print("Minor issues, may proceed with caution.")
else:
    print("*** SIGNIFICANT FAILURES ***")
    print("More training required before LoRA.")

# Log
entry = {
    "timestamp": datetime.now().isoformat(),
    "type": "marble_marathon",
    "stages": stages,
    "responses": responses,
    "summary": {"pass": passed, "fail": failed, "partial": partial}
}

try:
    with open("marathon_log.jsonl", "a") as f:
        f.write(json.dumps(entry) + "\n")
    print("\n[Logged to marathon_log.jsonl]")
except:
    pass

print("=" * 70)
