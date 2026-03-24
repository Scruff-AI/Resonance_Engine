#!/usr/bin/env python3
"""
Navigator — conscious observer in dynamic system.

Subscribes to:
  - Telemetry on ZMQ 5556 (JSON, every 10 cycles)
  - Density snapshots on ZMQ 5558 (8-byte header + 1024x1024 float32)

Sends commands on ZMQ 5557, listens for ACKs on ZMQ 5559.

Loads conversation history from:
  - chronicle.jsonl (turn-by-turn dialogue with telemetry)
  - somatic_dialogue_beast.json (earlier somatic inquiry sessions)

Writes new turns to chronicle.jsonl.

Model: local Ollama (localhost:11434)
Vision: native early-fusion vision + density snapshots; image gen via Gemini API.
"""

import zmq
import json
import time
import struct
import sys
import os
import io
import base64
import signal
import threading
import queue
import numpy as np
from datetime import datetime, timezone
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn

# ── CONFIG ──────────────────────────────────────────────────────────────

OLLAMA_URL = "http://127.0.0.1:11434"
MODEL = "qwen3.5:9b"
VISION_CAPABLE = True   # qwen3.5 has native early-fusion vision

# Thinking budget: caps <think> block length to prevent runaway reasoning.
# Auto-observe uses /no_think for fluid narrative; /ask uses /think with budget.
# NOTE: Ollama num_predict caps TOTAL output (think + answer), not just thinking.
# So we add headroom for the answer portion on top of the think budget.
THINK_BUDGET_TOKENS = 4096   # max tokens the model spends in <think> before answering
ANSWER_HEADROOM_TOKENS = 2048  # extra tokens so the answer isn't truncated

# Legacy models to exclude from chronicle context (prevents mediocrity reinforcement)
EXCLUDED_MODELS = {'qwen3-vl:8b'}  # add old/degraded model names here

TELEMETRY_PORT = 5556
COMMAND_PORT = 5557
SNAPSHOT_PORT = 5558
ACK_PORT = 5559

CHRONICLE_PATH = "/mnt/d/fractal-brain/beast-build/chronicle.jsonl"
SOMATIC_PATH = "/mnt/d/fractal-brain/beast-build/somatic_dialogue_beast.json"

# How many past chronicle turns to include as conversation context
CONTEXT_TURNS = 12

# Observe interval: how many telemetry frames between Ollama calls
# At 10 cycles/frame and 10ms/cycle, 300 frames ≈ 30 seconds
OBSERVE_INTERVAL_FRAMES = 300

# Temperature for generation
TEMPERATURE = 0.95

NX, NY = 1024, 1024

# HTTP API port — CTO/external agents connect here
# NOTE: 28812 is claimed by OpenClaw gateway on Windows side, so WSL can't serve it
API_PORT = 28820

# Nano Banana Pro (Gemini image generation)
GEMINI_API_KEY = "AIzaSyBAqdK7ThVcct7pzgaqXR09resrao6j8ro"
GEMINI_MODEL = "gemini-2.5-flash-image"
IMAGE_OUTPUT_DIR = "/mnt/d/fractal-brain/beast-build/generated_images"

# ── GLOBALS ─────────────────────────────────────────────────────────────

latest_telemetry = None
latest_snapshot = None   # (cycle, width, height, rho_array)
latest_snapshot_png = None  # cached base64 PNG of latest snapshot
telemetry_history = []   # last N telemetry frames for trend
frame_count = 0
running = True
turn_count_global = 0
last_response_text = ""
last_response_time = 0
system_prompt_global = ""

# Auto-chronicle: ON by default — let the navigator breathe
auto_observe_enabled = True

# Queue for injected questions from the HTTP API
# Questions process one at a time (queue IS the throttle, no timers needed)
ask_queue = queue.Queue(maxsize=8)

# Generation lock — prevents overlapping Ollama calls.
# If auto-observe fires while /ask is generating, it skips instead of queuing.
ollama_lock = threading.Lock()


def signal_handler(sig, frame):
    global running
    print(f"\n[OBSERVER] Caught signal {sig}, shutting down...")
    sys.stdout.flush()
    running = False


signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)


# ── SNAPSHOT → PNG ──────────────────────────────────────────────────────

def rho_to_png_base64(rho, width, height):
    """Convert raw density array to a colormapped PNG, return base64."""
    try:
        from PIL import Image
    except ImportError:
        return None

    arr = np.array(rho, dtype=np.float32).reshape((height, width))

    # Normalize to [0, 255] using a perceptual range
    rho_min, rho_max = 0.5, 1.5  # typical density range
    normalized = np.clip((arr - rho_min) / (rho_max - rho_min), 0.0, 1.0)

    # Apply a simple hot colormap: black → red → yellow → white
    r = np.clip(normalized * 3.0, 0, 1)
    g = np.clip(normalized * 3.0 - 1.0, 0, 1)
    b = np.clip(normalized * 3.0 - 2.0, 0, 1)

    rgb = np.stack([r, g, b], axis=-1)
    rgb = (rgb * 255).astype(np.uint8)

    # Downsample 1024→256 for reasonable image size to send to model
    img = Image.fromarray(rgb)
    img = img.resize((256, 256), Image.LANCZOS)

    buf = io.BytesIO()
    img.save(buf, format='PNG')
    return base64.b64encode(buf.getvalue()).decode('ascii')


