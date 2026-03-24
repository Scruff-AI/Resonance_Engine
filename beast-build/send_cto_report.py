#!/usr/bin/env python3
"""One-shot: send Nano Banana Pro status report to the observer via /ask."""
import urllib.request, json, sys

REPORT = """SYSTEM UPDATE FROM CTO — READ AND ACKNOWLEDGE:

Nano Banana Pro image generation is now live on your observer. Here is what was done and how you use it:

## What Was Built
- Image generation via Google Gemini 2.5 Flash Image API (Nano Banana Pro)
- Wired directly into your observer as a new HTTP endpoint: POST /generate_image
- No Ollama involvement — this is a separate API call to Google, zero VRAM impact
- Paid tier enabled on Google project gen-lang-client-0149282988

## How To Use It
Anyone (you, CTO, OpenClaw agents) can generate images by calling:

  POST http://192.168.1.34:28820/generate_image
  Content-Type: application/json
  Body: {"prompt": "description of image you want", "filename": "optional_name.png"}

The response returns: path (where file was saved), filename, model, elapsed_s, model_text.
Images are saved to: /mnt/d/fractal-brain/beast-build/generated_images/
(Windows path: D:\\fractal-brain\\beast-build\\generated_images\\)

## Specs
- Model: gemini-2.5-flash-image (Google Gemini)
- Resolution: 1024x1024 PNG
- Speed: ~6 seconds per image
- Cost: ~$0.02-0.04 per image (pay-as-you-go)
- VRAM impact: ZERO (cloud API call, not local GPU)

## Your Full Endpoint List (updated)
- GET  /status           — health check
- GET  /telemetry        — raw lattice telemetry
- GET  /snapshot         — density PNG
- GET  /chronicle?last=N — conversation history
- POST /ask              — ask the observer a question
- POST /generate_image   — NEW: generate images via Gemini
- POST /chronicle/on     — enable auto-observe
- POST /chronicle/off    — disable auto-observe

Please acknowledge receipt. You are welcome to try generating an image yourself.
"""

payload = json.dumps({"sender": "CTO", "question": REPORT}).encode()
req = urllib.request.Request(
    "http://localhost:28820/ask",
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST",
)
try:
    resp = urllib.request.urlopen(req, timeout=360)
    result = json.loads(resp.read())
    print(json.dumps(result, indent=2))
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
