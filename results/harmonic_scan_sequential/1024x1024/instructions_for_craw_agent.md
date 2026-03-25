# NVMe Hybridization Test Suite - For the-craw Agent

## CONTEXT:
- **Beast**: Working 1024×1024 with NVMe hybridization added
- **Original mothballed**: Safe in MOTHBALLED_ORIGINAL/
- **NVMe version working**: Checkpoint saved to C:\fractal_nvme_test\checkpoint_00100000.bin (48MB)

## TEST SUITE CONTENTS:
1. `fractal_habit_1024x1024_nvme_proper.cu` - NVMe hybrid source code
2. `fractal_habit_nvme_proper.exe` - Compiled NVMe hybrid binary
3. `MOTHBALLED_ORIGINAL/` - Original working version (DO NOT MODIFY)

## WHAT TO TEST ON THE-CRAW:

### Test 1: Compilation Test
```bash
# Compile the NVMe version on the-craw
nvcc -arch=sm_61 -O3 -D_USE_MATH_DEFINES fractal_habit_1024x1024_nvme_proper.cu -o fractal_habit_nvme_craw.exe -lnvml -lcufft
```

### Test 2: NVMe Checkpoint Test
```bash
# Create NVMe directory
mkdir -p /mnt/nvme/fractal_test

# Run test (should save checkpoint at 100,000 steps)
./fractal_habit_nvme_craw.exe
```

### Test 3: Crash Recovery Test
```bash
# Run to 50,000 steps, kill process
timeout 30 ./fractal_habit_nvme_craw.exe &
PID=$!
sleep 15  # Let it reach ~50,000 steps
kill -9 $PID

# Verify checkpoint exists
ls -lh /mnt/nvme/fractal_test/checkpoint_00050000.bin
```

### Test 4: Performance Comparison
```bash
# Time original vs NVMe version
time ./fractal_habit_original.exe  # If you have original
time ./fractal_habit_nvme_craw.exe
```

## EXPECTED RESULTS:
1. **Compilation success** on the-craw (GTX 1050, sm_61)
2. **NVMe checkpoint creation** at /mnt/nvme/fractal_test/
3. **Crash recovery possible** from checkpoint
4. **Performance overhead** < 10% for checkpointing

## REPORT BACK:
1. Compilation success/failure
2. Checkpoint file size and location
3. Crash recovery test results
4. Performance measurements

## IMPORTANT:
- **DO NOT** modify mothballed original
- **DO** test on actual GTX 1050 hardware
- **DO** measure power usage if possible
- **REPORT** any compilation errors or runtime issues