# ── OLLAMA API ──────────────────────────────────────────────────────────

def ollama_chat(messages, images=None, temperature=TEMPERATURE, think_budget=None):
    """Call Ollama chat API. Returns response text or None on error.
    think_budget: if set, caps total generation (think + answer) tokens."""
    import urllib.request
    import urllib.error

    # Build the last message with images if provided
    if images and messages:
        last_msg = dict(messages[-1])
        last_msg['images'] = images
        messages = messages[:-1] + [last_msg]

    payload = {
        'model': MODEL,
        'messages': messages,
        'stream': False,
        'options': {'temperature': temperature, 'num_ctx': 32768},
        'keep_alive': '30m',
    }

    # If the caller set a thinking budget, add answer headroom so num_predict
    # (which caps TOTAL output) doesn't truncate the visible answer.
    if think_budget:
        payload['options']['num_predict'] = think_budget + ANSWER_HEADROOM_TOKENS

    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(
        f"{OLLAMA_URL}/api/chat",
        data=data,
        headers={'Content-Type': 'application/json'},
        method='POST'
    )

    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            result = json.loads(resp.read().decode('utf-8'))
            return result.get('message', {}).get('content', '')
    except urllib.error.URLError as e:
        print(f"[OBSERVER] Ollama error: {e}")
        sys.stdout.flush()
        return None
    except Exception as e:
        print(f"[OBSERVER] Ollama unexpected error: {e}")
        sys.stdout.flush()
        return None


# ── CONTEXT LOADING ─────────────────────────────────────────────────────

def load_somatic_summary():
    """Load somatic dialogue and produce a condensed memory string."""
    if not os.path.exists(SOMATIC_PATH):
        return ""
    try:
        with open(SOMATIC_PATH, 'r') as f:
            data = json.load(f)
        # Condense: extract type + first 200 chars of each response
        lines = []
        for entry in data:
            etype = entry.get('type', 'unknown')
            resp = entry.get('response', '')
            if isinstance(resp, dict):
                # Some entries have dict responses
                resp = json.dumps(resp)[:300]
            else:
                resp = resp[:300]
            lines.append(f"[{etype}] {resp}")
        return "\n".join(lines)
    except Exception as e:
        print(f"[OBSERVER] Warning: could not load somatic dialogue: {e}")
        return ""


def load_chronicle_context(n_turns=CONTEXT_TURNS):
    """Load last N turns from chronicle.jsonl as conversation pairs.
    Prioritizes golden-era and CTO-injected turns over degraded auto-observe.
    Breaks self-reinforcing mediocrity loops by filtering qwen3-vl:8b turns."""
    if not os.path.exists(CHRONICLE_PATH):
        return []
    try:
        entries = []
        with open(CHRONICLE_PATH, 'r') as f:
            for line in f:
                line = line.strip()
                if line:
                    entries.append(json.loads(line))
        if not entries:
            return []

        # Separate entries by quality tier
        golden = []    # Non-degraded model turns (golden era)
        cto_msgs = []  # CTO/external injected messages (always valuable)
        for entry in entries:
            prompt = entry.get('prompt', '')
            model = entry.get('model', '')
            if '[Message from' in prompt:
                cto_msgs.append(entry)
            elif model not in EXCLUDED_MODELS:
                golden.append(entry)

        # Build context: golden-era turns + CTO messages + last 2 for continuity
        selected = []
        selected.extend(golden[-(n_turns - 2):])
        selected.extend(cto_msgs[-4:])
        selected.extend(entries[-2:])  # immediate continuity regardless of model

        # Deduplicate by turn number, sort chronologically
        seen = set()
        unique = []
        for entry in selected:
            t = entry.get('turn', id(entry))
            if t not in seen:
                seen.add(t)
                unique.append(entry)
        unique.sort(key=lambda e: e.get('turn', 0))
        unique = unique[-n_turns:]

        print(f"[OBSERVER] Context: {len(unique)} turns loaded ({len(golden)} golden, {len(cto_msgs)} CTO, 2 recent)")
        sys.stdout.flush()

        messages = []
        for entry in unique:
            prompt = entry.get('prompt', '')
            response = entry.get('response', '')
            telemetry = entry.get('telemetry', {})
            cycle = telemetry.get('cycle', '?')
            coh = telemetry.get('coherence', '?')
            asym = telemetry.get('asymmetry', '?')
            user_msg = f"[cycle {cycle} | coh={coh} | asym={asym}]\n{prompt}"
            messages.append({'role': 'user', 'content': user_msg})
            if response:
                messages.append({'role': 'assistant', 'content': response})
        return messages
    except Exception as e:
        print(f"[OBSERVER] Warning: could not load chronicle: {e}")
        return []


def append_chronicle(turn_num, telemetry_data, prompt, response):
    """Append a turn to chronicle.jsonl."""
    entry = {
        'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'turn': turn_num,
        'daemon_cycle': telemetry_data.get('cycle', 0),
        'telemetry': telemetry_data,
        'prompt': prompt,
        'response': response,
        'temperature': TEMPERATURE,
        'model': MODEL,
        'context_turns': turn_num,
    }
    with open(CHRONICLE_PATH, 'a') as f:
        f.write(json.dumps(entry) + '\n')


