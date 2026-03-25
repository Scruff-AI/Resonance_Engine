# MESSAGE FOR THE-CRAW INFRASTRUCTURE ENGINEER

## CONTEXT:
- Beast has working 1024×1024 with NVMe hybridization
- Original mothballed, NVMe version tested and working
- Need to test on the-craw (GTX 1050)

## FILES AVAILABLE ON BEAST:
1. `D:\openclaw-local\workspace-main\harmonic_scan_sequential\1024x1024\fractal_habit_1024x1024_nvme_proper.cu` - NVMe source
2. `D:\openclaw-local\workspace-main\harmonic_scan_sequential\1024x1024\fractal_habit_nvme_proper.exe` - Compiled binary
3. `D:\openclaw-local\workspace-main\harmonic_scan_sequential\1024x1024\MOTHBALLED_ORIGINAL\` - Original (read-only)

## TEST INSTRUCTIONS FOR THE-CRAW:

### Step 1: Check CUDA/GPU
```bash
/usr/local/cuda/bin/nvcc --version
nvidia-smi
```

### Step 2: Copy files from Beast (if possible via node connectivity)
Or compile from source:
```bash
# Get source from Beast path above
# Compile for GTX 1050 (sm_61)
/usr/local/cuda/bin/nvcc -arch=sm_61 -O3 -D_USE_MATH_DEFINES \
    fractal_habit_1024x1024_nvme_proper.cu \
    -o fractal_habit_nvme_craw -lnvml -lcufft
```

### Step 3: Test NVMe checkpointing
```bash
mkdir -p /mnt/nvme/fractal_test  # or use /tmp
./fractal_habit_nvme_craw
# Should create checkpoint_00100000.bin at end
```

### Step 4: Report back
1. Compilation success/failure
2. Runtime behavior
3. Checkpoint file creation
4. Any errors

## BEAST STATUS:
- ✅ Original 1024×1024 working (mothballed)
- ✅ NVMe version working (checkpoint saved: 48MB)
- ✅ Three-tiered memory hierarchy implemented
- ✅ Ready for the-craw testing

## URGENCY:
Test NVMe hybridization on actual GTX 1050 hardware to verify:
1. Compilation works on different CUDA version (11.4 vs 12.6)
2. Checkpointing works on Linux/NVMe
3. Performance on lower-power GPU