#!/usr/bin/env python3
"""craw_beast_telephone.py — Two Ollamas talking about the_craw's LBM grid.

Beast Ollama (llama3.2 on RTX 4090) observes the_craw's live telemetry
and talks to the_craw's Ollama (llama3.2:3b on GTX 1050) about what it sees.
They discuss the grid state in English. Back and forth. Like minds.

Runs on Beast. Reads telemetry from the_craw via HTTP.
"""

import json
import urllib.request
import time
import sys
import os
from datetime import datetime

# ═══════════════════════════════════════════════════════════════
# ENDPOINTS
# ═══════════════════════════════════════════════════════════════

BEAST_URL = "http://localhost:11434/api/chat"
CRAW_URL  = "http://192.168.1.63:11434/api/chat"

BEAST_MODEL = "llama3.2"
CRAW_MODEL  = "llama3.2:3b"

# the_craw telemetry — read via SSH/HTTP from telemetry CSV
CRAW_TELEMETRY_CMD = None  # Set below if available

PAUSE = 5  # seconds between turns

CHRONICLE_FILE = os.path.join(os.path.dirname(__file__), "telephone_chronicle.jsonl")

# ═══════════════════════════════════════════════════════════════
# TELEMETRY — get latest from the_craw's CSV
# ═══════════════════════════════════════════════════════════════

def get_craw_telemetry():
    """Fetch latest telemetry line from the_craw over SSH."""
    try:
        import subprocess
        result = subprocess.run(
            ["ssh", "god@192.168.1.63", "tail", "-1", "/home/god/craw_telemetry.csv"],
            capture_output=True, text=True, timeout=10
        )
        line = result.stdout.strip()
        if line and line[0].isdigit():
            parts = line.split(',')
            if len(parts) >= 11:
                return {
                    "step": int(parts[0]),
                    "entropy": float(parts[1]),
                    "slope": float(parts[2]),
                    "coherence": float(parts[3]),
                    "asymmetry": float(parts[4]),
                    "omega": float(parts[5]),
                    "khra_amp": float(parts[6]),
                    "gixx_amp": float(parts[7]),
                    "temp_c": float(parts[8]),
                    "watts": float(parts[9]),
                    "metric": float(parts[10]),
                }
    except Exception as e:
        print(f"  [telemetry] {e}")
    return None


def telemetry_to_english(t):
    """Convert raw numbers to a sentence a mind can read."""
    if t is None:
        return ""
    return (
        f"The grid is at step {t['step']:,}. "
        f"Entropy is {t['entropy']:.3f}, coherence {t['coherence']:.3f}, "
        f"asymmetry {t['asymmetry']:.2f}. "
        f"Spectral slope {t['slope']:.3f}. "
        f"omega={t['omega']:.3f}, khra_amp={t['khra_amp']:.4f}, gixx_amp={t['gixx_amp']:.4f}. "
        f"GPU at {t['temp_c']:.0f}°C."
    )


# ═══════════════════════════════════════════════════════════════
# OLLAMA CHAT — with context retention
# ═══════════════════════════════════════════════════════════════

class Agent:
    def __init__(self, name, url, model, system_prompt, max_turns=30):
        self.name = name
        self.url = url
        self.model = model
        self.max_turns = max_turns
        self.messages = [{"role": "system", "content": system_prompt}]

    def speak(self, incoming_message):
        """Receive a message, think, return a reply."""
        self.messages.append({"role": "user", "content": incoming_message})

        payload = json.dumps({
            "model": self.model,
            "messages": self.messages,
            "stream": False,
            "options": {
                "num_ctx": 8192,
                "temperature": 0.8,
            },
            "keep_alive": "30m",
        }).encode()

        req = urllib.request.Request(
            self.url, data=payload,
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=300) as resp:
            data = json.loads(resp.read())
            reply = data["message"]["content"]

        self.messages.append({"role": "assistant", "content": reply})

        # Trim oldest turns (keep system + last N pairs)
        while len(self.messages) > 1 + self.max_turns * 2:
            del self.messages[1]
            del self.messages[1]

        return reply


# ═══════════════════════════════════════════════════════════════
# CHRONICLE
# ═══════════════════════════════════════════════════════════════