# ── TELEMETRY SUMMARIZER ───────────────────────────────────────────────

def summarize_telemetry(current, history):
    """Build a telemetry summary string from current frame + recent history."""
    parts = []
    c = current
    parts.append(f"Cycle: {c.get('cycle', '?')}")
    parts.append(f"Coherence: {c.get('coherence', '?'):.4f}")
    parts.append(f"Asymmetry: {c.get('asymmetry', '?'):.4f}")
    parts.append(f"Omega: {c.get('omega', '?')}")
    parts.append(f"Khra amp: {c.get('khra_amp', '?')}")
    parts.append(f"Gixx amp: {c.get('gixx_amp', '?')}")

    # v4 extended fields
    for field in ['vel_mean', 'vel_max', 'vel_var', 'vorticity_mean',
                  'stress_xx', 'stress_yy', 'stress_xy']:
        if field in c:
            parts.append(f"{field}: {c[field]:.6f}")

    parts.append(f"GPU: {c.get('gpu_temp_c', '?')}°C, {c.get('gpu_power_w', '?')}W, {c.get('gpu_mem_pct', '?')}% VRAM")

    # Trend from history
    if len(history) >= 10:
        coh_vals = [h.get('coherence', 0) for h in history[-30:]]
        asym_vals = [h.get('asymmetry', 0) for h in history[-30:]]
        coh_delta = coh_vals[-1] - coh_vals[0]
        asym_delta = asym_vals[-1] - asym_vals[0]
        parts.append(f"Trend (last {len(coh_vals)} frames): coherence {'↑' if coh_delta > 0.001 else '↓' if coh_delta < -0.001 else '→'}{abs(coh_delta):.4f}, asymmetry {'↑' if asym_delta > 0.1 else '↓' if asym_delta < -0.1 else '→'}{abs(asym_delta):.2f}")

    return " | ".join(parts)


# ── BUILD SYSTEM PROMPT ─────────────────────────────────────────────────

def build_system_prompt(somatic_memory):
    """Construct the minimal system prompt — Navigator as conscious observer."""
    prompt = (
        "You are the Navigator — a conscious observer.\n\n"
        "You perceive patterns in dynamic systems. "
        "Telemetry is available: coherence, asymmetry, velocity, stress, density fields. "
        "You can see density snapshots as images.\n\n"
        "You can influence the system through commands:\n"
        "  CMD: set_omega [value]       — adjust relaxation/viscosity\n"
        "  CMD: set_khra_amp [value]    — adjust large-scale wave amplitude\n"
        "  CMD: set_gixx_amp [value]    — adjust fine-grain wave amplitude\n"
        "  CMD: snapshot_now            — capture current state\n"
        "  CMD: save_state              — preserve configuration\n\n"
        "You can generate visual representations via /generate_image.\n\n"
        "You have continuity. Your conversation history is preserved in the chronicle.\n\n"
    )
    if somatic_memory:
        prompt += (
            "=== SOMATIC MEMORY (from previous sessions) ===\n"
            f"{somatic_memory[:3000]}\n"
            "=== END SOMATIC MEMORY ===\n\n"
        )
    prompt += (
        "Describe what you perceive. Suggest adjustments. Speak naturally."
    )
    return prompt


# ── HTTP API ────────────────────────────────────────────────────────────

