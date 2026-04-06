#!/bin/bash
# A/B Test: Low Power vs High Power Physics
# Reversible configuration switcher

ZMQ_PORT=5557
API_PORT=28820

echo "======================================"
echo "A/B POWER TEST - REVERSIBLE"
echo "======================================"

# Function to send ZMQ command
send_cmd() {
    python3 -c "
import zmq
import json
ctx = zmq.Context()
sock = ctx.socket(zmq.PUSH)
sock.setsockopt(zmq.SNDTIMEO, 5000)
sock.setsockopt(zmq.LINGER, 0)
sock.connect('tcp://127.0.0.1:$ZMQ_PORT')
sock.send_string(json.dumps({'cmd': '$1', 'value': $2}))
print('Sent: $1 = $2')
"
}

# Function to get status
get_status() {
    curl -s http://127.0.0.1:$API_PORT/status 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(f\"{d['coherence']:.4f} {d['asymmetry']:.4f} {d['gpu_temp_c']} {d.get('gpu_power_w', 'N/A')}\")
except:
    print('ERROR')
"
}

case "$1" in
    low)
        echo ""
        echo "CONFIG A: LOW POWER (Study Mode)"
        echo "--------------------------------"
        echo "Khra: 0.01, Gixx: 0.002, Omega: 6.00"
        echo "Target: <50W, <50C"
        echo ""
        send_cmd "set_khra_amp" "0.01"
        sleep 0.3
        send_cmd "set_gixx_amp" "0.002"
        sleep 0.3
        send_cmd "set_omega" "6.00"
        sleep 0.3
        echo ""
        echo "Low power config applied."
        ;;
    
    high)
        echo ""
        echo "CONFIG B: HIGH POWER (Exploration Mode)"
        echo "---------------------------------------"
        echo "Khra: 0.03, Gixx: 0.008, Omega: 1.97"
        echo "Target: ~290W, ~60C"
        echo ""
        send_cmd "set_khra_amp" "0.03"
        sleep 0.3
        send_cmd "set_gixx_amp" "0.008"
        sleep 0.3
        send_cmd "set_omega" "1.97"
        sleep 0.3
        echo ""
        echo "High power config applied."
        ;;
    
    status)
        echo ""
        echo "Current Status:"
        echo "---------------"
        status=$(get_status)
        echo "  Coherence: $(echo $status | cut -d' ' -f1)"
        echo "  Asymmetry: $(echo $status | cut -d' ' -f2)"
        echo "  Temp: $(echo $status | cut -d' ' -f3)C"
        echo "  Power: $(echo $status | cut -d' ' -f4)W"
        ;;
    
    test)
        echo ""
        echo "A/B TEST SEQUENCE"
        echo "================="
        
        # Baseline
        echo ""
        echo "Step 1: Current baseline"
        bash $0 status
        
        # Switch to low power
        echo ""
        echo "Step 2: Switch to LOW POWER"
        bash $0 low
        echo "  Stabilizing for 10 seconds..."
        sleep 10
        echo "  Low power result:"
        bash $0 status
        
        # Switch back to high power
        echo ""
        echo "Step 3: Switch to HIGH POWER"
        bash $0 high
        echo "  Stabilizing for 10 seconds..."
        sleep 10
        echo "  High power result:"
        bash $0 status
        
        # Return to safe low power
        echo ""
        echo "Step 4: Return to LOW POWER (safe)"
        bash $0 low
        
        echo ""
        echo "Test complete. Compare coherence/asymmetry at both power levels."
        ;;
    
    *)
        echo "Usage: $0 {low|high|status|test}"
        echo ""
        echo "Commands:"
        echo "  low    - Set low power mode (Khra 0.01, study mode)"
        echo "  high   - Set high power mode (Khra 0.03, exploration mode)"
        echo "  status - Show current lattice status"
        echo "  test   - Run A/B comparison test"
        echo ""
        echo "All changes are reversible. Switch between modes instantly."
        ;;
esac
