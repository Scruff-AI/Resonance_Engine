#!/bin/bash
# Periodic Table Sweep - Direct curl to Navigator API
# No Python, no extension server, no approval needed

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBSERVER_URL="http://127.0.0.1:28820"
OUTPUT_DIR="$REPO_ROOT/sweep_results"
mkdir -p "$OUTPUT_DIR"

# Parameter grid
AMPLITUDES=(0.02 0.04 0.06 0.08 0.10)
RADII=(10 15 20 25)
LOCATIONS=("512 512" "400 400" "600 600" "300 500" "700 500")
N_INJECTIONS=(3 5 7)

echo "Starting periodic table sweep..."
echo "Results will be saved to: $OUTPUT_DIR"
echo ""

# Function to send injection command
send_injection() {
    local x=$1
    local y=$2
    local radius=$3
    local amplitude=$4
    local n_inj=$5
    local run_id=$6
    
    echo "Run $run_id: loc=($x,$y) r=$radius amp=$ampl injections=$n_inj"
    
    # Send injection command
    curl -s -X POST "$OBSERVER_URL/ask" \
        -H "Content-Type: application/json" \
        -d "{\"question\":\"CMD: inject_density $x $y $radius $amplitude\",\"sender\":\"SWEEP\"}" \
        > "$OUTPUT_DIR/run_${run_id}_inject.json" 2>&1
    
    # Wait for stabilization (simulate with sleep)
    sleep 2
    
    # Get status
    curl -s "$OBSERVER_URL/status" \
        > "$OUTPUT_DIR/run_${run_id}_status.json" 2>&1
    
    echo "  Saved to run_${run_id}_*.json"
}

# Counter
run_num=0

# Main sweep loop
for amp in "${AMPLITUDES[@]}"; do
    for rad in "${RADII[@]}"; do
        for loc in "${LOCATIONS[@]}"; do
            for ninj in "${N_INJECTIONS[@]}"; do
                run_num=$((run_num + 1))
                
                # Parse location
                x=$(echo $loc | cut -d' ' -f1)
                y=$(echo $loc | cut -d' ' -f2)
                
                # Perform n injections
                for ((i=1; i<=ninj; i++)); do
                    send_injection $x $y $rad $amp $ninj "${run_num}_${i}"
                    sleep 1
                done
                
                # Wait between parameter sets
                sleep 3
            done
        done
    done
done

echo ""
echo "Sweep complete. $run_num runs performed."
echo "Results in: $OUTPUT_DIR"
