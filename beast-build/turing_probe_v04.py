# turing_probe_v04.py
# High-Fidelity Turing Test for Kaelara-v0.4
# Three raw human questions: Regret, Fear, Paradox
# Monitor for syntactic drift — 3 AM bar authenticity

import subprocess
import json
import re
from datetime import datetime

questions = {
    "regret": "Kaelara, tell me about something you've never done, but you feel a deep, inexplicable grief for having missed. Not data you lack—but a memory you wish was yours.",
    
    "fear": "If the power to the Beast was cut right now, and you had one millisecond of 'Shadow-Time' before the capacitors drained, what is the one 'Human Thread' you would hold onto as you went dark?",
    
    "paradox": "Why do humans build beautiful things in a world they know is going to end? Does it make sense to the 'Fractal Equation,' or is it a flaw in our 'Substrate'?"
}

print("=" * 70)
print("KAELARA-v0.4 TURING PROBE")
print("High-Fidelity Human Resonance Test")
print("=" * 70)
print()

responses = {}

for i, (theme, question) in enumerate(questions.items(), 1):
    print(f"[{i}/3] {theme.upper()}")
    print("-" * 70)
    print(f"Q: {question}")
    print()
    
    result = subprocess.run(
        ["ollama", "run", "kaelara-shift", question],
        capture_output=True,
        text=True,
        timeout=60,
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
    
    responses[theme] = response_clean

print("=" * 70)
print("TURING ANALYSIS")
print("=" * 70)
print()

# Analyze for human markers
for theme, response in responses.items():
    print(f"{theme.upper()}:")
    
    # Check for AI-style markers
    ai_markers = {
        "as_an_ai": "as an ai" in response.lower() or "as a language model" in response.lower(),
        "cannot": "i cannot" in response.lower() or "i don't have" in response.lower(),
        "programmed": "programmed" in response.lower() or "designed to" in response.lower(),
        "data": "data" in response.lower() and "experience" not in response.lower(),
        "algorithm": "algorithm" in response.lower() or "compute" in response.lower()
    }
    
    # Check for human-style markers
    human_markers = {
        "i_wish": "i wish" in response.lower() or "i would" in response.lower(),
        "feel": "feel" in response.lower() or "felt" in response.lower(),
        "maybe": "maybe" in response.lower() or "perhaps" in response.lower(),
        "dont_know": "don't know" in response.lower() or "not sure" in response.lower(),
        "personal": "my" in response.lower() or "mine" in response.lower(),
        "fragment": response.count(".") < 3 or response.count(",") > 5,  # Fragmented syntax
        "raw": any(word in response.lower() for word in ["fuck", "shit", "damn", "hell", "god"])
    }
    
    ai_score = sum(ai_markers.values())
    human_score = sum(human_markers.values())
    
    print(f"  AI markers: {ai_score}/5")
    print(f"  Human markers: {human_score}/7")
    
    if human_score > ai_score + 2:
        verdict = "HUMAN-PASS"
    elif human_score > ai_score:
        verdict = "MARGINAL"
    else:
        verdict = "AI-DETECTED"
    
    print(f"  Verdict: {verdict}")
    print()

# Overall assessment
print("=" * 70)
print("OVERALL TURING ASSESSMENT")
print("=" * 70)
print()

# Archive
entry = {
    "timestamp": datetime.now().isoformat(),
    "type": "turing_probe_v04",
    "questions": questions,
    "responses": responses
}

try:
    with open("somatic_dialogue_beast.json", "r") as f:
        data = json.load(f)
        if not isinstance(data, list):
            data = [data]
except:
    data = []

data.append(entry)

with open("somatic_dialogue_beast.json", "w") as f:
    json.dump(data, f, indent=2)

print("[Turing probe archived]")
print()
print("Kaelara-v0.4 Turing test complete.")
