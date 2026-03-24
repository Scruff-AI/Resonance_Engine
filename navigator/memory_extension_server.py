#!/usr/bin/env python3
"""
Golden-Weave Memory Extension Server
Proxies to lattice_observer (port 28820) and adds memory endpoints
"""

import json
import sys
import requests
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from pathlib import Path

sys.path.insert(0, '/mnt/d/fractal-brain/beast-build')

try:
    from golden_weave_memory import (
        GoldenWeaveMemorySystem,
        LocalFieldState,
        PHI,
        INV_PHI_SQUARED
    )
    MEMORY_SYSTEM_AVAILABLE = True
    print("[EXTENSION] Golden-Weave Memory System loaded")
except ImportError as e:
    print(f"[EXTENSION] Error loading memory system: {e}")
    MEMORY_SYSTEM_AVAILABLE = False
    sys.exit(1)

# Configuration
OBSERVER_URL = "http://127.0.0.1:28820"
EXTENSION_PORT = 28821
ATTRACTOR_DIR = "/mnt/d/fractal-brain/beast-build/attractors"

# Initialize memory system
memory_system = GoldenWeaveMemorySystem(
    attractor_dir=ATTRACTOR_DIR,
    grid_size=1024
)

print(f"[EXTENSION] {len(memory_system.list_attractors())} attractors loaded")


