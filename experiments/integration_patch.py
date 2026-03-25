# Integration Patch for golden_weave_memory.py into lattice_observer.py
# Apply these changes to integrate the Golden-Weave Memory System

# ── STEP 1: ADD IMPORTS ─────────────────────────────────────────────────
# Add near the top of lattice_observer.py, after existing imports:

import sys
sys.path.insert(0, '/mnt/d/openclaw-local/workspace-main')  # Add path to golden_weave_memory

try:
    from golden_weave_memory import (
        GoldenWeaveMemorySystem,
        LocalFieldState,
        AttractorDefinition,
        HysteresisBuffer,
        PHI,
        INV_PHI_SQUARED
    )
    MEMORY_SYSTEM_AVAILABLE = True
    print("[OBSERVER] Golden-Weave Memory System loaded successfully")
except ImportError as e:
    print(f"[OBSERVER] Warning: Could not load Golden-Weave Memory System: {e}")
    MEMORY_SYSTEM_AVAILABLE = False


# ── STEP 2: ADD TO GLOBALS ──────────────────────────────────────────────
# Add after other globals (around line 80):

# Golden-Weave Memory System
memory_system = None  # Initialized in main()
latest_density_field = None
latest_stress_xx = None
latest_stress_yy = None
latest_stress_xy = None
latest_vorticity_field = None
latest_velocity_field = None


# ── STEP 3: INITIALIZE MEMORY SYSTEM ────────────────────────────────────
# In the main() function or at startup, add:

def initialize_memory_system():
    """Initialize the Golden-Weave Memory System."""
    global memory_system
    if MEMORY_SYSTEM_AVAILABLE:
        memory_system = GoldenWeaveMemorySystem(
            attractor_dir="/mnt/d/Resonance_Engine/beast-build/attractors",
            grid_size=1024
        )
        print(f"[OBSERVER] Memory system initialized with {len(memory_system.list_attractors())} stored attractors")
    else:
        print("[OBSERVER] Memory system not available")


# ── STEP 4: UPDATE FIELD STORAGE ────────────────────────────────────────
# In the zmq_telemetry_thread() where telemetry is received, add field extraction:

def extract_fields_from_telemetry(telemetry):
    """Extract field arrays from telemetry for memory system."""
    global latest_density_field, latest_stress_xx, latest_stress_yy
    global latest_stress_xy, latest_vorticity_field, latest_velocity_field
    
    # These would need to be provided by the daemon via ZMQ
    # For now, placeholders - the daemon would need to send these fields
    if 'density_field' in telemetry:
        latest_density_field = np.array(telemetry['density_field']).reshape(1024, 1024)
    if 'stress_xx' in telemetry:
        latest_stress_xx = np.array(telemetry['stress_xx']).reshape(1024, 1024)
    if 'stress_yy' in telemetry:
        latest_stress_yy = np.array(telemetry['stress_yy']).reshape(1024, 1024)
    if 'stress_xy' in telemetry:
        latest_stress_xy = np.array(telemetry['stress_xy']).reshape(1024, 1024)
    if 'vorticity' in telemetry:
        latest_vorticity_field = np.array(telemetry['vorticity']).reshape(1024, 1024)
    if 'velocity' in telemetry:
        latest_velocity_field = np.array(telemetry['velocity']).reshape(1024, 1024, 2)


# ── STEP 5: EXTEND HTTP HANDLER ─────────────────────────────────────────
# Add new methods to ObserverAPIHandler class:

