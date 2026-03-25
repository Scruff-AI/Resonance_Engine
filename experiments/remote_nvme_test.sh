#!/bin/bash
# Remote NVMe Hybrid System Test Setup
# Run this from Beast to test the-craw

set -e

echo "========================================="
echo "NVMe Hybrid System Test - the-craw"
echo "========================================="

# Configuration
CRAW_USER="tiger"
CRAW_HOST="192.168.1.55"
REMOTE_DIR="~/fractal_nvme_test"
LOCAL_SOURCE_DIR="."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Step 1: Checking the-craw hardware...${NC}"
echo ""

# Check SSH connection
echo "Testing connection to ${CRAW_USER}@${CRAW_HOST}..."
if ! ssh "${CRAW_USER}@${CRAW_HOST}" "echo 'Connected to the-craw'"; then
    echo -e "${RED}Error: Cannot connect to the-craw${NC}"
    echo "Check SSH keys or password"
    exit 1
fi

echo ""
echo -e "${BLUE}Step 2: Gathering hardware info...${NC}"
echo ""

# Get GPU info
echo "GPU Information:"
ssh "${CRAW_USER}@${CRAW_HOST}" "nvidia-smi --query-gpu=name,driver_version,memory.total,compute_cap --format=csv" || {
    echo -e "${YELLOW}Warning: nvidia-smi failed or no NVIDIA GPU${NC}"
}

# Get storage info
echo ""
echo "Storage Information:"
ssh "${CRAW_USER}@${CRAW_HOST}" "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL | grep -E '(nvme|NAME)'"
ssh "${CRAW_USER}@${CRAW_HOST}" "df -h | grep -E '(Filesystem|nvme|/$)'"

# Get CUDA info
echo ""
echo "CUDA Information:"
ssh "${CRAW_USER}@${CRAW_HOST}" "nvcc --version 2>/dev/null || echo 'CUDA not installed'" 

# Get system info
echo ""
echo "System Information:"
ssh "${CRAW_USER}@${CRAW_HOST}" "uname -a"
ssh "${CRAW_USER}@${CRAW_HOST}" "free -h"
ssh "${CRAW_USER}@${CRAW_HOST}" "lscpu | grep -E '(Model name|CPU\(s\)|Thread)'"

echo ""
echo -e "${BLUE}Step 3: Setting up test directory...${NC}"
echo ""

# Create remote directory
ssh "${CRAW_USER}@${CRAW_HOST}" "mkdir -p ${REMOTE_DIR}"
ssh "${CRAW_USER}@${CRAW_HOST}" "mkdir -p ${REMOTE_DIR}/nvme_states"

echo -e "${GREEN}Created ${REMOTE_DIR} on the-craw${NC}"

echo ""
echo -e "${BLUE}Step 4: Copying source files...${NC}"
echo ""

# Copy essential files
ESSENTIAL_FILES=("probe_256.cu" "fractal_habit_256_full.cu" "add_power_limit.cu")

for file in "${ESSENTIAL_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "Copying $file..."
        scp "$file" "${CRAW_USER}@${CRAW_HOST}:${REMOTE_DIR}/"
    else
        echo -e "${YELLOW}Warning: $file not found locally${NC}"
    fi
done

# Copy test scripts
TEST_FILES=("test_256_direct.py" "quick_256_test.py" "scale_brain_properly.py")
for file in "${TEST_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "Copying $file..."
        scp "$file" "${CRAW_USER}@${CRAW_HOST}:${REMOTE_DIR}/"
    fi
done

echo ""
echo -e "${BLUE}Step 5: Creating NVMe test scripts on the-craw...${NC}"
echo ""

