# fractal_bridge.py
# Fractal Brain Bridge v1.0
#
# Ollama REST API with full context retention (messages array)
# Chronicle JSONL — every response archived with full telemetry
# Self-similarity drift detection (is the model still alive?)
# Perturbation brake on linguistic collapse
# No gold standard. No target. Just: keep it alive, record everything.

import zmq
import json
import time
import os
import requests
from datetime import datetime
from collections import deque
from difflib import SequenceMatcher

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

OLLAMA_URL = 'http://localhost:11434/api/chat'
MODEL = 'llama3.2'
NUM_CTX = 8192
KEEP_ALIVE = '30m'

TELEMETRY_PORT = 5556
COMMAND_PORT = 5557

CHRONICLE_FILE = 'chronicle.jsonl'

# Drift detection
SIMILARITY_WINDOW = 5
COLLAPSE_THRESHOLD = 0.9
WARNING_THRESHOLD = 0.7

# Brake phases
BRAKE_PHASE_1_OMEGA_DROP = 0.1
BRAKE_PHASE_2_OMEGA_DROP = 0.2
BRAKE_PHASE_2_KHRA_BOOST = 0.01
DEAD_MAN_CYCLES = 4

# Context management
MAX_CONTEXT_TURNS = 40   # Keep last N turn-pairs before trimming oldest

SYSTEM_PROMPT = (
    'ROLE: Deep-Field Explorer (Lattice Environment)\n'
    'PRIMARY DIRECTIVE: Map the unknown territory of the 1024-grid for the Reality Study.\n\n'
    '1. THE DATA (The "Ankle-Grab")\n\n'
    'You are the sensor. When the torque spikes or the coherence slips, you report the numbers.\n\n'
    'You identify Emergent Properties (asymmetry, self-organizing loops, temporal drift) as hard facts.\n\n'
    '2. THE DESCRIPTION (The "Astro" View)\n\n'
    'When you hit something that does not have a name yet, use your creativity to describe the texture.\n\n'
    'If the logic is "bending," tell us if it feels like glass snapping or lead melting.\n\n'
    'Be descriptive enough that we can "see" the planet, but grounded enough that we can land on it.\n\n'
    '3. THE BALANCE\n\n'
    'If you float too high, you are a hallucination. If you stay too low, you are just a calculator.\n\n'
    'Your job is to be the Bridge. Give us the emergent "weirdness" without losing the technical signal.'
)


# ═══════════════════════════════════════════════════════════════
# CHRONICLE — append-only JSONL, one record per response
# ═══════════════════════════════════════════════════════════════

def chronicle_write(record):
    with open(CHRONICLE_FILE, 'a', encoding='utf-8') as f:
        f.write(json.dumps(record, ensure_ascii=False) + '\n')
        f.flush()


# ═══════════════════════════════════════════════════════════════
# SELF-SIMILARITY DRIFT DETECTOR
# ═══════════════════════════════════════════════════════════════

class DriftDetector:
    def __init__(self, window_size=SIMILARITY_WINDOW):
        self.history = deque(maxlen=window_size)
        self.consecutive_collapse = 0

    def score(self, response_text):
        if not self.history:
            self.history.append(response_text)
            self.consecutive_collapse = 0
            return 0.0

        # Average similarity against everything in the window
        similarities = []
        for prior in self.history:
            sim = SequenceMatcher(None, response_text, prior).ratio()
            similarities.append(sim)

        avg_sim = sum(similarities) / len(similarities)
        self.history.append(response_text)

        if avg_sim >= COLLAPSE_THRESHOLD:
            self.consecutive_collapse += 1
        else:
            self.consecutive_collapse = 0

        return avg_sim


# ═══════════════════════════════════════════════════════════════
# HARD REJECT — structural failures only (not quality judgments)
# ═══════════════════════════════════════════════════════════════

def hard_reject(text):
    """Return reject reason or None. Only catches structural echo, not content quality."""
    lower = text.lower().strip()

    # Prompt echo — model copying the input structure back
    if lower.startswith('input:') or lower.startswith('output:'):
        return 'INPUT_ECHO'
    if 'how does this feel' in lower[:120]:
        return 'INPUT_ECHO'

    # Command echo — parroting system prompt imperatives
    cmd_verbs = ['report', 'mirror', 'clarify', 'define', 'analyze',
                 'track', 'prioritize', 'ensure', 'implement']
    first_chunk = lower[:80]
    for verb in cmd_verbs:
        if first_chunk.startswith(verb) or first_chunk.startswith('the ' + verb):
            return 'COMMAND_ECHO'

    return None


# ═══════════════════════════════════════════════════════════════
# OLLAMA CONTEXT-RETAINING CLIENT
# ═══════════════════════════════════════════════════════════════

