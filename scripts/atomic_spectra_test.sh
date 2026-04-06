#!/bin/bash
# Atomic Emission Spectra Test
# Check if lattice mode energy ratios match hydrogen Balmer/Lyman series
# Run at low power (already established)

ZMQ_PORT=5557
API_PORT=28820

echo "======================================"
echo "ATOMIC EMISSION SPECTRA TEST"
echo "Hydrogen Balmer/Lyman Series Check"
echo "======================================"
echo "Low power mode: Khra 0.01, Omega 6.00"
echo ""

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
" 2>/dev/null
}

# Function to get telemetry
get_telemetry() {
    curl -s http://127.0.0.1:$API_PORT/telemetry 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(f\"{d['coherence']:.6f} {d['asymmetry']:.6f} {d['omega']} {d.get('khra_amp', 0)} {d.get('gixx_amp', 0)}\")
except:
    print('ERROR')
"
}

# Hydrogen energy levels: E_n = -13.6/n² eV
# Transitions: ΔE = 13.6(1/n₁² - 1/n₂²)
# Ratios we look for:
# Lyman-α (2→1): ΔE = 10.2 eV, ratio = 3/4 = 0.75
# Balmer-α (3→2): ΔE = 1.89 eV, ratio = 5/36 = 0.139
# Paschen-α (4→3): ΔE = 0.66 eV, ratio = 7/144 = 0.0486

echo "Hydrogen Transition Energy Ratios:"
echo "  Lyman-α (2→1):  3/4   = 0.7500"
echo "  Balmer-α (3→2): 5/36  = 0.1389"
echo "  Paschen-α (4→3):7/144 = 0.0486"
echo ""

# Sweep omega (energy proxy) and measure coherence response
echo "Sweeping omega (energy proxy)..."
echo "--------------------------------"

omega_values=(6.0 5.5 5.0 4.5 4.0 3.5 3.0 2.5 2.0)
results=()

for omega in "${omega_values[@]}"; do
    send_cmd "set_omega" "$omega"
    sleep 3
    
    tel=$(get_telemetry)
    if [ "$tel" != "ERROR" ]; then
        coh=$(echo $tel | cut -d' ' -f1)
        asym=$(echo $tel | cut -d' ' -f2)
        echo "  Omega $omega: Coh=$coh, Asym=$asym"
        results+=("$omega $coh $asym")
    fi
done

echo ""
echo "Analyzing energy ratios..."
echo "--------------------------"

# Calculate coherence differences (energy analog)
# Check if ratios match hydrogen transitions

if [ ${#results[@]} -ge 3 ]; then
    # Get first, middle, last for ratio check
    first=(${results[0]})
    mid=(${results[${#results[@]}/2]})
    last=(${results[-1]})
    
    coh1=${first[1]}
    coh2=${mid[1]}
    coh3=${last[1]}
    
    # Calculate ratios
    ratio1=$(echo "scale=6; $coh2 / $coh1" | bc 2>/dev/null || echo "N/A")
    ratio2=$(echo "scale=6; $coh3 / $coh2" | bc 2>/dev/null || echo "N/A")
    
    echo "  Coherence ratio (mid/first): $ratio1"
    echo "  Coherence ratio (last/mid):  $ratio2"
    echo ""
    
    # Compare to hydrogen
    echo "Comparison to hydrogen:"
    echo "  Lyman-α target: 0.7500"
    echo "  Balmer-α target: 0.1389"
    echo ""
    
    # Check if any ratio matches
    if [ "$ratio1" != "N/A" ]; then
        diff_lyman=$(echo "scale=6; $ratio1 - 0.75" | bc | tr -d '-')
        diff_balmer=$(echo "scale=6; $ratio1 - 0.1389" | bc | tr -d '-')
        
        if (( $(echo "$diff_lyman < 0.1" | bc -l) )); then
            echo "  ✓ MATCH: Ratio $ratio1 ≈ Lyman-α (diff: $diff_lyman)"
        elif (( $(echo "$diff_balmer < 0.05" | bc -l) )); then
            echo "  ✓ MATCH: Ratio $ratio1 ≈ Balmer-α (diff: $diff_balmer)"
        else
            echo "  ✗ No match to hydrogen series"
        fi
    fi
fi

echo ""
echo "======================================"
echo "TEST COMPLETE"
echo "======================================"
echo ""
echo "Interpretation:"
echo "  If coherence ratios match hydrogen energy ratios,"
echo "  the lattice quantizes energy like an atom."
echo ""
echo "  Current finding: Coherence changes with omega,"
echo "  but direct hydrogen correlation requires further analysis."

# Return to safe low power
send_cmd "set_omega" "6.00"
