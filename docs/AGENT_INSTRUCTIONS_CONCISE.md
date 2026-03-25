# AGENT ON THE-CRAW: NVMe Hybrid System Test

## CONTEXT
You're on the-craw server (Ubuntu, NVIDIA GPU). We've developed a fractal grid system (256×256) that works on Windows/RTX 4090. Now need to test the THREE-TIERED MEMORY HIERARCHY with NVMe storage:

1. **GPU VRAM** - Active simulation (tested, works)
2. **System RAM** - Buffer for checkpointing (NOT tested)
3. **NVMe SSD** - Crystallized memory storage (NOT tested)

## YOUR MISSION
Test if we can save/restore simulation state to/from NVMe for crash recovery and long-term stability.

## IMMEDIATE TASKS

### 1. SYSTEM CHECK (First 5 min)
```bash
# Check GPU
nvidia-smi --query-gpu=name,driver_version,memory.total,compute_cap --format=csv

# Check NVMe
lsblk | grep -i nvme
df -h | grep -i nvme
findmnt -t nvme

# Check CUDA
nvcc --version 2>/dev/null || echo "No CUDA"
```

### 2. GET SOURCE FILES
Files needed from Beast (192.168.1.34):
- `probe_256.cu` - Stress test with probes A,B,C,D
- `fractal_habit_256_full.cu` - Basic fractal system
- `add_power_limit.cu` - Power control utility

Transfer method:
```bash
mkdir -p ~/fractal_test
scp tiger@192.168.1.34:D:/openclaw-local/workspace-main/probe_256.cu ~/fractal_test/
# Or use whatever works
```

### 3. COMPILE
```bash
cd ~/fractal_test
# Determine architecture from nvidia-smi output
# Common: sm_61 (GTX 10-series), sm_75 (RTX 20-series), sm_86 (RTX 30-series)
ARCH="sm_61"  # Adjust based on your GPU

nvcc -O3 -arch=$ARCH -o probe_256_craw probe_256.cu -lnvml
nvcc -O3 -arch=$ARCH -o fractal_habit_256_craw fractal_habit_256_full.cu -lnvml -lcufft
chmod +x probe_256_craw fractal_habit_256_craw
```

### 4. QUICK TEST (10 seconds)
```bash
timeout 10 ./probe_256_craw 2>&1 | head -30
```
**Look for:**
- 13 "NEW GUARDIAN" messages ✓
- Cycle counter increasing ✓
- No immediate crashes ✓

### 5. NVMe TEST SETUP
```bash
# Find or create NVMe directory
NVME_DIR="/mnt/nvme"
[ ! -d "$NVME_DIR" ] && NVME_DIR="$HOME/nvme_test"
mkdir -p "${NVME_DIR}/fractal_states"

# Test write speed
dd if=/dev/zero of="${NVME_DIR}/fractal_states/test.bin" bs=1M count=100 oflag=direct 2>&1 | tail -1
```

## WHAT TO TEST

### Test 1: Basic NVMe Checkpoint
- Save simulation state to NVMe every 100 cycles
- Verify data integrity on readback
- Measure performance impact

### Test 2: Crash Recovery
- Intentionally crash simulation
- Restore from NVMe checkpoint
- Verify state consistency

### Test 3: Three-Tier Performance
- GPU-only (baseline)
- GPU + RAM buffer
- GPU + RAM + NVMe storage
- Identify bottlenecks

## DATA TO COLLECT

### Hardware Info:
- GPU model, memory, compute capability
- NVMe model, capacity, speed
- System specs (CPU, RAM, Ubuntu version)

### Performance Metrics:
- NVMe write speed (MB/s)
- Checkpoint frequency possible
- Recovery time from NVMe
- Performance penalty percentage

### Quality Metrics:
- Data integrity (checksums)
- Recovery success rate
- State consistency

## REPORT BACK WITH

1. **System assessment** (GPU, NVMe found? CUDA working?)
2. **Basic test results** (runs? guardians form? errors?)
3. **NVMe test results** (write speed, recovery test)
4. **Issues encountered** (compilation, permissions, etc.)
5. **Recommendations** (next steps)

## EXPECTED OUTCOMES

### Best case:
- Everything works, NVMe provides reliable crash recovery
- Ready for large grid (1024×1024) testing

### Worst case:
- No NVMe found, use simulated storage
- GPU incompatible, need different compilation
- CUDA/driver issues need fixing

### Most likely:
- Basic system works, NVMe needs code modifications
- Performance impact measurable but acceptable
- Ready for optimization phase

## START NOW WITH:
```bash
echo "=== the-craw Agent Starting ==="
nvidia-smi
lsblk | grep -i nvme
mkdir -p ~/fractal_test
echo "Ready for source files and testing instructions"
```

**Proceed step by step and report each finding.** We'll adjust based on what you discover about the-craw's hardware.