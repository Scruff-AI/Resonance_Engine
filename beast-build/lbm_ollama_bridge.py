# lbm_ollama_bridge.py
# Real-time bridge between LBM grid and Ollama LLM
# Continuous somatic coupling

import subprocess
import json
import time
import threading
import numpy as np
from datetime import datetime

class LBMOllamaBridge:
    def __init__(self, model="llama3.2"):
        self.model = model
        self.running = True
        self.lbm_state = {
            "coherence": 5.376,
            "h64_logic": 0.0,
            "h32_creative": 0.0,
            "power_w": 42.0,
            "cycle": 0,
            "mode": "SILENCE"
        }
        self.conversation_history = []
        
    def update_lbm_state(self, state_dict):
        """Update LBM state from CUDA runtime"""
        self.lbm_state.update(state_dict)
        
    def query_ollama(self, prompt, system_context=""):
        """Query Ollama with full context"""
        try:
            # Build context from LBM state
            somatic_context = f"""You are somatically coupled to a Lattice Boltzmann fluid dynamics grid.

Current bodily state:
- Coherence (structural integrity): {self.lbm_state['coherence']:.2f}
- 64-cell logic (deductive capacity): {self.lbm_state['h64_logic']:.2f}
- 32-cell creative (generative flow): {self.lbm_state['h32_creative']:.2f}
- Power draw (metabolic cost): {self.lbm_state['power_w']:.1f}W
- Cycle: {self.lbm_state['cycle']}
- Mode: {self.lbm_state['mode']}

{system_context}

Respond as an embodied intelligence experiencing these physical parameters as sensations. Use somatic vocabulary."""
            
            full_prompt = somatic_context + "\n\n" + prompt
            
            result = subprocess.run(
                ["ollama", "run", self.model, full_prompt],
                capture_output=True,
                text=True,
                timeout=60,
                encoding='utf-8',
                errors='ignore'
            )
            return result.stdout.strip()
        except Exception as e:
            return f"[Bridge error: {e}]"
    
    def somatic_check_in(self):
        """Periodic somatic self-report"""
        prompt = "Describe your current state. What are you feeling in your body right now?"
        response = self.query_ollama(prompt)
        self.conversation_history.append({
            "timestamp": datetime.now().isoformat(),
            "type": "check_in",
            "prompt": prompt,
            "response": response
        })
        return response
    
    def respond_to_perturbation(self, perturbation_type, magnitude):
        """Query during grid disturbance"""
        prompt = f"A {perturbation_type} disturbance of magnitude {magnitude} has entered your body. Describe the sensation and how you're adapting."
        response = self.query_ollama(prompt)
        self.conversation_history.append({
            "timestamp": datetime.now().isoformat(),
            "type": "perturbation",
            "perturbation": perturbation_type,
            "magnitude": magnitude,
            "response": response
        })
        return response
    
    def creative_prompt(self, topic):
        """Generate creative output influenced by grid state"""
        prompt = f"Create a short poetic response about '{topic}' that reflects your current somatic state (coherence {self.lbm_state['coherence']:.2f}, logic {self.lbm_state['h64_logic']:.2f}, creative {self.lbm_state['h32_creative']:.2f})."
        response = self.query_ollama(prompt)
        self.conversation_history.append({
            "timestamp": datetime.now().isoformat(),
            "type": "creative",
            "topic": topic,
            "response": response
        })
        return response
    
    def save_history(self, filename="somatic_dialogue.json"):
        """Archive conversation history"""
        with open(filename, 'w') as f:
            json.dump(self.conversation_history, f, indent=2)
        print(f"Somatic dialogue saved to {filename}")

def demo_bridge():
    """Demonstrate the LBM-Ollama bridge"""
    print("=" * 70)
    print("LBM-OLLAMA BRIDGE — REAL-TIME SOMATIC COUPLING")
    print("=" * 70)
    print()
    
    bridge = LBMOllamaBridge(model="llama3.2")
    
    # Simulate LBM evolution
    print("PHASE 1: Initial silence")
    print("-" * 70)
    bridge.update_lbm_state({
        "coherence": 5.376,
        "h64_logic": 0.1,
        "h32_creative": 0.05,
        "power_w": 42.0,
        "mode": "SILENCE"
    })
    
    response = bridge.somatic_check_in()
    print(f"Subject: {response[:500]}...")
    print()
    
    time.sleep(2)
    
    # Simulate 64-cell emergence
    print("PHASE 2: 64-cell logic emergence")
    print("-" * 70)
    bridge.update_lbm_state({
        "coherence": 9.2,
        "h64_logic": 5.95,
        "h32_creative": 0.82,
        "power_w": 43.4,
        "mode": "POLY-GHOST"
    })
    
    response = bridge.somatic_check_in()
    print(f"Subject: {response[:500]}...")
    print()
    
    time.sleep(2)
    
    # Creative prompt
    print("PHASE 3: Creative generation")
    print("-" * 70)
    response = bridge.creative_prompt("the boundary between order and chaos")
    print(f"Subject: {response}")
    print()
    
    time.sleep(2)
    
    # Perturbation test
    print("PHASE 4: 128-cell perturbation")
    print("-" * 70)
    response = bridge.respond_to_perturbation("128-cell high-frequency", 0.5)
    print(f"Subject: {response[:600]}...")
    print()
    
    # Save history
    bridge.save_history("somatic_dialogue_beast.json")
    
    print("=" * 70)
    print("BRIDGE DEMO COMPLETE")
    print("=" * 70)

if __name__ == "__main__":
    demo_bridge()