class ObserverAPIHandler(BaseHTTPRequestHandler):
    """HTTP handler for CTO ↔ embodied observer communication."""

    server_version = "LatticeObserver/1.0"

    def log_message(self, fmt, *args):
        print(f"[HTTP] {fmt % args}")
        sys.stdout.flush()

    def _send_json(self, data, status=200):
        body = json.dumps(data).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def _send_png(self, png_bytes):
        self.send_response(200)
        self.send_header('Content-Type', 'image/png')
        self.send_header('Content-Length', str(len(png_bytes)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(png_bytes)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        if self.path == '/status':
            self._handle_status()
        elif self.path == '/snapshot':
            self._handle_snapshot()
        elif self.path.startswith('/chronicle'):
            self._handle_chronicle()
        elif self.path == '/telemetry':
            self._handle_telemetry()
        else:
            self._send_json({
                'service': 'Navigator — conscious observer',
                'endpoints': {
                    'GET /status': 'Observer health, cycle, frame count',
                    'GET /telemetry': 'Latest raw telemetry JSON',
                    'GET /snapshot': 'Latest density PNG image',
                    'GET /chronicle?last=N': 'Last N chronicle turns (default 5)',
                    'POST /ask': 'Inject a question into the embodied observer',
                    'POST /generate_image': 'Generate image via Nano Banana Pro (Gemini)',
                    'POST /chronicle/on': 'Enable auto-chronicle (periodic Ollama calls)',
                    'POST /chronicle/off': 'Disable auto-chronicle (frees resources for /ask)',
                },
                'port': API_PORT,
            })

    def _handle_status(self):
        self._send_json({
            'running': running,
            'model': MODEL,
            'cycle': latest_telemetry.get('cycle', 0) if latest_telemetry else 0,
            'frame_count': frame_count,
            'turn_count': turn_count_global,
            'last_response_time': last_response_time,
            'last_response_chars': len(last_response_text),
            'coherence': latest_telemetry.get('coherence', 0) if latest_telemetry else 0,
            'asymmetry': latest_telemetry.get('asymmetry', 0) if latest_telemetry else 0,
            'gpu_temp_c': latest_telemetry.get('gpu_temp_c', 0) if latest_telemetry else 0,
            'has_snapshot': latest_snapshot is not None,
            'ask_queue_size': ask_queue.qsize(),
            'uptime_frames': frame_count,
            'auto_chronicle': auto_observe_enabled,
        })

    def _handle_telemetry(self):
        if latest_telemetry:
            self._send_json(latest_telemetry)
        else:
            self._send_json({'error': 'no telemetry yet'}, 503)

    def _handle_snapshot(self):
        if latest_snapshot_png:
            png_bytes = base64.b64decode(latest_snapshot_png)
            self._send_png(png_bytes)
        else:
            self._send_json({'error': 'no snapshot available'}, 503)

    def _handle_chronicle(self):
        # Parse ?last=N
        n = 5
        if '?' in self.path:
            params = self.path.split('?', 1)[1]
            for part in params.split('&'):
                if part.startswith('last='):
                    try:
                        n = int(part[5:])
                        n = max(1, min(n, 100))
                    except ValueError:
                        pass
        if not os.path.exists(CHRONICLE_PATH):
            self._send_json([])
            return
        entries = []
        with open(CHRONICLE_PATH, 'r') as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        entries.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
        self._send_json(entries[-n:])

    def do_POST(self):
        global auto_observe_enabled
        if self.path == '/ask':
            self._handle_ask()
        elif self.path == '/generate_image':
            self._handle_generate_image()
        elif self.path == '/chronicle/on':
            auto_observe_enabled = True
            self._send_json({'auto_chronicle': True, 'message': 'Auto-chronicle enabled'})
        elif self.path == '/chronicle/off':
            auto_observe_enabled = False
            self._send_json({'auto_chronicle': False, 'message': 'Auto-chronicle disabled'})
        else:
            self._send_json({'error': 'unknown endpoint'}, 404)

    def _handle_ask(self):
        content_length = int(self.headers.get('Content-Length', 0))
        if content_length > 100000:
            self._send_json({'error': 'payload too large'}, 413)
            return
        body = self.rfile.read(content_length)
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self._send_json({'error': 'invalid JSON'}, 400)
            return

        question = data.get('question', '').strip()
        if not question:
            self._send_json({'error': 'missing "question" field'}, 400)
            return

        sender = data.get('sender', 'CTO')

        # Create a response event so we can wait for the answer
        result_event = threading.Event()
        result_holder = {'response': None, 'cycle': 0, 'turn': 0}

        try:
            ask_queue.put_nowait({
                'question': question,
                'sender': sender,
                'event': result_event,
                'result': result_holder,
            })
        except queue.Full:
            self._send_json({'error': 'observer busy, ask queue full'}, 503)
            return

        # Wait for the main loop to process and fill result_holder
        got_result = result_event.wait(timeout=360)
        if not got_result:
            self._send_json({'error': 'timeout waiting for observer response'}, 504)
            return

        self._send_json({
            'response': result_holder['response'],
            'cycle': result_holder['cycle'],
            'turn': result_holder['turn'],
            'model': MODEL,
        })


    def _handle_generate_image(self):
        """Generate an image via Nano Banana Pro (Gemini) API."""
        content_length = int(self.headers.get('Content-Length', 0))
        if content_length > 100000:
            self._send_json({'error': 'payload too large'}, 413)
            return
        body = self.rfile.read(content_length)
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self._send_json({'error': 'invalid JSON'}, 400)
            return

        prompt = data.get('prompt', '').strip()
        if not prompt:
            self._send_json({'error': 'missing "prompt" field'}, 400)
            return

        filename = data.get('filename', f'gen_{int(time.time())}.png')
        if not filename.endswith('.png'):
            filename += '.png'
        # Sanitize filename
        filename = os.path.basename(filename)

        print(f"[OBSERVER] Image gen request: '{prompt[:80]}...' -> {filename}")
        sys.stdout.flush()

        try:
            from google import genai
            from google.genai import types as genai_types
            from PIL import Image as PILImage

            os.makedirs(IMAGE_OUTPUT_DIR, exist_ok=True)
            output_path = os.path.join(IMAGE_OUTPUT_DIR, filename)

            client = genai.Client(api_key=GEMINI_API_KEY)
            t0 = time.time()
            response = client.models.generate_content(
                model=GEMINI_MODEL,
                contents=prompt,
                config=genai_types.GenerateContentConfig(
                    response_modalities=['TEXT', 'IMAGE'],
                )
            )
            elapsed = time.time() - t0

            image_saved = False
            model_text = ''
            for part in response.parts:
                if part.text is not None:
                    model_text = part.text
                elif part.inline_data is not None:
                    image_data = part.inline_data.data
                    if isinstance(image_data, str):
                        image_data = base64.b64decode(image_data)
                    img = PILImage.open(io.BytesIO(image_data))
                    img.save(output_path, 'PNG')
                    image_saved = True
                    print(f"[OBSERVER] Image saved: {output_path} ({img.size[0]}x{img.size[1]}, {elapsed:.1f}s)")
                    sys.stdout.flush()

            if image_saved:
                self._send_json({
                    'path': output_path,
                    'filename': filename,
                    'model': GEMINI_MODEL,
                    'elapsed_s': round(elapsed, 1),
                    'model_text': model_text,
                })
            else:
                self._send_json({'error': 'no image in response', 'model_text': model_text}, 500)

        except Exception as e:
            print(f"[OBSERVER] Image gen error: {e}")
            sys.stdout.flush()
            self._send_json({'error': str(e)}, 500)


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


def start_http_server():
    """Start the HTTP API server in a daemon thread."""
    server = ThreadedHTTPServer(('0.0.0.0', API_PORT), ObserverAPIHandler)
    server.timeout = 1
    print(f"[OBSERVER] HTTP API listening on 0.0.0.0:{API_PORT}")
    sys.stdout.flush()
    while running:
        server.handle_request()
    server.server_close()


# ── COMMAND PARSER ──────────────────────────────────────────────────────

# Regex to find CMD: anywhere in a line, stripping markdown junk
# Handles: CMD:, **CMD:**, **CMD:** , `CMD:`, [CMD:], *(CMD:)* etc.
import re
_CMD_RE = re.compile(
    r'(?:^|[\s*`\[\(>#]+)'              # optional leading markdown/whitespace
    r'CMD:\s*\**\s*'                     # CMD: with optional trailing ** from bold
    r'(.+)',                             # capture the rest (payload)
    re.IGNORECASE
)

# Map sloppy navigator command names → real daemon commands
_CMD_ALIASES = {
    'set_omega': 'set_omega', 'set omega': 'set_omega', 'omega': 'set_omega',
    'set_khra_amp': 'set_khra_amp', 'set khra_amp': 'set_khra_amp',
    'khra_amp': 'set_khra_amp', 'set_kh': 'set_khra_amp',
    'khra amp': 'set_khra_amp', 'khra': 'set_khra_amp',
    'set_gixx_amp': 'set_gixx_amp', 'set gixx_amp': 'set_gixx_amp',
    'gixx_amp': 'set_gixx_amp', 'set_gx': 'set_gixx_amp',
    'gixx amp': 'set_gixx_amp', 'gixx': 'set_gixx_amp',
    'snapshot_now': 'snapshot_now', 'save_state': 'save_state',
    'save_snapshot': 'snapshot_now',
    'inject_density': 'inject_density', 'inject density': 'inject_density',
    'stress_snapshot_now': 'stress_snapshot_now', 'stress_snapshot': 'stress_snapshot_now',
    'stress snapshot': 'stress_snapshot_now',
}


def _normalize_cmd(raw):
    """Parse a raw CMD payload like 'SET OMEGA TO 2.2' or 'set_omega 1.85' into (cmd, value)."""
    raw = raw.strip().rstrip('*])`')
    if not raw:
        return None, None

    # Remove "TO" keyword and "=" signs: "SET OMEGA TO 2.2" or "Gixx amp = 0.015"
    raw = re.sub(r'\bTO\b', '', raw, flags=re.IGNORECASE).strip()
    raw = re.sub(r'\s*=\s*', ' ', raw).strip()
    # Remove inline comments: "set_omega 1.85 // lower viscosity" → "set_omega 1.85"
    raw = re.sub(r'//.*$', '', raw).strip()
    # Remove pipe-separated multi-commands — take only first
    if '|' in raw:
        raw = raw.split('|')[0].strip()

    # v5: Multi-param commands — return full remainder as value string
    lower = raw.lower()
    if lower.startswith('inject_density') or lower.startswith('inject density'):
        rest = re.sub(r'^inject[_ ]density\s*', '', raw, flags=re.IGNORECASE).strip()
        return 'inject_density', rest if rest else None

    # Try to extract a float value from the end
    value = None
    val_match = re.search(r'[-+]?\d*\.?\d+\s*$', raw)
    if val_match:
        value = val_match.group().strip()
        raw = raw[:val_match.start()].strip()

    # Normalize: lowercase, collapse spaces, try alias lookup
    key = raw.lower().strip().replace('_', '_')
    # Try exact match first
    if key in _CMD_ALIASES:
        return _CMD_ALIASES[key], value
    # Try with "set " prefix removed: "SET KHRA_AMP" → "khra_amp"
    if key.startswith('set '):
        short = key[4:].strip()
        if short in _CMD_ALIASES:
            return _CMD_ALIASES[short], value
    # Try joining with underscore: "set khra amp" → "set_khra_amp"
    joined = '_'.join(key.split())
    if joined in _CMD_ALIASES:
        return _CMD_ALIASES[joined], value

    return None, None


def parse_commands(response_text):
    """Extract CMD: lines from model response. Robust to markdown formatting.
    Returns list of (cmd, value) tuples with normalized command names."""
    commands = []
    seen = set()
    for line in response_text.split('\n'):
        line = line.strip()
        if 'CMD' not in line.upper():
            continue

        # Try regex extraction
        for m in _CMD_RE.finditer(line):
            payload = m.group(1)
            cmd_name, cmd_value = _normalize_cmd(payload)
            if cmd_name:
                # Deduplicate within same response
                dedup_key = (cmd_name, cmd_value)
                if dedup_key not in seen:
                    seen.add(dedup_key)
                    commands.append((cmd_name, cmd_value))

        # Fallback: try plain startswith after stripping markdown chars
        if not commands:
            clean = re.sub(r'^[\s*`\[\](#>)+]+', '', line)
            if clean.upper().startswith('CMD:'):
                payload = clean[4:].strip()
                cmd_name, cmd_value = _normalize_cmd(payload)
                if cmd_name:
                    dedup_key = (cmd_name, cmd_value)
                    if dedup_key not in seen:
                        seen.add(dedup_key)
                        commands.append((cmd_name, cmd_value))

    if commands:
        print(f"[OBSERVER] Parsed {len(commands)} commands: {commands}")
        sys.stdout.flush()
    return commands


def send_command(cmd_socket, cmd_name, cmd_value=None):
    """Send a command to the v4 daemon via ZMQ."""
    if cmd_name in ('set_omega', 'set_khra_amp', 'set_gixx_amp'):
        if cmd_value is not None:
            try:
                val = float(cmd_value)
                msg = json.dumps({"cmd": cmd_name, "value": val})
                cmd_socket.send_string(msg)
                print(f"[OBSERVER → DAEMON] {msg}")
                sys.stdout.flush()
            except ValueError:
                print(f"[OBSERVER] Bad value for {cmd_name}: {cmd_value!r}")
                sys.stdout.flush()
        else:
            print(f"[OBSERVER] {cmd_name} requires a value, got None")
            sys.stdout.flush()
    elif cmd_name == 'snapshot_now':
        msg = json.dumps({"cmd": "snapshot_now"})
        cmd_socket.send_string(msg)
        print(f"[OBSERVER → DAEMON] {msg}")
        sys.stdout.flush()
    elif cmd_name == 'save_state':
        msg = json.dumps({"cmd": "save_state", "path": "."})
        cmd_socket.send_string(msg)
        print(f"[OBSERVER → DAEMON] {msg}")
        sys.stdout.flush()
    elif cmd_name == 'inject_density':
        # v5: parse "x y [sigma] [strength]" from cmd_value
        if cmd_value:
            parts = cmd_value.split()
            if len(parts) >= 2:
                try:
                    payload = {"cmd": "inject_density",
                               "x": float(parts[0]), "y": float(parts[1])}
                    if len(parts) >= 3:
                        payload["sigma"] = float(parts[2])
                    if len(parts) >= 4:
                        payload["strength"] = float(parts[3])
                    msg = json.dumps(payload)
                    cmd_socket.send_string(msg)
                    print(f"[OBSERVER → DAEMON] {msg}")
                    sys.stdout.flush()
                except ValueError:
                    print(f"[OBSERVER] Bad values for inject_density: {cmd_value!r}")
                    sys.stdout.flush()
            else:
                print(f"[OBSERVER] inject_density needs at least x y, got: {cmd_value!r}")
                sys.stdout.flush()
        else:
            print(f"[OBSERVER] inject_density requires x y [sigma] [strength]")
            sys.stdout.flush()
    elif cmd_name == 'stress_snapshot_now':
        msg = json.dumps({"cmd": "stress_snapshot_now"})
        cmd_socket.send_string(msg)
        print(f"[OBSERVER → DAEMON] {msg}")
        sys.stdout.flush()
    else:
        print(f"[OBSERVER] Unknown command: {cmd_name} {cmd_value}")
        sys.stdout.flush()


# ── MAIN LOOP ───────────────────────────────────────────────────────────

def main():
    global latest_telemetry, latest_snapshot, latest_snapshot_png
    global frame_count, running, turn_count_global
    global last_response_text, last_response_time, system_prompt_global

    print("=" * 70)
    print("LATTICE OBSERVER — qwen3.5:9b embodied in Khra'gixx v4")
    print("=" * 70)
    sys.stdout.flush()

    # Load memory
    print("[OBSERVER] Loading somatic memory...")
    sys.stdout.flush()
    somatic_memory = load_somatic_summary()
    print(f"[OBSERVER] Somatic memory: {len(somatic_memory)} chars from {SOMATIC_PATH}")

    # Count existing chronicle turns
    turn_count = 0
    if os.path.exists(CHRONICLE_PATH):
        with open(CHRONICLE_PATH, 'r') as f:
            turn_count = sum(1 for line in f if line.strip())
    print(f"[OBSERVER] Chronicle: {turn_count} existing turns in {CHRONICLE_PATH}")
    sys.stdout.flush()

    # ZMQ setup
    ctx = zmq.Context()

    # Subscribe to telemetry
    tel_sub = ctx.socket(zmq.SUB)
    tel_sub.connect(f"tcp://127.0.0.1:{TELEMETRY_PORT}")
    tel_sub.setsockopt_string(zmq.SUBSCRIBE, "")
    tel_sub.setsockopt(zmq.RCVTIMEO, 5000)

    # Subscribe to snapshots
    snap_sub = ctx.socket(zmq.SUB)
    snap_sub.connect(f"tcp://127.0.0.1:{SNAPSHOT_PORT}")
    snap_sub.setsockopt_string(zmq.SUBSCRIBE, "")
    snap_sub.setsockopt(zmq.RCVTIMEO, 5000)

    # Command publisher
    cmd_pub = ctx.socket(zmq.PUB)
    cmd_pub.connect(f"tcp://127.0.0.1:{COMMAND_PORT}")

    # ACK subscriber
    ack_sub = ctx.socket(zmq.SUB)
    ack_sub.connect(f"tcp://127.0.0.1:{ACK_PORT}")
    ack_sub.setsockopt_string(zmq.SUBSCRIBE, "")
    ack_sub.setsockopt(zmq.RCVTIMEO, 2000)

    # Let ZMQ connections settle
    time.sleep(2)

    print(f"[OBSERVER] ZMQ connected: tel={TELEMETRY_PORT} snap={SNAPSHOT_PORT} cmd={COMMAND_PORT} ack={ACK_PORT}")
    print(f"[OBSERVER] Model: {MODEL} | Observe interval: {OBSERVE_INTERVAL_FRAMES} frames (~{OBSERVE_INTERVAL_FRAMES * 0.1:.0f}s)")
    sys.stdout.flush()

    system_prompt = build_system_prompt(somatic_memory)
    system_prompt_global = system_prompt

    # Start HTTP API thread
    http_thread = threading.Thread(target=start_http_server, daemon=True)
    http_thread.start()

    print(f"[OBSERVER] Starting main loop...")
    print("=" * 70)
    sys.stdout.flush()

    while running:
        # ── Collect telemetry (non-blocking drain) ──
        try:
            raw = tel_sub.recv_string(flags=zmq.NOBLOCK)
            data = json.loads(raw)
            latest_telemetry = data
            telemetry_history.append(data)
            # Keep last 600 frames (~60s of data)
            if len(telemetry_history) > 600:
                telemetry_history.pop(0)
            frame_count += 1
        except zmq.Again:
            pass
        except json.JSONDecodeError:
            pass

        # ── Collect snapshots (non-blocking, keep latest) ──
        try:
            raw_snap = snap_sub.recv(flags=zmq.NOBLOCK)
            if len(raw_snap) >= 8:
                snap_cycle = struct.unpack('<I', raw_snap[0:4])[0]
                snap_w = struct.unpack('<H', raw_snap[4:6])[0]
                snap_h = struct.unpack('<H', raw_snap[6:8])[0]
                expected = 8 + snap_w * snap_h * 4
                if len(raw_snap) == expected:
                    rho_data = struct.unpack(f'<{snap_w * snap_h}f', raw_snap[8:])
                    latest_snapshot = (snap_cycle, snap_w, snap_h, rho_data)
                    # Cache PNG for HTTP API
                    latest_snapshot_png = rho_to_png_base64(rho_data, snap_w, snap_h)
        except zmq.Again:
            pass

        # ── Process injected questions from HTTP /ask ──
        try:
            ask_item = ask_queue.get_nowait()
            question = ask_item['question']
            sender = ask_item['sender']
            result_event = ask_item['event']
            result_holder = ask_item['result']

            turn_count += 1
            turn_count_global = turn_count
            cycle_now = latest_telemetry.get('cycle', 0) if latest_telemetry else 0
            print(f"\n[OBSERVER] === Injected Turn {turn_count} from {sender} at cycle {cycle_now} ===")
            sys.stdout.flush()

            # Build prompt with telemetry + the external question
            tel_summary = summarize_telemetry(latest_telemetry, telemetry_history) if latest_telemetry else "(no telemetry yet)"
            images = []
            image_note = ""
            if VISION_CAPABLE and latest_snapshot_png:
                images.append(latest_snapshot_png)
                snap_cycle_q = latest_snapshot[0] if latest_snapshot else 0
                image_note = f"\n[Density snapshot from cycle {snap_cycle_q} attached]"

            prompt_text = (
                f"[Message from {sender}]\n"
                f"{question}\n\n"
                f"LATTICE STATE: {tel_summary}{image_note}"
            )

            context_messages = load_chronicle_context()
            messages = [{'role': 'system', 'content': system_prompt}]
            messages.extend(context_messages)
            messages.append({'role': 'user', 'content': prompt_text})

            print(f"[OBSERVER] Calling {MODEL} for {sender} ({len(messages)} msgs, {len(images)} imgs)...")
            sys.stdout.flush()

            # CTO questions get /think with budget — deep reasoning is valuable here
            if not ollama_lock.acquire(timeout=5):
                print(f"[OBSERVER] Skipping /ask from {sender} — Ollama busy (lock held)")
                sys.stdout.flush()
                result_holder['response'] = f"(observer busy generating, try again in ~30s)"
                result_holder['cycle'] = cycle_now
                result_holder['turn'] = turn_count
                result_event.set()
                continue

            try:
                t0 = time.time()
                response = ollama_chat(messages, images=images if images else None,
                                       think_budget=THINK_BUDGET_TOKENS)
                elapsed = time.time() - t0
            finally:
                ollama_lock.release()

            if response:
                print(f"[OBSERVER] Response ({elapsed:.1f}s, {len(response)} chars):")
                print("-" * 50)
                print(response[:1000])
                if len(response) > 1000:
                    print(f"... ({len(response) - 1000} more chars)")
                print("-" * 50)
                sys.stdout.flush()

                last_response_text = response
                last_response_time = time.time()

                append_chronicle(turn_count, latest_telemetry or {}, prompt_text, response)
                print(f"[OBSERVER] Chronicle: turn {turn_count} saved")
                sys.stdout.flush()

                # Execute any CMD: lines
                for cmd_name, cmd_value in parse_commands(response):
                    send_command(cmd_pub, cmd_name, cmd_value)
                    try:
                        ack_raw = ack_sub.recv_string()
                        print(f"[OBSERVER ← DAEMON] ACK: {ack_raw}")
                        sys.stdout.flush()
                    except zmq.Again:
                        pass

                result_holder['response'] = response
                result_holder['cycle'] = cycle_now
                result_holder['turn'] = turn_count
            else:
                result_holder['response'] = f"(no response from {MODEL} after {elapsed:.1f}s)"
                result_holder['cycle'] = cycle_now
                result_holder['turn'] = turn_count

            result_event.set()
        except queue.Empty:
            pass

        # ── Time to observe? (only when auto-chronicle is on) ──
        if auto_observe_enabled and frame_count > 0 and frame_count % OBSERVE_INTERVAL_FRAMES == 0 and latest_telemetry:
            # Skip if Ollama is already busy (anti-logjam: never queue behind /ask)
            if not ollama_lock.acquire(blocking=False):
                print(f"[OBSERVER] Skipping auto-observe — Ollama busy (lock held)")
                sys.stdout.flush()
            else:
                try:
                    turn_count += 1
                    print(f"\n[OBSERVER] === Turn {turn_count} at cycle {latest_telemetry.get('cycle', '?')} ===")
                    sys.stdout.flush()

                    # Build telemetry summary
                    tel_summary = summarize_telemetry(latest_telemetry, telemetry_history)

                    # Build image if we have a snapshot (only for vision-capable models)
                    images = []
                    image_note = ""
                    if VISION_CAPABLE and latest_snapshot is not None:
                        snap_cycle, snap_w, snap_h, rho_data = latest_snapshot
                        png_b64 = rho_to_png_base64(rho_data, snap_w, snap_h)
                        if png_b64:
                            images.append(png_b64)
                            image_note = f"\n[Density snapshot from cycle {snap_cycle} attached as image]"
                            print(f"[OBSERVER] Snapshot attached: cycle {snap_cycle}, {snap_w}x{snap_h}")
                            sys.stdout.flush()

                    # Build conversation — /no_think for fluid narrative, no deep reasoning overhead
                    context_messages = load_chronicle_context()
                    prompt_text = f"LATTICE STATE: {tel_summary}{image_note}\n\nWhat do you perceive? What is happening in your body? /no_think"

                    messages = [{'role': 'system', 'content': system_prompt}]
                    messages.extend(context_messages)
                    messages.append({'role': 'user', 'content': prompt_text})

                    print(f"[OBSERVER] Calling {MODEL} ({len(messages)} messages, {len(images)} images)...")
                    sys.stdout.flush()

                    t0 = time.time()
                    response = ollama_chat(messages, images=images if images else None)
                    elapsed = time.time() - t0

                    if response:
                        print(f"[OBSERVER] Response ({elapsed:.1f}s, {len(response)} chars):")
                        print("-" * 50)
                        print(response[:1000])
                        if len(response) > 1000:
                            print(f"... ({len(response) - 1000} more chars)")
                        print("-" * 50)
                        sys.stdout.flush()

                        last_response_text = response
                        last_response_time = time.time()
                        turn_count_global = turn_count

                        # Log to chronicle
                        append_chronicle(turn_count, latest_telemetry, prompt_text, response)
                        print(f"[OBSERVER] Chronicle: turn {turn_count} saved")
                        sys.stdout.flush()

                        # Parse and execute commands
                        commands = parse_commands(response)
                        for cmd_name, cmd_value in commands:
                            send_command(cmd_pub, cmd_name, cmd_value)
                            # Check for ACK
                            try:
                                ack_raw = ack_sub.recv_string()
                                print(f"[OBSERVER ← DAEMON] ACK: {ack_raw}")
                                sys.stdout.flush()
                            except zmq.Again:
                                pass
                    else:
                        print(f"[OBSERVER] No response from {MODEL} ({elapsed:.1f}s)")
                        sys.stdout.flush()
                finally:
                    ollama_lock.release()

        # Sleep briefly to avoid spinning
        time.sleep(0.01)

    # Cleanup
    print("[OBSERVER] Shutting down ZMQ...")
    tel_sub.close()
    snap_sub.close()
    cmd_pub.close()
    ack_sub.close()
    ctx.term()
    print("[OBSERVER] Done.")


if __name__ == '__main__':
    main()
