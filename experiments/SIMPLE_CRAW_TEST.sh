#!/bin/bash
# SIMPLE TEST for the-craw NVMe hybrid system
# Run this ON the-craw server

echo "=== NVMe Hybrid System Quick Test ==="
echo ""

# Step 1: Check system
echo "1. System Check:"
echo "---------------"
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv
echo ""
echo "Storage:"
lsblk | grep -E "(nvme|NAME)"
echo ""
echo "CUDA:"
nvcc --version 2>/dev/null || echo "CUDA not installed"

# Step 2: Create test dir
echo ""
echo "2. Setting up test directory..."
echo "-----------------------------"
mkdir -p ~/nvme_hybrid_test
cd ~/nvme_hybrid_test
mkdir -p states

# Step 3: Check for source files
echo ""
echo "3. Checking for source files..."
echo "------------------------------"
if [ -f "probe_256.cu" ]; then
    echo "✓ Found probe_256.cu"
else
    echo "✗ Missing probe_256.cu"
    echo "Copy from Beast: scp probe_256.cu tiger@192.168.1.55:~/nvme_hybrid_test/"
    exit 1
fi

if [ -f "fractal_habit_256_full.cu" ]; then
    echo "✓ Found fractal_habit_256_full.cu"
else
    echo "✗ Missing fractal_habit_256_full.cu"
    echo "Copy from Beast: scp fractal_habit_256_full.cu tiger@192.168.1.55:~/nvme_hybrid_test/"
    exit 1
fi

# Step 4: Compile
echo ""
echo "4. Compiling..."
echo "--------------"
# Try common architectures
for ARCH in "sm_61" "sm_75" "sm_86" "sm_89"; do
    echo "Trying architecture: $ARCH"
    nvcc -O3 -arch=$ARCH -o probe_test probe_256.cu -lnvml 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✓ Compiled successfully with $ARCH"
        break
    fi
done

if [ ! -f "probe_test" ]; then
    echo "✗ Compilation failed"
    echo "Trying without architecture flag..."
    nvcc -O3 -o probe_test probe_256.cu -lnvml
fi

if [ -f "probe_test" ]; then
    chmod +x probe_test
    echo "✓ Executable created: probe_test"
else
    echo "✗ Failed to create executable"
    exit 1
fi

# Step 5: Quick run test
echo ""
echo "5. Quick Test Run (10 seconds)..."
echo "--------------------------------"
echo "Starting test - will run for 10 seconds max"
echo "Look for:"
echo "  - 'NEW GUARDIAN' messages (should see 13)"
echo "  - Cycle counter increasing"
echo "  - No immediate crashes"
echo ""

timeout 10 ./probe_test 2>&1 | head -30

echo ""
echo "=== Test Complete ==="
echo ""
echo "What to report back:"
echo "1. Did it run? (Yes/No)"
echo "2. How many guardians formed?"
echo "3. Any error messages?"
echo "4. GPU power/temp from nvidia-smi"
echo ""
echo "Next steps based on result..."