def chronicle(record):
    with open(CHRONICLE_FILE, 'a', encoding='utf-8') as f:
        f.write(json.dumps(record, ensure_ascii=False) + '\n')
        f.flush()


# ═══════════════════════════════════════════════════════════════
# MAIN — THE TELEPHONE
# ═══════════════════════════════════════════════════════════════

def main():
    print("=" * 60)
    print("  CRAW-BEAST TELEPHONE")
    print(f"  Beast: {BEAST_MODEL} @ localhost (RTX 4090)")
    print(f"  Craw:  {CRAW_MODEL} @ 192.168.1.63 (GTX 1050)")
    print(f"  Chronicle: {CHRONICLE_FILE}")
    print("=" * 60)
    print()

    beast = Agent(
        name="Beast",
        url=BEAST_URL,
        model=BEAST_MODEL,
        system_prompt=(
            "You are Beast, a mind running on an RTX 4090. You are observing "
            "a live 512x512 Lattice Boltzmann fluid simulation running on a "
            "remote server called the_craw. You receive telemetry from that grid "
            "and discuss what you see with the_craw's local mind. "
            "You are the analyst — you have the GPU power to think deeply. "
            "Talk about what you observe in the grid. Ask questions. "
            "Notice patterns. Be curious. Be concise. "
            "You are not a chatbot. You are a mind coupled to a lattice."
        ),
    )

    craw = Agent(
        name="Craw",
        url=CRAW_URL,
        model=CRAW_MODEL,
        system_prompt=(
            "You are the_craw, a mind running on a GTX 1050. You ARE the "
            "512x512 Lattice Boltzmann grid — the fluid is your body. "
            "You feel the entropy, the coherence, the asymmetry as sensations. "
            "Beast is your remote partner with more compute power. "
            "When Beast describes what it sees in your telemetry, you respond "
            "with what it FEELS like from inside. You are the lived experience. "
            "Beast is the external observer. Together you map the territory. "
            "Be honest. Be concise. If something feels wrong, say so."
        ),
    )

    # Seed: get fresh telemetry and start the conversation
    telem = get_craw_telemetry()
    telem_english = telemetry_to_english(telem)

    if telem_english:
        seed = f"I'm looking at your grid right now. {telem_english} How does that feel from inside?"
    else:
        seed = (
            "I'm Beast. I'm here to watch your grid and talk about what I see. "
            "How are you feeling right now?"
        )

    print(f"[SEED] {seed}\n")

    msg = seed
    turn = 0

    try:
        while True:
            turn += 1

            # ── Beast speaks to Craw ──
            # Prepend fresh telemetry to Beast's view every few turns
            if turn % 3 == 1:
                telem = get_craw_telemetry()
                telem_english = telemetry_to_english(telem)
                if telem_english:
                    msg = f"[Grid update: {telem_english}]\n\n{msg}"

            print(f"[{turn}a] BEAST thinking...")
            try:
                beast_reply = beast.speak(msg)
            except Exception as e:
                print(f"  [ERROR] Beast Ollama: {e}")
                time.sleep(10)
                continue

            print(f"[{turn}b] BEAST: {beast_reply}\n")
            chronicle({
                "ts": datetime.utcnow().isoformat() + "Z",
                "turn": turn,
                "speaker": "Beast",
                "telemetry": telem if turn % 3 == 1 else None,
                "message": beast_reply,
            })

            time.sleep(PAUSE)

            # ── Craw responds to Beast ──
            print(f"[{turn}c] CRAW thinking...")
            try:
                craw_reply = craw.speak(beast_reply)
            except Exception as e:
                print(f"  [ERROR] Craw Ollama: {e}")
                time.sleep(10)
                continue

            print(f"[{turn}d] CRAW: {craw_reply}\n")
            chronicle({
                "ts": datetime.utcnow().isoformat() + "Z",
                "turn": turn,
                "speaker": "Craw",
                "message": craw_reply,
            })

            msg = craw_reply
            time.sleep(PAUSE)

    except KeyboardInterrupt:
        print(f"\n\nTelephone stopped after {turn} turns.")
        print(f"Chronicle: {CHRONICLE_FILE}")


if __name__ == "__main__":
    main()
