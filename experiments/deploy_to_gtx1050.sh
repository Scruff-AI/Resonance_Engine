#!/bin/bash
# Deployment script for GTX 1050 Ubuntu system
# Run this on the Ubuntu machine

set -e  # Exit on error

echo "========================================="
echo "GTX 1050 Fractal Habit Deployment"
echo "========================================="

# Configuration
TARGET_USER="user"  # Change this to your Ubuntu username
TARGET_HOST="gtx1050"  # Change this to your hostname/IP
REMOTE_DIR="~/fractal_habit"
LOCAL_SOURCE_DIR="."  # Current directory

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Step 1: Checking local files...${NC}"
echo ""

# Check for required source files
REQUIRED_FILES=("probe_256.cu" "fractal_habit_256_full.cu" "add_power_limit.cu")
MISSING_FILES=()

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓ Found: $file${NC}"
    else
        echo -e "${RED}✗ Missing: $file${NC}"
        MISSING_FILES+=("$file")
    fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    echo -e "${RED}Error: Missing required files: ${MISSING_FILES[*]}${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Step 2: Checking remote system prerequisites...${NC}"
echo ""

# Check remote system
echo "Checking remote system at ${TARGET_USER}@${TARGET_HOST}..."

# Test SSH connection
if ! ssh "${TARGET_USER}@${TARGET_HOST}" "echo 'SSH connection successful'"; then
    echo -e "${RED}Error: Cannot connect to ${TARGET_HOST}${NC}"
    exit 1
fi

# Check for required tools on remote
echo "Checking for required tools on remote system..."
if ! ssh "${TARGET_USER}@${TARGET_HOST}" "command -v nvcc >/dev/null 2>&1"; then
    echo -e "${RED}Error: nvcc (CUDA) not found on remote system${NC}"
    echo "Install CUDA toolkit first:"
    echo "  sudo apt install nvidia-cuda-toolkit"
    exit 1
fi

if ! ssh "${TARGET_USER}@${TARGET_HOST}" "command -v nvidia-smi >/dev/null 2>&1"; then
    echo -e "${RED}Error: nvidia-smi not found on remote system${NC}"
    echo "Install NVIDIA drivers first:"
    echo "  sudo apt install nvidia-driver-470"
    exit 1
fi

echo -e "${GREEN}✓ Remote system checks passed${NC}"

echo ""
echo -e "${BLUE}Step 3: Creating remote directory...${NC}"
echo ""

# Create remote directory
ssh "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${REMOTE_DIR}"

echo ""
echo -e "${BLUE}Step 4: Copying source files...${NC}"
echo ""

# Copy source files
echo "Copying source files to ${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/"
scp probe_256.cu "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/"
scp fractal_habit_256_full.cu "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/"
scp add_power_limit.cu "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/"

# Copy supporting files if they exist
SUPPORT_FILES=("compile_256.ps1" "do_it_properly.ps1" "quick_256_test.py" "test_256_direct.py")
for file in "${SUPPORT_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "Copying $file..."
        scp "$file" "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/"
    fi
done

echo ""
echo -e "${BLUE}Step 5: Compiling on remote system...${NC}"
echo ""

# Compile on remote
echo "Compiling probe_256 for GTX 1050 (sm_61)..."
ssh "${TARGET_USER}@${TARGET_HOST}" "cd ${REMOTE_DIR} && nvcc -O3 -arch=sm_61 -o probe_256_gtx1050 probe_256.cu -lnvml"

echo "Compiling fractal_habit_256 for GTX 1050 (sm_61)..."
ssh "${TARGET_USER}@${TARGET_HOST}" "cd ${REMOTE_DIR} && nvcc -O3 -arch=sm_61 -o fractal_habit_256 fractal_habit_256_full.cu -lnvml -lcufft"

echo "Compiling power limit utility..."
ssh "${TARGET_USER}@${TARGET_HOST}" "cd ${REMOTE_DIR} && nvcc -O3 -arch=sm_61 -o set_power_limit add_power_limit.cu -lnvml"

echo ""
echo -e "${BLUE}Step 6: Creating run scripts...${NC}"
echo ""

# Create run script on remote
RUN_SCRIPT=$(cat << 'EOF'
#!/bin/bash
# run_fractal.sh - Run fractal habit on GTX 1050

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "Fractal Habit GTX 1050 Runner"
echo "========================================="

# Check if executables exist
if [ ! -f "probe_256_gtx1050" ]; then
    echo "Error: probe_256_gtx1050 not found"
    echo "Run compile.sh first"
    exit 1
fi

if [ ! -f "fractal_habit_256" ]; then
    echo "Error: fractal_habit_256 not found"
    echo "Run compile.sh first"
    exit 1
fi

# Set power limit (requires sudo)
echo "Setting power limit to 60W (requires sudo)..."
sudo ./set_power_limit 60 2>/dev/null || echo "Note: Power limit may require manual setting"

# Check GPU info
echo ""
echo "GPU Information:"
nvidia-smi --query-gpu=name,driver_version,memory.total,power.limit --format=csv

echo ""
echo "Starting fractal_habit_256..."
echo "Press Ctrl+C to stop"
echo ""

# Run with basic monitoring
./fractal_habit_256
EOF
)

