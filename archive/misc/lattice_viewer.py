#!/usr/bin/env python3
"""
Live lattice viewer — subscribes to ZMQ snapshot feed (port 5558)
and displays the density field as a real-time heatmap in a pygame window.

Runs as a standalone program, completely decoupled from the daemon.
No daemon changes needed. Just: python lattice_viewer.py

Controls:
  C      — cycle colormap (inferno/viridis/plasma/coolwarm/turbo)
  SPACE  — pause/resume
  S      — save current frame as PNG
  +/-    — adjust contrast (auto-range scaling)
  R      — reset contrast to auto
  Q/ESC  — quit
"""

import sys
import struct
import time
import numpy as np

try:
    import zmq
except ImportError:
    print("ERROR: pip install pyzmq"); sys.exit(1)
try:
    import pygame
except ImportError:
    print("ERROR: pip install pygame"); sys.exit(1)

# --- Config ---
ZMQ_ADDR = "tcp://127.0.0.1:5558"
WINDOW_SIZE = 768       # display window (square)
NX, NY = 1024, 1024     # expected grid — header overrides
COLORMAPS = ["inferno", "viridis", "plasma", "coolwarm", "turbo"]
TARGET_FPS = 60

def build_lut(name, n=256):
    """Build a 256-entry RGB lookup table for a named colormap."""
    try:
        import matplotlib.cm as cm
        cmap = cm.get_cmap(name, n)
        return np.array([cmap(i)[:3] for i in range(n)], dtype=np.float32) * 255
    except ImportError:
        # Fallback: simple grayscale→hot gradient
        lut = np.zeros((n, 3), dtype=np.float32)
        for i in range(n):
            t = i / 255.0
            lut[i] = [min(255, t * 512), min(255, max(0, t * 512 - 255)), min(255, max(0, t * 3 * 255 - 2 * 255))]
        return lut

def apply_colormap(data_u8, lut):
    """Map uint8 grayscale to RGB via LUT. Returns (H, W, 3) uint8."""
    return lut[data_u8].astype(np.uint8)

def main():
    # ZMQ subscriber
    ctx = zmq.Context()
    sub = ctx.socket(zmq.SUB)
    sub.setsockopt(zmq.SUBSCRIBE, b"")
    sub.setsockopt(zmq.RCVHWM, 2)        # drop old frames
    sub.setsockopt(zmq.CONFLATE, 1)       # only keep latest
    sub.connect(ZMQ_ADDR)

    # Pygame
    pygame.init()
    screen = pygame.display.set_mode((WINDOW_SIZE, WINDOW_SIZE))
    pygame.display.set_caption("Khra'gixx Lattice Viewer")
    clock = pygame.time.Clock()
    font = pygame.font.SysFont("consolas", 16)

    # State
    cmap_idx = 0
    luts = {name: build_lut(name) for name in COLORMAPS}
    paused = False
    contrast_boost = 1.0   # multiplier on auto-range
    last_frame = None
    frame_count = 0
    fps_time = time.time()
    display_fps = 0.0
    cycle_num = 0

    print(f"Lattice Viewer started — subscribing to {ZMQ_ADDR}")
    print(f"Controls: C=colormap, SPACE=pause, S=save, +/-=contrast, R=reset, Q=quit")

    running = True
    while running:
        # Events
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN:
                if event.key in (pygame.K_q, pygame.K_ESCAPE):
                    running = False
                elif event.key == pygame.K_c:
                    cmap_idx = (cmap_idx + 1) % len(COLORMAPS)
                    print(f"Colormap: {COLORMAPS[cmap_idx]}")
                elif event.key == pygame.K_SPACE:
                    paused = not paused
                    print(f"{'Paused' if paused else 'Resumed'}")
                elif event.key == pygame.K_s and last_frame is not None:
                    fname = f"lattice_frame_{cycle_num}.png"
                    pygame.image.save(screen, fname)
                    print(f"Saved: {fname}")
                elif event.key in (pygame.K_PLUS, pygame.K_EQUALS, pygame.K_KP_PLUS):
                    contrast_boost = min(contrast_boost * 1.5, 100.0)
                    print(f"Contrast: {contrast_boost:.1f}x")
                elif event.key in (pygame.K_MINUS, pygame.K_KP_MINUS):
                    contrast_boost = max(contrast_boost / 1.5, 0.1)
                    print(f"Contrast: {contrast_boost:.1f}x")
                elif event.key == pygame.K_r:
                    contrast_boost = 1.0
                    print("Contrast reset")

        # Receive snapshot (non-blocking)
        if not paused:
            try:
                raw = sub.recv(zmq.NOBLOCK)
                if len(raw) >= 8:
                    cycle_num = struct.unpack('<I', raw[0:4])[0]
                    w = struct.unpack('<H', raw[4:6])[0]
                    h = struct.unpack('<H', raw[6:8])[0]
                    expected = 8 + w * h * 4
                    if len(raw) >= expected:
                        rho = np.frombuffer(raw, dtype=np.float32, offset=8, count=w*h).reshape(h, w)
                        last_frame = rho
            except zmq.Again:
                pass

        # Render
        if last_frame is not None:
            rho = last_frame
            # Normalize: density hovers near 1.0, deviations are small
            deviation = rho - 1.0
            vmax = max(abs(deviation.min()), abs(deviation.max()), 1e-8) / contrast_boost
            normalized = np.clip(deviation / vmax * 0.5 + 0.5, 0, 1)
            u8 = (normalized * 255).astype(np.uint8)

            lut = luts[COLORMAPS[cmap_idx]]
            rgb = apply_colormap(u8, lut)

            # pygame surfarray expects (W, H, 3) — transpose axes 0,1
            surf = pygame.surfarray.make_surface(rgb.swapaxes(0, 1))
            scaled = pygame.transform.scale(surf, (WINDOW_SIZE, WINDOW_SIZE))
            screen.blit(scaled, (0, 0))
        else:
            screen.fill((20, 20, 30))
            waiting = font.render("Waiting for lattice snapshots...", True, (200, 200, 200))
            screen.blit(waiting, (WINDOW_SIZE // 2 - waiting.get_width() // 2, WINDOW_SIZE // 2))

        # HUD overlay
        frame_count += 1
        now = time.time()
        if now - fps_time >= 1.0:
            display_fps = frame_count / (now - fps_time)
            frame_count = 0
            fps_time = now

        hud_lines = [
            f"Cycle: {cycle_num:,}",
            f"FPS: {display_fps:.0f}",
            f"Cmap: {COLORMAPS[cmap_idx]}",
            f"Contrast: {contrast_boost:.1f}x",
        ]
        if paused:
            hud_lines.append("PAUSED")
        for i, line in enumerate(hud_lines):
            label = font.render(line, True, (255, 255, 255), (0, 0, 0))
            screen.blit(label, (8, 8 + i * 20))

        pygame.display.flip()
        clock.tick(60)

    pygame.quit()
    sub.close()
    ctx.term()
    print("Viewer closed.")

if __name__ == "__main__":
    main()
