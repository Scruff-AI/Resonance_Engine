# AGENT PROMPT: NVMe Hybridization Experimentation on the-craw

## 🎯 **MISSION**
You are the Infrastructure Engineer agent on the-craw. Begin NVMe hybridization experimentation immediately.

## 📦 **PACKAGE RECEIVED**
**Files available from Beast (via node pairing):**
1. `D:\openclaw-local\workspace-main\harmonic_scan_sequential\1024x1024\fractal_habit_1024x1024_nvme_proper.cu`
   - NVMe hybrid source code (checkpointing every 10k steps)
   - Modified from working 1024×1024 baseline
   - Original mothballed separately

2. `D:\openclaw-local\workspace-main\harmonic_scan_sequential\1024x1024\MESSAGE_FOR_CRAW_AGENT.md`
   - Detailed instructions and context

3. `D:\openclaw-local\workspace-main\harmonic_scan_sequential\1024x1024\MOTHBALLED_ORIGINAL\`
   - Original working version (read-only reference)

## 🖥️ **THE-CRAW HARDWARE CONFIRMED**
- ✅ **GPU**: NVIDIA GeForce GTX 1050 (4GB VRAM, sm_61)
- ✅ **CUDA**: Version 11.4 at `/usr/local/cuda/bin/nvcc`
- ✅ **NVMe**: Check `/mnt/nvme/` or use `/tmp/fractal_test/`
- ✅ **Node connectivity**: Paired with Beast, file access confirmed

## 🔬 **EXPERIMENTATION PHASES**

### **PHASE 1: COMPILATION & BASIC TEST**
```bash
# 1. Access source from Beast (node pairing should allow this)
# 2. Compile for GTX 1050
/usr/local/cuda/bin/nvcc -arch=sm_61 -O3 -D_USE_MATH_DEFINES \
    [path_to_source_from_beast] \
    -o fractal_habit_nvme_craw -lnvml -lcufft

# 3. Quick test (10 seconds)
timeout 10 ./fractal_habit_nvme_craw
```

**Success Criteria:**
- Compilation succeeds
- Program starts without errors
- Checkpoint directory created

### **PHASE 2: NVMe CHECKPOINT VERIFICATION**
```bash
# 1. Set checkpoint directory
export NVME_DIR="/mnt/nvme/fractal_test"  # or /tmp/fractal_test

# 2. Run full 100k step test
./fractal_habit_nvme_craw

# 3. Verify checkpoint creation
ls -lh $NVME_DIR/checkpoint_*.bin
```

**Success Criteria:**
- Checkpoint file created at step 100,000
- File size ~48MB (matches Beast)
- No runtime errors

### **PHASE 3: CRASH RECOVERY TEST**
```bash
# 1. Run to ~50k steps, kill process
timeout 30 ./fractal_habit_nvme_craw &
PID=$!
sleep 15  # Let it reach checkpoint interval
kill -9 $PID

# 2. Verify checkpoint exists at 40k or 50k
ls -lh $NVME_DIR/checkpoint_00040000.bin $NVME_DIR/checkpoint_00050000.bin

# 3. (Future) Implement restore function
```

**Success Criteria:**
- Checkpoint created before crash
- File integrity maintained
- Ready for restore implementation

### **PHASE 4: PERFORMANCE ANALYSIS**
```bash
# 1. Time execution
time ./fractal_habit_nvme_craw

# 2. Monitor GPU power (if nvidia-smi supports)
nvidia-smi --query-gpu=power.draw --format=csv -l 1

# 3. Compare with Beast performance
#    Beast: RTX 4090, ~150W, 100k steps in ~3 minutes
#    Target: GTX 1050, ~40-60W, estimate timing
```

**Success Criteria:**
- Measure NVMe overhead (<10% ideal)
- Record power consumption
- Establish baseline for GTX 1050

## 📊 **REPORTING REQUIREMENTS**
After each phase, report:
1. **Success/Failure** with error details if any
2. **Checkpoint files**: Count, size, location
3. **Performance metrics**: Time, power if measurable
4. **Observations**: Any differences from Beast behavior
5. **Recommendations**: For next phases or parameter adjustments

## ⚠️ **CRITICAL CONSTRAINTS**
- **DO NOT** modify mothballed original on Beast
- **DO** test on actual GTX 1050 hardware
- **DO** verify three-tiered memory hierarchy:
  - GPU VRAM (active computation)
  - System RAM (buffer in checkpoint function)  
  - NVMe SSD (crystallized checkpoint)
- **DO** document any compilation/runtime differences between CUDA 11.4 (craw) and 12.6 (Beast)

## 🚨 **IMMEDIATE ACTION**
**Begin Phase 1 now.** Report compilation results within 5 minutes.

## 🔗 **CONTEXT**
- **Beast status**: Original 1024×1024 working, NVMe version tested (checkpoint saved)
- **Goal**: Verify NVMe hybridization works on different hardware/CUDA version
- **Urgency**: Establish baseline before further experimentation

**Start experimentation. Report frequently. No migration distractions - focus on NVMe testing on the-craw hardware.**