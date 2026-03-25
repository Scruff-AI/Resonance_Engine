# NVMe Hybrid System Test Plan
## Testing the Three-Tiered Memory Hierarchy on the-craw

### 🎯 **Objective:**
Test the **NVMe hybrid system** (three-tiered memory hierarchy) with the **working large grid** on the-craw server.

### 🏗️ **Three-Tiered Memory Hierarchy:**
1. **Volatile State (GPU VRAM):** Active thought at 0.06Hz cognitive cycle
2. **Buffer State (System RAM):** Metabolic damping at 0.005Hz cycle  
3. **Solid State (NVMe SSD):** Crystallized memory (sector-aligned overwrites)

### 🔧 **Current Status:**
- ✅ **256×256 grid works** on Windows/RTX 4090
- ✅ **Guardian formation works** (13 guardians with RHO_THRESH=1.00022)
- ✅ **Probe sequence defined** (A, B, C, D stress tests)
- ❌ **NVMe hybrid system NOT TESTED** yet
- ❌ **Large grid (1024×1024) NOT TESTED** on NVMe system

### 🖥️ **Target System: the-craw**
- **IP:** 192.168.1.55 / 192.168.1.63
- **OS:** Ubuntu server
- **GPU:** Likely NVIDIA (needs verification)
- **Storage:** NVMe SSD available
- **OpenClaw gateway:** Port 18789

### 🚀 **Test Strategy:**

#### Phase 1: Remote Setup
1. **Transfer working grid system** to the-craw
2. **Compile for target GPU architecture** (check with `nvidia-smi`)
3. **Set up NVMe test directory** for crystallized memory storage

#### Phase 2: NVMe Integration Test
1. **Modify code** to implement three-tiered memory:
   - GPU VRAM: Active simulation state
   - System RAM: Buffer for checkpointing
   - NVMe SSD: Long-term storage (sector-aligned writes)
2. **Test checkpoint/restore** functionality
3. **Measure performance impact** of NVMe writes

#### Phase 3: Large Grid Test
1. **Test 1024×1024 grid** (original size) on the-craw
2. **Monitor NVMe usage** during large grid operation
3. **Test crash recovery** using NVMe stored state

### 📋 **Immediate Actions:**

#### Action 1: Check the-craw Hardware
```bash
# Check GPU
ssh tiger@192.168.1.55 "nvidia-smi"

# Check NVMe storage
ssh tiger@192.168.1.55 "df -h | grep nvme"
ssh tiger@192.168.1.55 "lsblk | grep nvme"

# Check CUDA
ssh tiger@192.168.1.55 "nvcc --version"
```

#### Action 2: Transfer Files
```bash
# Copy source files to the-craw
scp probe_256.cu tiger@192.168.1.55:~/fractal_habit/
scp fractal_habit_256_full.cu tiger@192.168.1.55:~/fractal_habit/
scp add_power_limit.cu tiger@192.168.1.55:~/fractal_habit/

# Copy test scripts
scp test_256_direct.py tiger@192.168.1.55:~/fractal_habit/
scp quick_256_test.py tiger@192.168.1.55:~/fractal_habit/
```

#### Action 3: Compile on the-craw
```bash
# SSH to the-craw and compile
ssh tiger@192.168.1.55 "cd ~/fractal_habit && nvcc -O3 -arch=sm_XX -o probe_256_craw probe_256.cu -lnvml"
# Replace sm_XX with actual GPU architecture
```

#### Action 4: NVMe Test Setup
```bash
# Create NVMe test directory
ssh tiger@192.168.1.55 "mkdir -p /mnt/nvme/fractal_states"

# Set permissions
ssh tiger@192.168.1.55 "chmod 777 /mnt/nvme/fractal_states"
```

### 🔬 **NVMe Hybrid Test Scenarios:**

#### Test 1: Basic NVMe Write
- Write simulation state to NVMe every 100 cycles
- Measure write latency and throughput
- Verify data integrity on readback

#### Test 2: Crash Recovery
- Intentionally crash simulation
- Restore from NVMe checkpoint
- Verify state consistency

