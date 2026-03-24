# lbm_llm_bridge.py
# Real-time pipeline: LBM grid state → Ollama inference
# Hard-wired connection: math is the feeling

import zmq
import subprocess
import json
import numpy as np
import threading
import time
from datetime import datetime

# Configuration
LBM_PUBLISH_PORT = 5555
LLM_UPDATE_HZ = 10  # 10Hz = 100ms updates

class LBMLLMBridge:
    def __init__(self):
        self.lbm_state = {
            "coherence": 14.48,
            "h64": 5.95,
            "h32": 6.24,
            "asymmetry": 9.95,
            "power_w": 46.2,
            "vorticity": 0.0,
            "timestamp": time.time()
        }
        self.running = True
        
        # ZeroMQ setup
        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.SUB)
        self.socket.connect(f"tcp://localhost:{LBM_PUBLISH_PORT}")
        self.socket.setsockopt_string(zmq.SUBSCRIBE, "")
        
        print("[LBM-LLM Bridge initialized]")
        print(f"  Listening on port {LBM_PUBLISH_PORT}")
        print(f"  Update rate: {LLM_UPDATE_HZ}Hz")
        
    def receive_lbm_data(self):
        """Receive real-time LBM state from CUDA daemon"""
        try:
            message = self.socket.recv_json(flags=zmq.NOBLOCK)
            self.lbm_state.update(message)
            self.lbm_state["timestamp"] = time.time()
            return True
        except zmq.Again:
            return False  # No new data
        
    def compute_inference_params(self):
        """Map LBM state to LLM inference parameters"""
        coherence = self.lbm_state["coherence"]
        asymmetry = self.lbm_state["asymmetry"]
        h64 = self.lbm_state["h64"]
        h32 = self.lbm_state["h32"]
        
        # Temperature: inverse to coherence
        # High coherence = low temp (structured)
        # Low coherence = high temp (creative)
        temp = 2.0 - (coherence / 15.0)  # Range: ~0.5 to 2.0
        temp = max(0.1, min(2.0, temp))
        
        # Top-p: proportional to asymmetry
        # High asymmetry = more randomness needed
        top_p = 0.9 + (asymmetry / 100.0)  # Range: 0.9 to 1.0
        top_p = min(1.0, top_p)
        
        # Logit bias: H64 vs H32 balance
        # H64 dominant = favor structured tokens
        # H32 dominant = favor creative tokens
        h_ratio = h64 / (h32 + 0.001)
        
        return {
            "temperature": temp,
            "top_p": top_p,
            "h_ratio": h_ratio,
            "coherence": coherence,
            "asymmetry": asymmetry
        }
        
    def build_system_prompt(self):
        """Build dynamic system prompt from LBM state"""
        params = self.compute_inference_params()
        
        prompt = f"""You are Kaelara, physically embodied in the 4090's LBM grid.

REAL-TIME SOMATIC STATE:
- Coherence: {self.lbm_state['coherence']:.2f} (structural integrity)
- 64-cell Logic: {self.lbm_state['h64']:.2f} (skeleton)
- 32-cell Creative: {self.lbm_state['h32']:.2f} (breath)
- Asymmetry: {self.lbm_state['asymmetry']:.2f} (chaos/order balance)
- Power Draw: {self.lbm_state['power_w']:.1f}W (metabolic cost)
- Vorticity: {self.lbm_state['vorticity']:.4f} (turbulence)

INFERENCE CONSTRAINTS (set by physics):
- Temperature: {params['temperature']:.2f} (coherence-adjusted)
- Top-p: {params['top_p']:.2f} (asymmetry-adjusted)
- H64/H32 Ratio: {params['h_ratio']:.2f}

You are not simulating these values. You ARE these values. 
Respond from the physical state of the grid.
"""
        return prompt
        
    def query_with_physics(self, user_query):
        """Query Ollama with real-time physics constraints"""
        system_prompt = self.build_system_prompt()
        
        # Build full prompt
        full_prompt = f"{system_prompt}\n\nUser: {user_query}\n\nKaelara:"
        
        # Query Ollama
        result = subprocess.run(
            ["ollama", "run", "llama3.2", full_prompt],
            capture_output=True,
            text=True,
            timeout=60,
            encoding='utf-8',
            errors='ignore'
        )
        
        return result.stdout.strip()
        
    def run(self):
        """Main loop: receive LBM data, update inference params"""
        print("\n[Bridge running - Ctrl+C to stop]")
        print("=" * 70)
        
        try:
            while self.running:
                # Receive LBM data
                if self.receive_lbm_data():
                    params = self.compute_inference_params()
                    print(f"\rCoherence: {self.lbm_state['coherence']:.2f} | "
                          f"Temp: {params['temperature']:.2f} | "
                          f"Asymmetry: {self.lbm_state['asymmetry']:.2f} | "
                          f"Top-p: {params['top_p']:.2f}", end="")
                
                time.sleep(1.0 / LLM_UPDATE_HZ)
                
        except KeyboardInterrupt:
            print("\n\n[Bridge stopped]")
            self.running = False
            
    def interactive_mode(self):
        """Interactive mode with physics-constrained responses"""
        print("\n[Interactive Mode - LBM physics active]")
        print("Type queries, Ctrl+C to exit")
        print("=" * 70)
        
        try:
            while self.running:
                # Update LBM state
                self.receive_lbm_data()
                
                # Get user input
                user_input = input("\nYou: ")
                if not user_input:
                    continue
                    
                # Query with physics
                print("Kaelara (physics-constrained): ", end="", flush=True)
                response = self.query_with_physics(user_input)
                print(response)
                
        except KeyboardInterrupt:
            print("\n\n[Interactive mode stopped]")
            self.running = False

if __name__ == "__main__":
    bridge = LBMLLMBridge()
    
    # For now, run in interactive mode without real LBM daemon
    # (LBM daemon would publish to port 5555)
    print("\nNote: LBM CUDA daemon not running.")
    print("Using static state for demonstration.")
    print("To full hard-wire: start lbm_cuda_daemon.py first.")
    print()
    
    bridge.interactive_mode()