# Create compile script on remote
COMPILE_SCRIPT=$(cat << 'EOF'
#!/bin/bash
# compile.sh - Compile fractal habit for GTX 1050

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Compiling for GTX 1050 (sm_61 architecture)..."
echo ""

echo "1. Compiling probe_256_gtx1050..."
nvcc -O3 -arch=sm_61 -o probe_256_gtx1050 probe_256.cu -lnvml

echo "2. Compiling fractal_habit_256..."
nvcc -O3 -arch=sm_61 -o fractal_habit_256 fractal_habit_256_full.cu -lnvml -lcufft

echo "3. Compiling set_power_limit..."
nvcc -O3 -arch=sm_61 -o set_power_limit add_power_limit.cu -lnvml

echo ""
echo "Compilation complete!"
echo "Executables created:"
ls -la probe_256_gtx1050 fractal_habit_256 set_power_limit
EOF
)

# Create test script on remote
TEST_SCRIPT=$(cat << 'EOF'
#!/bin/bash
# test_gtx1050.sh - Test fractal habit on GTX 1050

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "GTX 1050 Fractal Habit Test Suite"
echo "========================================="

# Test 1: Basic compilation check
echo ""
echo "Test 1: Checking executables..."
if [ -f "probe_256_gtx1050" ] && [ -f "fractal_habit_256" ]; then
    echo "✓ Executables found"
else
    echo "✗ Executables missing - run compile.sh first"
    exit 1
fi

# Test 2: GPU check
echo ""
echo "Test 2: Checking GPU..."
if nvidia-smi >/dev/null 2>&1; then
    echo "✓ NVIDIA GPU detected"
    nvidia-smi --query-gpu=name,driver_version --format=csv
else
    echo "✗ No NVIDIA GPU detected"
    exit 1
fi

# Test 3: Architecture check
echo ""
echo "Test 3: Checking CUDA architecture..."
ARCH=$(nvcc --version | grep -o "release [0-9.]*" | cut -d' ' -f2)
echo "CUDA version: $ARCH"
echo "Target architecture: sm_61 (GTX 1050)"

# Test 4: Quick run test
echo ""
echo "Test 4: Quick functionality test..."
echo "Running fractal_habit_256 for 5 seconds..."
timeout 5 ./fractal_habit_256 2>&1 | head -20

echo ""
echo "========================================="
echo "Test suite complete!"
echo "Next: Run ./run_fractal.sh for full execution"
echo "========================================="
EOF
)

# Create monitor script on remote
MONITOR_SCRIPT=$(cat << 'EOF'
#!/bin/bash
# monitor.sh - Monitor GPU during fractal execution

echo "Monitoring GPU during fractal execution..."
echo "Press Ctrl+C to stop monitoring"
echo ""

# Header
echo "Timestamp,PowerDraw(W),Temperature(C),GPUUtil(%),MemUsed(MB),MemTotal(MB)"

# Continuous monitoring
while true; do
    TIMESTAMP=$(date +%H:%M:%S)
    GPU_STATS=$(nvidia-smi --query-gpu=power.draw,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits)
    echo "$TIMESTAMP,$GPU_STATS"
    sleep 1
done
EOF
)

# Send scripts to remote
echo "Creating run_fractal.sh..."
echo "$RUN_SCRIPT" | ssh "${TARGET_USER}@${TARGET_HOST}" "cat > ${REMOTE_DIR}/run_fractal.sh && chmod +x ${REMOTE_DIR}/run_fractal.sh"

echo "Creating compile.sh..."
echo "$COMPILE_SCRIPT" | ssh "${TARGET_USER}@${TARGET_HOST}" "cat > ${REMOTE_DIR}/compile.sh && chmod +x ${REMOTE_DIR}/compile.sh"

echo "Creating test_gtx1050.sh..."
echo "$TEST_SCRIPT" | ssh "${TARGET_USER}@${TARGET_HOST}" "cat > ${REMOTE_DIR}/test_gtx1050.sh && chmod +x ${REMOTE_DIR}/test_gtx1050.sh"

echo "Creating monitor.sh..."
echo "$MONITOR_SCRIPT" | ssh "${TARGET_USER}@${TARGET_HOST}" "cat > ${REMOTE_DIR}/monitor.sh && chmod +x ${REMOTE_DIR}/monitor.sh"

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "${YELLOW}Next steps on the GTX 1050 system:${NC}"
echo "1. SSH to the machine:"
echo "   ssh ${TARGET_USER}@${TARGET_HOST}"
echo "2. Navigate to the directory:"
echo "   cd ${REMOTE_DIR}"
echo "3. Run tests:"
echo "   ./test_gtx1050.sh"
echo "4. Run the fractal system:"
echo "   ./run_fractal.sh"
echo ""
echo -e "${BLUE}To monitor GPU during execution:${NC}"
echo "  In one terminal: ./run_fractal.sh"
echo "  In another terminal: ./monitor.sh > gpu_log.csv"
echo ""
echo -e "${GREEN}Good luck with the GTX 1050 deployment!${NC}"