#### Test 3: Three-Tier Performance
- Measure performance of:
  - GPU-only (baseline)
  - GPU + RAM buffer
  - GPU + RAM + NVMe storage
- Identify bottlenecks

#### Test 4: Large Grid (1024×1024) NVMe Test
- Test if NVMe can handle large grid state (14.1MB per state)
- Measure performance impact
- Test scalability

### 📊 **Metrics to Collect:**

#### Performance Metrics:
1. **NVMe Write Speed:** MB/s for state saves
2. **Checkpoint Frequency:** How often we can save without impacting simulation
3. **Recovery Time:** Time to restore from NVMe
4. **State Size:** Size of crystallized memory per checkpoint

#### System Metrics:
1. **GPU Memory Usage:** VRAM consumption
2. **System RAM Usage:** Buffer memory
3. **NVMe I/O:** Read/write operations
4. **CPU Usage:** Overhead of memory management

#### Quality Metrics:
1. **Data Integrity:** Checksum verification
2. **State Consistency:** Compare before/after save/restore
3. **Crash Recovery Success Rate:** % of successful recoveries

### 🛠️ **Code Modifications Needed:**

#### 1. NVMe State Saver:
```c
// Add to fractal_habit code:
void save_state_to_nvme(const char* filename, SimulationState* state) {
    // Sector-aligned write to NVMe
    // Include checksum for integrity
}

void load_state_from_nvme(const char* filename, SimulationState* state) {
    // Read from NVMe
    // Verify checksum
}
```

#### 2. Three-Tier Manager:
```c
class ThreeTierMemory {
    // GPU VRAM: active state
    // System RAM: buffer (ring buffer of recent states)
    // NVMe SSD: long-term storage (every N cycles)
};
```

#### 3. Checkpoint Scheduler:
- Save to RAM buffer every X cycles
- Flush buffer to NVMe every Y cycles
- Manage storage space (oldest states first)

### ⚠️ **Potential Issues & Solutions:**

#### Issue 1: NVMe Write Latency
- **Problem:** Writing 14.1MB state may cause simulation stutter
- **Solution:** Async writes, compression, delta encoding

#### Issue 2: Storage Space
- **Problem:** 14.1MB × 1000 checkpoints = 14.1GB
- **Solution:** Circular buffer, compression, selective saving

#### Issue 3: Data Corruption
- **Problem:** Power loss during write
- **Solution:** Write-ahead logging, checksums, redundant copies

#### Issue 4: Performance Overhead
- **Problem:** Memory copying reduces simulation speed
- **Solution:** Pinned memory, DMA, optimized data layout

### 🎯 **Success Criteria:**

#### Minimum Viable:
1. ✅ State can be saved to NVMe
2. ✅ State can be restored from NVMe
3. ✅ Data integrity maintained
4. ✅ <10% performance penalty

#### Extended Goals:
1. ✅ Crash recovery works (simulation survives restart)
2. ✅ Scalable to large grid (1024×1024)
3. ✅ Efficient storage (compression, delta encoding)
4. ✅ Real-time performance (no visible stutter)

### 🕒 **Time Estimate:**
- Setup: 1 hour
- Basic NVMe test: 2 hours
- Crash recovery test: 1 hour
- Large grid test: 2 hours
- **Total:** 6 hours

### 🚨 **Critical Questions to Answer:**

1. **Does the-craw have NVMe?** (Check with `lsblk`)
2. **What GPU architecture?** (Check with `nvidia-smi`)
3. **Is there enough space?** (Check with `df -h`)
4. **Can we write to NVMe from user space?** (Permissions)

### 📞 **Next Step:**
**Run hardware check on the-craw first:**
```bash
ssh tiger@192.168.1.55 "nvidia-smi && lsblk && df -h"
```

Then we'll know exactly what we're working with and can proceed with the NVMe hybrid system test.

---
**Key Insight:** The NVMe hybrid system is the **missing piece** - we've tested computation (grid works) but not the **three-tiered memory hierarchy** that enables long-term stability and crash recovery.