class ObserverAPIHandler(BaseHTTPRequestHandler):
    # ... existing methods ...
    
    def do_GET(self):
        if self.path == '/status':
            self._handle_status()
        elif self.path == '/snapshot':
            self._handle_snapshot()
        elif self.path.startswith('/chronicle'):
            self._handle_chronicle()
        elif self.path == '/telemetry':
            self._handle_telemetry()
        # NEW ENDPOINTS:
        elif self.path.startswith('/query_local'):
            self._handle_query_local()
        elif self.path == '/list_attractors':
            self._handle_list_attractors()
        elif self.path.startswith('/recall_attractor'):
            self._handle_recall_attractor()
        else:
            # ... existing help response with new endpoints added ...
            pass
    
    def do_POST(self):
        global auto_observe_enabled
        if self.path == '/ask':
            self._handle_ask()
        elif self.path == '/generate_image':
            self._handle_generate_image()
        elif self.path == '/chronicle/on':
            auto_observe_enabled = True
            self._send_json({'auto_chronicle': True})
        elif self.path == '/chronicle/off':
            auto_observe_enabled = False
            self._send_json({'auto_chronicle': False})
        # NEW ENDPOINTS:
        elif self.path == '/store_attractor':
            self._handle_store_attractor()
        else:
            self._send_json({'error': 'unknown endpoint'}, 404)
    
    # NEW HANDLER METHODS:
    
    def _handle_query_local(self):
        """Handle GET /query_local?x=512&y=512"""
        if not memory_system:
            self._send_json({'error': 'memory system not available'}, 503)
            return
        
        # Parse query parameters
        x, y = 512, 512  # defaults
        if '?' in self.path:
            params = self.path.split('?', 1)[1]
            for part in params.split('&'):
                if part.startswith('x='):
                    x = int(part[2:])
                elif part.startswith('y='):
                    y = int(part[2:])
        
        # Check if fields are available
        if latest_density_field is None:
            self._send_json({'error': 'field data not available from daemon'}, 503)
            return
        
        try:
            local_state = memory_system.query_local_field(
                x=x, y=y,
                density_field=latest_density_field,
                stress_xx=latest_stress_xx or np.zeros((1024, 1024)),
                stress_yy=latest_stress_yy or np.zeros((1024, 1024)),
                stress_xy=latest_stress_xy or np.zeros((1024, 1024)),
                vorticity_field=latest_vorticity_field or np.zeros((1024, 1024)),
                velocity_field=latest_velocity_field or np.zeros((1024, 1024, 2)),
                current_cycle=latest_telemetry.get('cycle', 0) if latest_telemetry else 0
            )
            
            self._send_json({
                'command': 'query_local',
                'x': x,
                'y': y,
                'density': local_state.density,
                'stress_divergence': local_state.stress_divergence,
                'stress_magnitude': local_state.stress_magnitude,
                'vorticity': local_state.vorticity,
                'velocity': [local_state.velocity_x, local_state.velocity_y],
                'cycle': local_state.cycle
            })
        except Exception as e:
            self._send_json({'error': str(e)}, 500)
    
    def _handle_store_attractor(self):
        """Handle POST /store_attractor with JSON body"""
        if not memory_system:
            self._send_json({'error': 'memory system not available'}, 503)
            return
        
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
        
        # Check if fields are available
        if latest_density_field is None:
            self._send_json({'error': 'field data not available'}, 503)
            return
        
        try:
            # Query current state at location
            local_state = memory_system.query_local_field(
                x=x, y=y,
                density_field=latest_density_field,
                stress_xx=latest_stress_xx or np.zeros((1024, 1024)),
                stress_yy=latest_stress_yy or np.zeros((1024, 1024)),
                stress_xy=latest_stress_xy or np.zeros((1024, 1024)),
                vorticity_field=latest_vorticity_field or np.zeros((1024, 1024)),
                velocity_field=latest_velocity_field or np.zeros((1024, 1024, 2)),
                current_cycle=latest_telemetry.get('cycle', 0) if latest_telemetry else 0
            )
            
            # Get injection params from request or use defaults
            injection_params = {
                'amplitude': data.get('amplitude', 0.05),
                'radius': data.get('injection_radius', 20),
                'num_injections': data.get('num_injections', 5),
                'omega': data.get('omega', 1.97)
            }
            
            # Store the attractor
            attractor = memory_system.store_attractor(
                name=name,
                center_x=x,
                center_y=y,
                radius=radius,
                local_state=local_state,
                injection_params=injection_params,
                density_snapshot=latest_density_field if radius > 50 else None
            )
            
            self._send_json({
                'command': 'store_attractor',
                'name': name,
                'properties': memory_system.get_attractor_properties(name),
                'status': 'stored'
            })
        except Exception as e:
            self._send_json({'error': str(e)}, 500)
    
    def _handle_list_attractors(self):
        """Handle GET /list_attractors"""
        if not memory_system:
            self._send_json({'error': 'memory system not available'}, 503)
            return
        
        try:
            attractors = memory_system.list_attractors()
            properties = [memory_system.get_attractor_properties(name) for name in attractors]
            
            self._send_json({
                'command': 'list_attractors',
                'count': len(attractors),
                'attractors': properties
            })
        except Exception as e:
            self._send_json({'error': str(e)}, 500)
    
    def _handle_recall_attractor(self):
        """Handle GET /recall_attractor?name=fire"""
        if not memory_system:
            self._send_json({'error': 'memory system not available'}, 503)
            return
        
        # Parse query parameters
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
                'command': 'recall_attractor',
                'name': name,
                'center': [attractor.center_x, attractor.center_y],
                'injection_amplitude': attractor.injection_amplitude,
                'injection_radius': attractor.injection_radius,
                'num_injections': attractor.num_injections,
                'omega': attractor.omega_at_creation,
                'properties': memory_system.get_attractor_properties(name),
                'status': 'ready_for_injection'
            })
        except Exception as e:
            self._send_json({'error': str(e)}, 500)


# ── STEP 6: UPDATE HELP RESPONSE ────────────────────────────────────────
# In the default GET handler (the help endpoint), add:

"""
'endpoints': {
    # ... existing endpoints ...
    'GET /query_local?x=512&y=512': 'Query field properties at specific coordinates',
    'POST /store_attractor': 'Store current field state as named attractor (JSON: name, x, y, radius)',
    'GET /list_attractors': 'List all stored attractors with properties',
    'GET /recall_attractor?name=...': 'Retrieve attractor parameters for reinjection',
}
"""


# ── STEP 7: DAEMON MODIFICATIONS (REQUIRED) ────────────────────────────
# The Khra'gixx daemon must be modified to send full field arrays via ZMQ.
# Add to daemon's telemetry publication:

"""
// In khra_gixx daemon, modify telemetry publishing:

// Pack full field arrays (compress or downsample if bandwidth limited)
telemetry["density_field"] = std::vector<float>(rho, rho + NX*NY);
telemetry["stress_xx"] = std::vector<float>(stress_xx, stress_xx + NX*NY);
telemetry["stress_yy"] = std::vector<float>(stress_yy, stress_yy + NX*NY);
telemetry["stress_xy"] = std::vector<float>(stress_xy, stress_xy + NX*NY);
telemetry["vorticity"] = std::vector<float>(vorticity, vorticity + NX*NY);
telemetry["velocity"] = std::vector<float>(vel, vel + NX*NY*2);

// Send via ZMQ PUB on telemetry port
"""

# Without these fields from the daemon, query_local will return zeros/placeholders.


# ── STEP 8: INITIALIZATION CALL ────────────────────────────────────────
# Add to main() or startup sequence:

"""
def main():
    # ... existing initialization ...
    
    # Initialize Golden-Weave Memory System
    initialize_memory_system()
    
    # ... rest of main ...
"""


# End of integration patch
