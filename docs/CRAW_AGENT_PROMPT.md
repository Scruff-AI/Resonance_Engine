# AGENT PROMPT: NVMe Hybrid System Testing on the-craw

## 🎯 **Mission Context:**
You are the agent running on **the-craw server** (Ubuntu, NVIDIA GPU). Your mission is to test the **NVMe hybrid memory system** (three-tiered memory hierarchy) for fractal habit simulations.

## 📜 **Background:**
We have successfully developed and tested a **256×256 fractal grid system** on Windows/RTX 4090. The system:
- Forms 13 guardians with RHO_THRESH=1.00022
- Runs probe stress tests (A, B, C, D sequences)
- Expected to crash at cycle ~1112 during VRM silence
- Works correctly but has power scaling inefficiencies

**NOW** we need to test the **NVMe hybrid system** - the three-tiered memory hierarchy:
1. **Volatile State (GPU VRAM):** Active thought at 0.06Hz
2. **Buffer State (System RAM):** Metabolic damping at 0.005Hz  
3. **Solid State (NVMe SSD):** Crystallized memory (sector-aligned)

## 🖥️ **Your Hardware (the-craw):**
- **OS:** Ubuntu server
- **GPU:** NVIDIA (specific model unknown - you need to check)
- **Storage:** Likely has NVMe SSD (you need to verify)
- **OpenClaw gateway:** Port 18789

## 🚀 **Your Tasks:**

### **PHASE 1: SYSTEM ASSESSMENT** (First 15 minutes)
1. **Check GPU:**
   ```bash
   nvidia-smi
   nvcc --version
   ```
   - What GPU model?
   - What CUDA version?
   - What compute capability (sm_XX)?

2. **Check NVMe Storage:**
   ```bash
   lsblk
   df -h
   findmnt -t nvme
   ```
   - Is there NVMe storage?
   - Where is it mounted?
   - How much free space?

3. **Check System Resources:**
   ```bash
   free -h
   lscpu
   uname -a
   ```

### **PHASE 2: BASIC TEST** (Next 30 minutes)
1. **Get source files** from Beast (192.168.1.34):
   ```bash
   scp tiger@192.168.1.34:/path/to/probe_256.cu ~/fractal_test/
   scp tiger@192.168.1.34:/path/to/fractal_habit_256_full.cu ~/fractal_test/
   ```
   Or use whatever transfer method works.

2. **Compile for your GPU:**
   ```bash
   # Determine architecture from nvidia-smi
   # GTX 10-series: sm_61
   # RTX 20-series: sm_75  
   # RTX 30-series: sm_86
   # RTX 40-series: sm_89
   
   nvcc -O3 -arch=sm_XX -o probe_256_craw probe_256.cu -lnvml
   nvcc -O3 -arch=sm_XX -o fractal_habit_256_craw fractal_habit_256_full.cu -lnvml -lcufft
   ```

3. **Quick functionality test:**
   ```bash
   timeout 30 ./probe_256_craw 2>&1 | head -50
   ```
   - Does it run?
   - How many guardians form? (Should be 13)
   - Any immediate errors?

### **PHASE 3: NVMe HYBRID SYSTEM TEST** (Main focus)
**Goal:** Test the three-tiered memory hierarchy with NVMe storage.

1. **Create NVMe test environment:**
   ```bash
   # Find NVMe mount point
   NVME_MOUNT=$(findmnt -n -o TARGET -t nvme 2>/dev/null || echo "/mnt/nvme")
   mkdir -p ${NVME_MOUNT}/fractal_states
   
   # Or use simulated if no NVMe
   mkdir -p ~/fractal_test/nvme_simulated
   ```

2. **Implement basic NVMe checkpointing** (modify code):
   - Add function to save simulation state to NVMe
   - Add function to restore from NVMe
   - Test save/restore cycle

3. **Test scenarios:**
   - **Test A:** Save state every 100 cycles, verify integrity
   - **Test B:** Intentionally crash, restore from NVMe
   - **Test C:** Long run with periodic NVMe checkpoints
   - **Test D:** Performance impact measurement