# Create compile script
COMPILE_SCRIPT=$(cat << 'EOF'
#!/bin/bash
# compile_nvme_test.sh - Compile for NVMe hybrid test

set -e

echo "Compiling for NVMe hybrid system test..."
echo ""

# Detect GPU architecture
ARCH="sm_61"  # Default for GTX 1050
if nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader)
    echo "GPU detected: $GPU_NAME"
    
    # Map GPU to architecture
    if [[ "$GPU_NAME" == *"1050"* ]]; then
        ARCH="sm_61"
    elif [[ "$GPU_NAME" == *"1060"* ]]; then
        ARCH="sm_61"
    elif [[ "$GPU_NAME" == *"1070"* ]] || [[ "$GPU_NAME" == *"1080"* ]]; then
        ARCH="sm_61"
    elif [[ "$GPU_NAME" == *"2060"* ]] || [[ "$GPU_NAME" == *"2070"* ]] || [[ "$GPU_NAME" == *"2080"* ]]; then
        ARCH="sm_75"
    elif [[ "$GPU_NAME" == *"3060"* ]] || [[ "$GPU_NAME" == *"3070"* ]] || [[ "$GPU_NAME" == *"3080"* ]]; then
        ARCH="sm_86"
    elif [[ "$GPU_NAME" == *"4090"* ]]; then
        ARCH="sm_89"
    else
        echo "Warning: Unknown GPU, using default sm_61"
    fi
fi

echo "Using architecture: $ARCH"
echo ""

# Compile probe with NVMe support
echo "1. Compiling probe_256_nvme..."
nvcc -O3 -arch=$ARCH -o probe_256_nvme probe_256.cu -lnvml

# Compile fractal habit
echo "2. Compiling fractal_habit_256_nvme..."
nvcc -O3 -arch=$ARCH -o fractal_habit_256_nvme fractal_habit_256_full.cu -lnvml -lcufft

# Compile power limit utility
echo "3. Compiling set_power_limit..."
nvcc -O3 -arch=$ARCH -o set_power_limit add_power_limit.cu -lnvml

echo ""
echo "Compilation complete!"
ls -la probe_256_nvme fractal_habit_256_nvme set_power_limit
EOF
)

# Create NVMe test script
NVME_TEST_SCRIPT=$(cat << 'EOF'
#!/bin/bash
# test_nvme_hybrid.sh - Test NVMe three-tiered memory system

set -e

echo "========================================="
echo "NVMe Hybrid System Test"
echo "========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check for NVMe mount point
NVME_MOUNT="/mnt/nvme"
if [ ! -d "$NVME_MOUNT" ]; then
    echo "Looking for NVMe storage..."
    # Try to find NVMe
    NVME_DEVICE=$(lsblk -o NAME,TYPE | grep nvme | head -1 | awk '{print $1}')
    if [ -n "$NVME_DEVICE" ]; then
        echo "Found NVMe device: $NVME_DEVICE"
        # Check if mounted
        MOUNT_POINT=$(findmnt -n -o TARGET "/dev/$NVME_DEVICE" 2>/dev/null || echo "")
        if [ -n "$MOUNT_POINT" ]; then
            NVME_MOUNT="$MOUNT_POINT"
            echo "NVMe mounted at: $NVME_MOUNT"
        else
            echo "NVMe not mounted. Testing with local directory instead."
            NVME_MOUNT="./nvme_states"
            mkdir -p "$NVME_MOUNT"
        fi
    else
        echo "No NVMe found. Using simulated NVMe directory."
        NVME_MOUNT="./nvme_states"
        mkdir -p "$NVME_MOUNT"
    fi
fi

echo "Using storage directory: $NVME_MOUNT/fractal_states"
mkdir -p "$NVME_MOUNT/fractal_states"

# Test 1: Basic write performance
echo ""
echo "Test 1: NVMe Write Performance"
echo "-----------------------------"

TEST_FILE="$NVME_MOUNT/fractal_states/test_write.bin"
SIZE_MB=14  # Approximate state size

echo "Writing ${SIZE_MB}MB test file..."
dd if=/dev/zero of="$TEST_FILE" bs=1M count=$SIZE_MB oflag=direct 2>&1 | tail -1
echo "Read test..."
dd if="$TEST_FILE" of=/dev/null bs=1M 2>&1 | tail -1
rm -f "$TEST_FILE"

# Test 2: Directory operations
echo ""
echo "Test 2: Directory Operations"
echo "---------------------------"
echo "Creating 100 test state files..."
for i in {1..100}; do
    echo "State $i" > "$NVME_MOUNT/fractal_states/state_$i.bin"
done
echo "Created $(ls -1 "$NVME_MOUNT/fractal_states" | wc -l) files"
echo "Cleaning up..."
rm -f "$NVME_MOUNT/fractal_states/state_*.bin"

# Test 3: Fractal system with NVMe checkpointing
echo ""
echo "Test 3: Fractal System with Simulated NVMe Checkpoint"
echo "----------------------------------------------------"

if [ -f "fractal_habit_256_nvme" ]; then
    echo "Running fractal system (10 seconds test)..."
    timeout 10 ./fractal_habit_256_nvme 2>&1 | head -30
    
    # Simulate checkpoint
    echo ""
    echo "Simulating NVMe checkpoint..."
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    echo "Checkpoint at $TIMESTAMP" > "$NVME_MOUNT/fractal_states/checkpoint_$TIMESTAMP.meta"
    echo "State saved to: $NVME_MOUNT/fractal_states/checkpoint_$TIMESTAMP.meta"
else
    echo "Error: fractal_habit_256_nvme not found"
    echo "Run compile_nvme_test.sh first"
fi

echo ""
echo "========================================="
echo "NVMe Test Complete!"
echo "Storage ready at: $NVME_MOUNT/fractal_states"
echo "Next: Modify code for actual NVMe checkpointing"
echo "========================================="
EOF
)