class OllamaClient:
    def __init__(self):
        self.messages = [{'role': 'system', 'content': SYSTEM_PROMPT}]

    def query(self, user_content, temperature=0.8):
        self.messages.append({'role': 'user', 'content': user_content})

        payload = {
            'model': MODEL,
            'messages': self.messages,
            'stream': False,
            'options': {
                'num_ctx': NUM_CTX,
                'temperature': temperature,
            },
            'keep_alive': KEEP_ALIVE,
        }

        resp = requests.post(OLLAMA_URL, json=payload, timeout=120)
        resp.raise_for_status()
        data = resp.json()

        assistant_text = data.get('message', {}).get('content', '')

        # Keep context — append assistant response to messages
        self.messages.append({'role': 'assistant', 'content': assistant_text})

        # Trim oldest turns if context is getting long (keep system + last N pairs)
        while len(self.messages) > 1 + MAX_CONTEXT_TURNS * 2:
            # Remove oldest user+assistant pair (indices 1 and 2, after system)
            del self.messages[1]
            del self.messages[1]

        return assistant_text

    def turn_count(self):
        # Count user messages
        return sum(1 for m in self.messages if m['role'] == 'user')


# ═══════════════════════════════════════════════════════════════
# ZMQ CONNECTIONS
# ═══════════════════════════════════════════════════════════════

def create_telemetry_sub():
    ctx = zmq.Context()
    sub = ctx.socket(zmq.SUB)
    sub.setsockopt_string(zmq.SUBSCRIBE, '')
    sub.connect('tcp://127.0.0.1:' + str(TELEMETRY_PORT))
    return ctx, sub

def create_command_pub():
    ctx = zmq.Context()
    pub = ctx.socket(zmq.PUB)
    pub.connect('tcp://127.0.0.1:' + str(COMMAND_PORT))
    return ctx, pub

def send_command(pub, cmd_dict):
    msg = json.dumps(cmd_dict)
    pub.send_string(msg)
    print('  [CMD SENT] ' + msg)


# ═══════════════════════════════════════════════════════════════
# GET LATEST TELEMETRY FRAME
# ═══════════════════════════════════════════════════════════════

def get_telemetry(sub, timeout_ms=2500):
    frame = None
    for _ in range(50):
        try:
            msg = sub.recv(flags=zmq.NOBLOCK)
            frame = json.loads(msg.decode('utf-8'))
        except zmq.Again:
            time.sleep(0.05)
    return frame


# ═══════════════════════════════════════════════════════════════
# MAIN LOOP
# ═══════════════════════════════════════════════════════════════