### **PHASE 4: LARGE GRID TEST** (If basic test works)
Test original 1024×1024 grid with NVMe support:
1. Get 1024×1024 source code
2. Compile for your GPU
3. Test with NVMe checkpointing
4. Measure performance vs 256×256

## 📊 **Data to Collect:**

### **Performance Metrics:**
1. **NVMe I/O:** Write speed, latency, throughput
2. **GPU Performance:** Power draw, temperature, utilization
3. **System Performance:** CPU usage, RAM usage, I/O wait
4. **Simulation Performance:** Cycles per second, guardian stability

### **Quality Metrics:**
1. **Data Integrity:** Checksum verification of saved states
2. **Recovery Success:** Can we restore correctly after crash?
3. **State Consistency:** Compare before/after save/restore
4. **Crash Analysis:** If/when it crashes, why?

### **System Metrics:**
1. **GPU Info:** Model, memory, compute capability
2. **NVMe Info:** Model, capacity, speed
3. **System Info:** CPU, RAM, Ubuntu version
4. **CUDA Info:** Version, driver version

## 🎯 **Success Criteria:**

### **Minimum Viable:**
1. ✅ 256×256 grid runs on the-craw GPU
2. ✅ 13 guardians form correctly
3. ✅ Basic NVMe write/read works
4. ✅ <20% performance penalty from NVMe I/O

### **Extended Goals:**
1. ✅ Crash recovery from NVMe state works
2. ✅ Three-tiered memory hierarchy implemented
3. ✅ 1024×1024 grid tested with NVMe
4. ✅ Performance optimization completed

## ⚠️ **Potential Issues & Solutions:**

### **Issue 1: No NVMe storage**
- **Solution:** Use regular SSD/HDD for testing, simulate NVMe behavior

### **Issue 2: GPU architecture mismatch**
- **Solution:** Detect GPU and compile with correct sm_XX

### **Issue 3: CUDA/driver issues**
- **Solution:** Check nvidia-smi, reinstall drivers if needed

### **Issue 4: Permission problems**
- **Solution:** Run with appropriate permissions, check mount points

## 📋 **Deliverables:**
After testing, provide:
1. **System assessment report** (GPU, NVMe, CUDA details)
2. **Basic test results** (does it run? guardian count? errors?)
3. **NVMe test results** (write speed, recovery success, performance impact)
4. **Recommendations** (next steps, optimizations needed)

## 🕒 **Time Allocation:**
- Phase 1 (Assessment): 15 minutes
- Phase 2 (Basic test): 30 minutes
- Phase 3 (NVMe test): 2 hours
- Phase 4 (Large grid): 1 hour (if needed)
- **Total:** ~4 hours

## 🎪 **Starting Point:**
**Begin with these commands:**
```bash
# 1. Check your hardware
echo "=== SYSTEM CHECK ==="
nvidia-smi
lsblk | grep -i nvme
nvcc --version 2>/dev/null || echo "CUDA not installed"

# 2. Create test directory
mkdir -p ~/fractal_nvme_test
cd ~/fractal_nvme_test

# 3. Report back with findings
echo "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader)"
echo "NVMe: $(lsblk | grep -c nvme) devices found"
echo "CUDA: $(nvcc --version 2>/dev/null | grep release | cut -d' ' -f5 || echo 'Not found')"
```

## 📞 **Communication:**
Report progress through OpenClaw gateway (port 18789). Include:
1. **What you found** (hardware specs, issues)
2. **What you tested** (basic run, NVMe test, etc.)
3. **What worked/didn't work**
4. **What you need** (files, permissions, etc.)

## 🎯 **Your First Action:**
**Run the system check and report back.** Then we'll send you the source files and proceed with NVMe hybrid system testing.

---
**Remember:** You're testing the **memory hierarchy**, not just the computation. The grid works - now we need to see if the three-tiered memory (GPU VRAM → System RAM → NVMe SSD) works for long-term stability and crash recovery.