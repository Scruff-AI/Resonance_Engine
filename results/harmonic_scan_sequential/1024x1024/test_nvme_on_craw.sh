#!/bin/bash
# NVMe Hybridization Test for the-craw
# Run this on the-craw to test NVMe checkpointing

echo "=== NVMe Hybridization Test Suite ==="
echo "Running on: $(hostname)"
echo "Date: $(date)"
echo ""

# Step 1: Check CUDA installation
echo "1. Checking CUDA installation..."
if command -v nvcc &> /dev/null; then
    nvcc --version
    echo "✓ CUDA found"
else
    echo "✗ CUDA not found"
    exit 1
fi

# Step 2: Check NVMe mount
echo ""
echo "2. Checking NVMe storage..."
if [ -d "/mnt/nvme" ]; then
    echo "✓ NVMe mount found at /mnt/nvme"
    TEST_DIR="/mnt/nvme/fractal_test"
else
    echo "⚠ Using /tmp for testing (no NVMe mount)"
    TEST_DIR="/tmp/fractal_test"
fi

mkdir -p "$TEST_DIR"
echo "Test directory: $TEST_DIR"

# Step 3: Check for source file (would be transferred separately)
echo ""
echo "3. Looking for source files..."
SOURCE_FILE="fractal_habit_1024x1024_nvme_proper.cu"
if [ -f "$SOURCE_FILE" ]; then
    echo "✓ Source file found: $SOURCE_FILE"
    echo "  Size: $(wc -l < "$SOURCE_FILE") lines"
else
    echo "✗ Source file not found: $SOURCE_FILE"
    echo "  Note: File needs to be transferred from Beast"
    exit 1
fi

# Step 4: Compilation test
echo ""
echo "4. Compilation test..."
COMPILE_CMD="nvcc -arch=sm_61 -O3 -D_USE_MATH_DEFINES $SOURCE_FILE -o fractal_habit_nvme_craw -lnvml -lcufft"
echo "Command: $COMPILE_CMD"
$COMPILE_CMD

if [ $? -eq 0 ]; then
    echo "✓ Compilation successful"
    echo "  Binary size: $(stat -c%s fractal_habit_nvme_craw) bytes"
else
    echo "✗ Compilation failed"
    exit 1
fi

# Step 5: Quick test run
echo ""
echo "5. Quick test run (10 seconds)..."
timeout 10 ./fractal_habit_nvme_craw &
PID=$!
sleep 2
if ps -p $PID > /dev/null; then
    echo "✓ Program started successfully"
    sleep 8
    if ps -p $PID > /dev/null; then
        kill $PID
        echo "✓ Program ran for 10 seconds"
    else
        echo "⚠ Program exited early"
    fi
else
    echo "✗ Program failed to start"
    exit 1
fi

# Step 6: Check for checkpoint files
echo ""
echo "6. Checking for checkpoint files..."
CHECKPOINT_FILES=$(find "$TEST_DIR" -name "checkpoint_*.bin" 2>/dev/null | wc -l)
if [ $CHECKPOINT_FILES -gt 0 ]; then
    echo "✓ Checkpoint files found: $CHECKPOINT_FILES"
    find "$TEST_DIR" -name "checkpoint_*.bin" -exec ls -lh {} \;
else
    echo "⚠ No checkpoint files found (may need longer run)"
fi

echo ""
echo "=== Test Complete ==="
echo "Summary:"
echo "  - CUDA: $(command -v nvcc 2>/dev/null && echo 'Installed' || echo 'Missing')"
echo "  - Compilation: $( [ -f fractal_habit_nvme_craw ] && echo 'Success' || echo 'Failed' )"
echo "  - Runtime: $( [ $? -eq 0 ] && echo 'Working' || echo 'Failed' )"
echo "  - Checkpoints: $CHECKPOINT_FILES files"
echo ""
echo "Next steps:"
echo "  1. Full 100k step test"
echo "  2. Crash recovery test"
echo "  3. Performance measurement"