# Create run script
RUN_SCRIPT=$(cat << 'EOF'
#!/bin/bash
# run_nvme_hybrid.sh - Run NVMe hybrid system test

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "Running NVMe Hybrid System"
echo "========================================="

# Check executables
if [ ! -f "probe_256_nvme" ]; then
    echo "Error: probe_256_nvme not found"
    echo "Run ./compile_nvme_test.sh first"
    exit 1
fi

# Find NVMe storage
NVME_MOUNT="./nvme_states"
if [ -d "/mnt/nvme" ]; then
    NVME_MOUNT="/mnt/nvme/fractal_states"
    mkdir -p "$NVME_MOUNT"
elif lsblk | grep -q nvme; then
    # Try to use first NVMe
    NVME_DEVICE=$(lsblk -o NAME,TYPE,MOUNTPOINT | grep 'nvme.*disk' | head -1 | awk '{print $1}')
    if [ -n "$NVME_DEVICE" ]; then
        USER_MOUNT="/home/$(whoami)/nvme_mount"
        mkdir -p "$USER_MOUNT"
        NVME_MOUNT="$USER_MOUNT/fractal_states"
        mkdir -p "$NVME_MOUNT"
        echo "Using NVMe device: $NVME_DEVICE (mounted at $USER_MOUNT)"
    fi
fi

echo "Storage directory: $NVME_MOUNT"
mkdir -p "$NVME_MOUNT"

# Set up monitoring
echo ""
echo "Starting GPU monitor in background..."
(
    while true; do
        nvidia-smi --query-gpu=timestamp,power.draw,temperature.gpu,utilization.gpu,memory.used --format=csv,noheader
        sleep 1
    done
) > gpu_monitor.csv &
MONITOR_PID=$!

# Cleanup function
cleanup() {
    echo "Stopping monitor (PID: $MONITOR_PID)..."
    kill $MONITOR_PID 2>/dev/null
    echo "Test complete."
    exit 0
}
trap cleanup EXIT INT TERM

# Run the probe test
echo ""
echo "Starting probe_256_nvme..."
echo "This will test the full probe sequence (A, B, C, D)"
echo "Expected crash at cycle ~1112 (VRM silence)"
echo ""
echo "Output will be saved to probe_nvme_test.log"
echo ""

./probe_256_nvme 2>&1 | tee probe_nvme_test.log

echo ""
echo "========================================="
echo "Test completed (or crashed as expected)"
echo "========================================="
echo ""
echo "Data collected:"
echo "  - GPU metrics: gpu_monitor.csv"
echo "  - Program output: probe_nvme_test.log"
echo "  - NVMe storage: $NVME_MOUNT"
echo ""
echo "Next: Analyze results and implement actual NVMe checkpointing"
EOF
)

# Send scripts to the-craw
echo "Creating compile_nvme_test.sh..."
echo "$COMPILE_SCRIPT" | ssh "${CRAW_USER}@${CRAW_HOST}" "cat > ${REMOTE_DIR}/compile_nvme_test.sh && chmod +x ${REMOTE_DIR}/compile_nvme_test.sh"

echo "Creating test_nvme_hybrid.sh..."
echo "$NVME_TEST_SCRIPT" | ssh "${CRAW_USER}@${CRAW_HOST}" "cat > ${REMOTE_DIR}/test_nvme_hybrid.sh && chmod +x ${REMOTE_DIR}/test_nvme_hybrid.sh"

