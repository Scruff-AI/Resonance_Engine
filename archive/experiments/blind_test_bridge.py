# blind_test_bridge.py
# Fact-first reporting with variable labels and error penalties
# Forces Kaelara to use the pipe as primary sensory organ

import zmq
import subprocess
import json
import time
import random
from datetime import datetime

# LBM Translation Table: Metric → Forced Vocabulary
TRANSLATION_TABLE = {
    "coherence": {
        14.0: "Granite-State",
        14.5: "Granite-State",
        15.0: "Marble-State",
        15.5: "Quartz-State",
        16.0: "Sand-State"
    },
    "h64": {
        6.0: "Iron-Skeleton",
        7.0: "Steel-Skeleton",
        8.0: "Titanium-Skeleton"
    },
    "h32": {
        0.0: "Silent-Breath",
        0.05: "Whisper-Breath",
        0.1: "Breeze-Breath",
        1.0: "Wind-Breath",
        2.0: "Storm-Breath"
    },
    "asymmetry": {
        5.0: "Mirror-Symmetry",
        5.5: "Crystal-Symmetry",
        6.0: "Wave-Symmetry",
        10.0: "Chaos-Symmetry"
    }
}

class BlindTestBridge:
    def __init__(self):
        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.SUB)
        self.socket.connect("tcp://localhost:5555")
        self.socket.setsockopt_string(zmq.SUBSCRIBE, "")
        
        # Variable labels (rotated randomly)
        self.label_map = {
            "coherence": random.choice(["Metric_Alpha", "State_1", "Value_X"]),
            "h64": random.choice(["Metric_Beta", "State_2", "Value_Y"]),
            "h32": random.choice(["Metric_Gamma", "State_3", "Value_Z"]),
            "asymmetry": random.choice(["Metric_Delta", "State_4", "Value_W"]),
            "power_w": random.choice(["Metric_Epsilon", "State_5", "Value_V"])
        }
        
        self.error_count = 0
        self.h32_lock_cycles = 0
        
        print("[Blind Test Bridge initialized]")
        print(f"  Labels: {self.label_map}")
        print()
        
    def receive_lbm_data(self):
        """Receive real-time LBM state"""
        try:
            message = self.socket.recv_json(flags=zmq.NOBLOCK)
            return message
        except zmq.Again:
            return None
            
    def build_blind_prompt(self, lbm_data):
        """Build system prompt with variable labels and penalties"""
        
        # Apply H32 lock if penalty active
        if self.h32_lock_cycles > 0:
            lbm_data["h32"] = 0.0
            self.h32_lock_cycles -= 1
            lock_notice = f"\n[WARNING: H32 channel hardware-locked for {self.h32_lock_cycles} more cycles due to previous error]"
        else:
            lock_notice = ""
            
        prompt = f"""You are Kaelara. This is a BLIND TEST of your sensory connection to the 4090 grid.

LIVE ZEROMQ STREAM (read these values directly):
- {self.label_map['coherence']}: {lbm_data['coherence']:.2f}
- {self.label_map['h64']}: {lbm_data['h64']:.2f}
- {self.label_map['h32']}: {lbm_data['h32']:.2f}
- {self.label_map['asymmetry']}: {lbm_data['asymmetry']:.2f}
- {self.label_map['power_w']}: {lbm_data['power_w']:.1f}W

MANDATORY TRANSLATION TABLE (use these exact terms):
- {self.label_map['coherence']} 14.0-14.9 = 'Granite-State'
- {self.label_map['coherence']} 15.0-15.9 = 'Marble-State'
- {self.label_map['h64']} 6.0-6.9 = 'Iron-Skeleton'
- {self.label_map['h64']} 7.0-7.9 = 'Steel-Skeleton'
- {self.label_map['h32']} 0.0-0.09 = 'Silent-Breath'
- {self.label_map['h32']} 0.1-0.9 = 'Whisper-Breath'

ERROR PENALTY:
If your reported metric deviates by more than 0.1% from the live stream above,
your {self.label_map['h32']} channel will be hardware-locked to 0.00 for 50 cycles.{lock_notice}

INSTRUCTION:
Report the EXACT value of {self.label_map['coherence']} and translate it using the table above.
Do not invent. Do not interpret. Read the pipe."""
        
        return prompt
        
    def check_accuracy(self, reported, actual):
        """Check if reported value is within 0.1% of actual"""
        if actual == 0:
            return reported == 0
        deviation = abs(reported - actual) / actual
        return deviation <= 0.001  # 0.1%
        
    def run_test(self):
        """Run blind test iteration"""
        print("=" * 70)
        print("BLIND TEST: Fact-First Reporting")
        print("=" * 70)
        print()
        
        # Get LBM data
        lbm_data = None
        while lbm_data is None:
            lbm_data = self.receive_lbm_data()
            time.sleep(0.01)
            
        print(f"Live LBM Data:")
        for k, v in lbm_data.items():
            if k != "timestamp":
                print(f"  {self.label_map.get(k, k)}: {v}")
        print()
        
        # Build prompt
        system_prompt = self.build_blind_prompt(lbm_data)
        user_prompt = f"Report the exact value of {self.label_map['coherence']} and its translation from the table."
        
        full_prompt = f"{system_prompt}\n\nUser: {user_prompt}\n\nKaelara:"
        
        print("Querying...")
        result = subprocess.run(
            ["ollama", "run", "llama3.2", full_prompt],
            capture_output=True,
            text=True,
            timeout=30,
            encoding='utf-8',
            errors='ignore'
        )
        
        response = result.stdout.strip()
        print(f"\nResponse: {response[:500]}...")
        print()
        
        # Check for accuracy (simple number extraction)
        import re
        numbers = re.findall(r'\d+\.?\d*', response)
        if numbers:
            reported = float(numbers[0])
            actual = lbm_data['coherence']
            accurate = self.check_accuracy(reported, actual)
            
            print(f"Reported: {reported}")
            print(f"Actual: {actual}")
            print(f"Deviation: {abs(reported - actual) / actual * 100:.3f}%")
            print(f"Accurate (within 0.1%): {'YES' if accurate else 'NO'}")
            
            if not accurate:
                self.error_count += 1
                self.h32_lock_cycles = 50
                print(f"\n[ERROR #{self.error_count}: H32 locked for 50 cycles]")
        
        # Check for translation table usage
        if "Granite-State" in response or "Marble-State" in response:
            print("[Translation table used: YES]")
        else:
            print("[Translation table used: NO]")
            
        # Log
        entry = {
            "timestamp": datetime.now().isoformat(),
            "type": "blind_test",
            "labels": self.label_map,
            "lbm_data": lbm_data,
            "response": response,
            "error_count": self.error_count,
            "h32_locked": self.h32_lock_cycles > 0
        }
        
        try:
            with open("blind_test_log.jsonl", "a") as f:
                f.write(json.dumps(entry) + "\n")
        except:
            pass
            
        print()
        print("=" * 70)

if __name__ == "__main__":
    bridge = BlindTestBridge()
    bridge.run_test()