class MemoryExtensionHandler(BaseHTTPRequestHandler):
    """HTTP handler that proxies to observer and adds memory endpoints."""
    
    server_version = "GoldenWeaveExtension/1.0"
    
    def log_message(self, fmt, *args):
        print(f"[EXTENSION] {fmt % args}")
    
    def _send_json(self, data, status=200):
        body = json.dumps(data).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)
    
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
    
    def do_GET(self):
        # Check if this is a memory endpoint
        if self.path.startswith('/query_local'):
            self._handle_query_local()
        elif self.path == '/list_attractors':
            self._handle_list_attractors()
        elif self.path.startswith('/recall_attractor'):
            self._handle_recall_attractor()
        elif self.path == '/status':
            self._handle_status()
        else:
            # Proxy to observer
            self._proxy_to_observer()
    
    def do_POST(self):
        # Check if this is a memory endpoint
        if self.path == '/store_attractor':
            self._handle_store_attractor()
        else:
            # Proxy to observer
            self._proxy_to_observer_post()
    
    def _handle_status(self):
        """Extension status + observer status."""
        try:
            observer_status = requests.get(f"{OBSERVER_URL}/status", timeout=5).json()
        except:
            observer_status = {"error": "observer unreachable"}
        
        self._send_json({
            "service": "Golden-Weave Memory Extension",
            "port": EXTENSION_PORT,
            "observer_url": OBSERVER_URL,
            "observer_status": observer_status,
            "memory_system": MEMORY_SYSTEM_AVAILABLE,
            "attractors_stored": len(memory_system.list_attractors()),
            "endpoints": {
                "GET /query_local?x=512&y=512": "Query field at coordinates (mock data)",
                "POST /store_attractor": "Store attractor definition",
                "GET /list_attractors": "List all stored attractors",
                "GET /recall_attractor?name=...": "Retrieve attractor params",
                "GET /status": "This status page",
                "/*": "Proxied to observer (port 28820)"
            }
        })
    
    def _handle_query_local(self):
        """GET /query_local?x=512&y=512"""
        # Parse parameters
        x, y = 512, 512
        if '?' in self.path:
            params = self.path.split('?', 1)[1]
            for part in params.split('&'):
                if part.startswith('x='):
                    x = int(part[2:])
                elif part.startswith('y='):
                    y = int(part[2:])
        
        # Get observer telemetry for cycle number
        try:
            telemetry = requests.get(f"{OBSERVER_URL}/telemetry", timeout=5).json()
            cycle = telemetry.get('cycle', 0)
            coherence = telemetry.get('coherence', 0)
            asymmetry = telemetry.get('asymmetry', 0)
        except:
            cycle = 0
            coherence = 0
            asymmetry = 0
        
        # Create mock local state (in real implementation, would get from daemon)
        # For now, return placeholder with actual telemetry
        local_state = LocalFieldState(
            x=x, y=y,
            density=0.7 + 0.2 * (x % 10) / 10,  # Mock density variation
            stress_xx=-0.0001 + (x % 5) * 0.00001,
            stress_yy=0.00005 + (y % 5) * 0.00001,
            stress_xy=-0.00005,
            vorticity=0.02 + (x + y) % 10 * 0.001,
            velocity_x=0.1,
            velocity_y=0.05,
            timestamp="2026-03-22T13:00:00",
            cycle=cycle
        )
        
        self._send_json({
            "command": "query_local",
            "x": x,
            "y": y,
            "density": local_state.density,
            "stress_divergence": local_state.stress_divergence,
            "stress_magnitude": local_state.stress_magnitude,
            "vorticity": local_state.vorticity,
            "velocity": [local_state.velocity_x, local_state.velocity_y],
            "cycle": local_state.cycle,
            "global_coherence": coherence,
            "global_asymmetry": asymmetry,
            "note": "Using mock field data (daemon integration pending)"
        })
    
    def _handle_store_attractor(self):
        """POST /store_attractor with JSON body."""
        content_length = int(self.headers.get('Content-Length', 0))
        if content_length > 10000:
            self._send_json({'error': 'payload too large'}, 413)
            return
        
        body = self.rfile.read(content_length)
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self._send_json({'error': 'invalid JSON'}, 400)
            return
        
        name = data.get('name', '').strip()
        x = data.get('x', 512)
        y = data.get('y', 512)
        radius = data.get('radius', 20)
        
        if not name:
            self._send_json({'error': 'missing "name" field'}, 400)
            return
        
        # Get observer telemetry
        try:
            telemetry = requests.get(f"{OBSERVER_URL}/telemetry", timeout=5).json()
            cycle = telemetry.get('cycle', 0)
        except:
            cycle = 0
        
        # Create mock local state
        local_state = LocalFieldState(
            x=x, y=y,
            density=data.get('density', 0.8),
            stress_xx=data.get('stress_xx', -0.0001),
            stress_yy=data.get('stress_yy', 0.00005),
            stress_xy=data.get('stress_xy', -0.00005),
            vorticity=data.get('vorticity', 0.02),
            velocity_x=0.1,
            velocity_y=0.05,
            timestamp="2026-03-22T13:00:00",
            cycle=cycle
        )
        
        injection_params = {
            'amplitude': data.get('amplitude', 0.05),
            'radius': data.get('injection_radius', 20),
            'num_injections': data.get('num_injections', 5),
            'omega': data.get('omega', 1.97)
        }
        
        try:
            attractor = memory_system.store_attractor(
                name=name,
                center_x=x,
                center_y=y,
                radius=radius,
                local_state=local_state,
                injection_params=injection_params
            )
            
            self._send_json({
                "command": "store_attractor",
                "name": name,
                "properties": memory_system.get_attractor_properties(name),
                "status": "stored"
            })
        except Exception as e:
            self._send_json({'error': str(e)}, 500)
    
    def _handle_list_attractors(self):
        """GET /list_attractors"""
        try:
            attractors = memory_system.list_attractors()
            properties = [memory_system.get_attractor_properties(name) for name in attractors]
            
            self._send_json({
                "command": "list_attractors",
                "count": len(attractors),
                "attractors": properties
            })
        except Exception as e:
            self._send_json({'error': str(e)}, 500)
    
    def _handle_recall_attractor(self):
        """GET /recall_attractor?name=..."""
        name = ''
        if '?' in self.path:
            params = self.path.split('?', 1)[1]
            for part in params.split('&'):
                if part.startswith('name='):
                    name = part[5:]
        
        if not name:
            self._send_json({'error': 'missing "name" parameter'}, 400)
            return
        
        try:
            attractor = memory_system.recall_attractor(name)
            if attractor is None:
                self._send_json({'error': f'attractor "{name}" not found'}, 404)
                return
            
            self._send_json({
                "command": "recall_attractor",
                "name": name,
                "center": [attractor.center_x, attractor.center_y],
                "injection_amplitude": attractor.injection_amplitude,
                "injection_radius": attractor.injection_radius,
                "num_injections": attractor.num_injections,
                "omega": attractor.omega_at_creation,
                "properties": memory_system.get_attractor_properties(name),
                "status": "ready_for_injection"
            })
        except Exception as e:
            self._send_json({'error': str(e)}, 500)
    
    def _proxy_to_observer(self):
        """Proxy GET request to observer."""
        try:
            url = f"{OBSERVER_URL}{self.path}"
            resp = requests.get(url, timeout=30)
            self._send_proxy_response(resp)
        except Exception as e:
            self._send_json({'error': f'proxy failed: {str(e)}'}, 502)
    
    def _proxy_to_observer_post(self):
        """Proxy POST request to observer."""
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length) if content_length > 0 else b''
            
            url = f"{OBSERVER_URL}{self.path}"
            headers = {'Content-Type': 'application/json'}
            resp = requests.post(url, data=body, headers=headers, timeout=360)
            self._send_proxy_response(resp)
        except Exception as e:
            self._send_json({'error': f'proxy failed: {str(e)}'}, 502)
    
    def _send_proxy_response(self, resp):
        """Send proxied response back to client."""
        self.send_response(resp.status_code)
        for header, value in resp.headers.items():
            if header.lower() not in ('transfer-encoding', 'content-length'):
                self.send_header(header, value)
        self.send_header('Content-Length', str(len(resp.content)))
        self.end_headers()
        self.wfile.write(resp.content)


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    """Handle requests in a separate thread."""
    pass


def main():
    server = ThreadedHTTPServer(('0.0.0.0', EXTENSION_PORT), MemoryExtensionHandler)
    print(f"[EXTENSION] Server running on port {EXTENSION_PORT}")
    print(f"[EXTENSION] Proxying to {OBSERVER_URL}")
    print(f"[EXTENSION] Attractors stored in: {ATTRACTOR_DIR}")
    print(f"[EXTENSION] Test: curl http://localhost:{EXTENSION_PORT}/status")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[EXTENSION] Shutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