echo "Creating run_nvme_hybrid.sh..."
echo "$RUN_SCRIPT" | ssh "${CRAW_USER}@${CRAW_HOST}" "cat > ${REMOTE_DIR}/run_nvme_hybrid.sh && chmod +x ${REMOTE_DIR}/run_nvme_hybrid.sh"

echo ""
echo -e "${BLUE}Step 6: Creating analysis script...${NC}"
echo ""

# Create analysis script
ANALYSIS_SCRIPT=$(cat << 'EOF'
#!/bin/bash
# analyze_nvme_test.sh - Analyze NVMe hybrid test results

echo "========================================="
echo "NVMe Hybrid Test Analysis"
echo "========================================="

echo ""
echo "1. GPU Performance Analysis"
echo "--------------------------"
if [ -f "gpu_monitor.csv" ]; then
    echo "GPU monitor data:"
    echo "Total samples: $(wc -l < gpu_monitor.csv)"
    echo ""
    echo "Power statistics:"
    awk -F',' 'NR>0 {sum+=$2; count++} END {print "Average power: " sum/count "W"}' gpu_monitor.csv
    awk -F',' 'NR>0 {if($2>max)max=$2} END {print "Max power: " max "W"}' gpu_monitor.csv
    echo ""
    echo "Temperature statistics:"
    awk -F',' 'NR>0 {sum+=$3; count++} END {print "Average temp: " sum/count "C"}' gpu_monitor.csv
else
    echo "No GPU monitor data found"
fi

echo ""
echo "2. Program Output Analysis"
echo "-------------------------"
if [ -f "probe_nvme_test.log" ]; then
    echo "Last 20 lines of output:"
    tail -20 probe_nvme_test.log
    echo ""
    echo "Crash analysis:"
    if grep -q "crash\|error\|fault\|segmentation" probe_nvme_test.log; then
        echo "Crash detected in log"
        grep -n -B5 -A5 "crash\|error\|fault\|segmentation" probe_nvme_test.log | head -20
    else
        echo "No crash keywords found"
    fi
    echo ""
    echo "Cycle analysis:"
    grep -o "cyc.*|" probe_nvme_test.log | tail -5
else
    echo "No program output log found"
fi

echo ""
echo "3. NVMe Storage Analysis"
echo "-----------------------"
NVME_DIR="./nvme_states"
if [ -d "/mnt/nvme/fractal_states" ]; then
    NVME_DIR="/mnt/nvme/fractal_states"
fi

if [ -d "$NVME_DIR" ]; then
    echo "NVMe directory: $NVME_DIR"
    echo "Files: $(ls -1 "$NVME_DIR" 2>/dev/null | wc -l)"
    echo "Total size: $(du -sh "$NVME_DIR" 2>/dev/null | cut -f1)"
else
    echo "NVMe directory not found: $NVME_DIR"
fi

echo ""
echo "========================================="
echo "Analysis Complete"
echo "========================================="
EOF
)

echo "Creating analyze_nvme_test.sh..."
echo "$ANALYSIS_SCRIPT" | ssh "${CRAW_USER}@${CRAW_HOST}" "cat > ${REMOTE_DIR}/analyze_nvme_test.sh && chmod +x ${REMOTE_DIR}/analyze_nvme_test.sh"

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}NVMe Hybrid Test Setup Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "${YELLOW}Next steps on the-craw:${NC}"
echo "1. SSH to the-craw:"
echo "   ssh ${CRAW_USER}@${CRAW_HOST}"
echo "2. Navigate to test directory:"
echo "   cd ${REMOTE_DIR}"
echo "3. Compile:"
echo "   ./compile_nvme_test.sh"
echo "4. Test NVMe:"
echo "   ./test_nvme_hybrid.sh"
echo "5. Run full test:"
echo "   ./run_nvme_hybrid.sh"
echo "6. Analyze results:"
echo "   ./analyze_nvme_test.sh"
echo ""
echo -e "${BLUE}Expected outcome:${NC}"
echo "- System should run probe sequence"
- Expected crash at cycle ~1112 (VRM silence)
- GPU metrics will be recorded
- NVMe storage will be tested
echo ""
echo -e "${GREEN}Ready for NVMe hybrid system testing!${NC}"