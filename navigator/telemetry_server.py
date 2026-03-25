# telemetry_server.py
# HTTP Telemetry Endpoint for Resonance Engine (no Flask)

import zmq
import json
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

# ZMQ connection to Resonance Engine daemon
context = zmq.Context()
socket = context.socket(zmq.SUB)
socket.connect("tcp://localhost:5556")
socket.setsockopt_string(zmq.SUBSCRIBE, "")

# Cache latest telemetry
latest_telemetry = {
    "cycle": 0,
    "coherence": 0.0,
    "asymmetry": 0.0,
    "torque": 0.0,
    "gpu_temp": 0.0,
    "gpu_power": 0.0,
    "grid": 512,
    "timestamp": None
}

def zmq_listener():
    """Background thread to listen for ZMQ messages"""
    global latest_telemetry
    print("[ZMQ Listener] Starting...")
    while True:
        try:
            data = socket.recv_json(flags=zmq.NOBLOCK)
            latest_telemetry.update(data)
            latest_telemetry["timestamp"] = time.time()
        except zmq.Again:
            time.sleep(0.001)
        except Exception as e:
            print(f"[ZMQ Listener] Error: {e}")
            time.sleep(0.1)

class TelemetryHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/telemetry':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(latest_telemetry).encode())
        elif self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                "status": "ok",
                "source": "beast-resonance-engine",
                "grid": latest_telemetry["grid"],
                "cycle": latest_telemetry["cycle"]
            }).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        pass  # Suppress logs

if __name__ == '__main__':
    # Start ZMQ listener in background
    listener_thread = threading.Thread(target=zmq_listener, daemon=True)
    listener_thread.start()
    
    server = HTTPServer(('0.0.0.0', 28811), TelemetryHandler)
    print("[HTTP Server] Starting on port 28811...")
    server.serve_forever()