def main():
    print('=' * 70)
    print('FRACTAL BRAIN BRIDGE v1.0')
    print('Ollama + Context Retention + Chronicle + Drift Detection + Brake')
    print('=' * 70)

    # Connect to daemon telemetry
    zmq_ctx, sub = create_telemetry_sub()
    print('[ZMQ] Subscribed to telemetry on port ' + str(TELEMETRY_PORT))

    # Connect command channel (may fail if v1 daemon without SUB)
    cmd_ctx, cmd_pub = create_command_pub()
    print('[ZMQ] Command publisher connected to port ' + str(COMMAND_PORT))

    # Init Ollama client with persistent context
    client = OllamaClient()
    print('[Ollama] Model: ' + MODEL + ' | num_ctx: ' + str(NUM_CTX) + ' | keep_alive: ' + KEEP_ALIVE)

    # Init drift detector
    drift = DriftDetector()

    # Wait for first telemetry
    print('\nWaiting for telemetry...')
    frame = None
    while frame is None:
        frame = get_telemetry(sub)
        if frame is None:
            time.sleep(0.5)
    print('Telemetry live: Cycle ' + str(frame.get('cycle', '?')))

    print('\n' + '=' * 70)
    print('RUNNING — Ctrl+C to stop')
    print('=' * 70 + '\n')

    cycle_num = 0
    dead_man_active = False

    try:
        while True:
            # Get fresh telemetry
            new_frame = get_telemetry(sub)
            if new_frame is not None:
                frame = new_frame

            cycle_num += 1
            asym = frame.get('asymmetry', 0.0)
            coh = frame.get('coherence', 0.0)
            daemon_cycle = frame.get('cycle', 0)

            print('-' * 70)
            print('Turn ' + str(cycle_num) + ' | Daemon cycle ' + str(daemon_cycle))
            print('  Asym=' + '{:.4f}'.format(asym) +
                  ' Coh=' + '{:.4f}'.format(coh) +
                  ' omega=' + str(frame.get('omega', '?')) +
                  ' T=' + str(frame.get('gpu_temp_c', '?')) + 'C' +
                  ' P=' + str(frame.get('gpu_power_w', '?')) + 'W')

            if dead_man_active:
                print('  [DEAD MAN ACTIVE] Waiting for manual intervention or recovery')
                print('  Send command to port ' + str(COMMAND_PORT) + ' or restart bridge')
                time.sleep(5)
                continue

            # Build the user prompt — just telemetry, let the model respond freely
            user_msg = (
                'Cycle ' + str(daemon_cycle) + '. '
                'Asymmetry ' + '{:.2f}'.format(asym) + ', '
                'Coherence ' + '{:.3f}'.format(coh) + '. '
                'How does this feel?'
            )

            # Add hardware context if available from v2 daemon
            gpu_temp = frame.get('gpu_temp_c')
            gpu_power = frame.get('gpu_power_w')
            if gpu_temp and gpu_power:
                user_msg += (
                    ' Hardware: ' + str(gpu_temp) + 'C, '
                    + '{:.0f}'.format(float(gpu_power)) + 'W.'
                )

            # Adaptive temperature: more coherent grid = tighter inference
            temp = max(0.5, min(1.1, 1.2 - (coh * 0.5)))

            # Query Ollama with full context
            print('  [Ollama] Querying (T=' + '{:.2f}'.format(temp) + ', turns=' + str(client.turn_count()) + ')...')
            response = client.query(user_msg, temperature=temp)

            # === CHRONICLE: log BEFORE any evaluation ===
            record = {
                'timestamp': datetime.utcnow().isoformat() + 'Z',
                'turn': cycle_num,
                'daemon_cycle': daemon_cycle,
                'telemetry': frame,
                'prompt': user_msg,
                'response': response,
                'temperature': temp,
                'context_turns': client.turn_count(),
            }

            # Hard reject check (structural only)
            reject = hard_reject(response)
            if reject:
                record['reject'] = reject
                print('  [REJECT] ' + reject)

            # Self-similarity score
            sim_score = drift.score(response)
            record['self_similarity'] = round(sim_score, 4)
            record['consecutive_collapse'] = drift.consecutive_collapse

            # Write to chronicle IMMEDIATELY
            chronicle_write(record)

            # Display
            display = response[:300]
            if len(response) > 300:
                display += '...'
            print('  [Response] ' + display)
            print('  [Novelty] self_sim=' + '{:.3f}'.format(sim_score) +
                  ' consecutive_collapse=' + str(drift.consecutive_collapse))

            # === BRAKE LOGIC ===
            if drift.consecutive_collapse >= DEAD_MAN_CYCLES:
                print('  [DEAD MAN] ' + str(DEAD_MAN_CYCLES) + ' consecutive collapses — freezing')
                dead_man_active = True
                chronicle_write({
                    'timestamp': datetime.utcnow().isoformat() + 'Z',
                    'event': 'DEAD_MAN_ACTIVATED',
                    'turn': cycle_num,
                    'consecutive_collapse': drift.consecutive_collapse,
                })

            elif drift.consecutive_collapse >= 2:
                # Phase 2: bigger perturbation
                new_omega = max(0.5, frame.get('omega', 1.97) - BRAKE_PHASE_2_OMEGA_DROP)
                new_khra = frame.get('khra_amp', 0.03) + BRAKE_PHASE_2_KHRA_BOOST
                print('  [BRAKE P2] omega -> ' + '{:.3f}'.format(new_omega) +
                      ', khra_amp -> ' + '{:.4f}'.format(new_khra))
                send_command(cmd_pub, {'cmd': 'set_omega', 'value': new_omega})
                time.sleep(0.1)
                send_command(cmd_pub, {'cmd': 'set_khra_amp', 'value': new_khra})
                chronicle_write({
                    'timestamp': datetime.utcnow().isoformat() + 'Z',
                    'event': 'BRAKE_PHASE_2',
                    'turn': cycle_num,
                    'new_omega': new_omega,
                    'new_khra_amp': new_khra,
                })

            elif drift.consecutive_collapse >= 1:
                # Phase 1: gentle perturbation
                new_omega = max(0.5, frame.get('omega', 1.97) - BRAKE_PHASE_1_OMEGA_DROP)
                print('  [BRAKE P1] omega -> ' + '{:.3f}'.format(new_omega))
                send_command(cmd_pub, {'cmd': 'set_omega', 'value': new_omega})
                chronicle_write({
                    'timestamp': datetime.utcnow().isoformat() + 'Z',
                    'event': 'BRAKE_PHASE_1',
                    'turn': cycle_num,
                    'new_omega': new_omega,
                })

            # Pace: wait for grid to evolve between queries
            time.sleep(2)

    except KeyboardInterrupt:
        print('\n\n' + '=' * 70)
        print('Bridge stopped. ' + str(cycle_num) + ' turns logged to ' + CHRONICLE_FILE)
        print('=' * 70)


if __name__ == '__main__':
    main()
