# MANUAL NVMe Hybrid Test Instructions
## Run these commands ON the-craw server

Since remote SSH seems to have issues, here are the exact commands to run **directly on the-craw** to test the NVMe hybrid system.

### 🎯 **Goal:** Test the three-tiered memory hierarchy with working large grid

### 📋 **Prerequisites Check (Run on the-craw):**
```bash
# 1. Check GPU
nvidia-smi

# 2. Check NVMe storage
lsblk | grep -i nvme
df -h | grep -i nvme

# 3. Check CUDA
nvcc --version

# 4. Check system
uname -a
free -h
```

### 🚀 **Step 1: Create Test Directory**
```bash
# Create directory for NVMe test
mkdir -p ~/fractal_nvme_test
cd ~/fractal_nvme_test
mkdir -p nvme_states
```

### 📦 **Step 2: Get Source Files**
You need these files from Beast:
1. `probe_256.cu`
2. `fractal_habit_256_full.cu` 
3. `add_power_limit.cu`

**Copy them manually or use SCP from Beast:**
```bash
# FROM Beast, run:
scp probe_256.cu tiger@192.168.1.55:~/fractal_nvme_test/
scp fractal_habit_256_full.cu tiger@192.168.1.55:~/fractal_nvme_test/
scp add_power_limit.cu tiger@192.168.1.55:~/fractal_nvme_test/
```

### 🔧 **Step 3: Compile on the-craw**
```bash
cd ~/fractal_nvme_test

# Detect GPU architecture first
GPU_ARCH="sm_61"  # Default for GTX 1050/1060
# If you have RTX card, use sm_75 for 20-series, sm_86 for 30-series

# Compile
nvcc -O3 -arch=$GPU_ARCH -o probe_256_nvme probe_256.cu -lnvml
nvcc -O3 -arch=$GPU_ARCH -o fractal_habit_256_nvme fractal_habit_256_full.cu -lnvml -lcufft
nvcc -O3 -arch=$GPU_ARCH -o set_power_limit add_power_limit.cu -lnvml

# Make executable
chmod +x probe_256_nvme fractal_habit_256_nvme set_power_limit
```

### 🔬 **Step 4: Quick NVMe Test**
```bash
cd ~/fractal_nvme_test

# Test 1: Check if we can write to NVMe
NVME_PATH="/mnt/nvme"
if [ ! -d "$NVME_PATH" ]; then
    # Try to find NVMe
    NVME_DEVICE=$(lsblk -o NAME,TYPE,MOUNTPOINT | grep 'nvme.*disk' | head -1)
    if [ -n "$NVME_DEVICE" ]; then
        echo "Found NVMe: $NVME_DEVICE"
        # Use home directory if not mounted
        NVME_PATH="~/nvme_test"
        mkdir -p "$NVME_PATH"
    else
        echo "No NVMe found, using local directory"
        NVME_PATH="./nvme_states"
    fi
fi

echo "Using storage: $NVME_PATH/fractal_states"
mkdir -p "$NVME_PATH/fractal_states"

# Test write speed
echo "Testing write speed..."
time dd if=/dev/zero of="$NVME_PATH/fractal_states/test.bin" bs=1M count=100 oflag=direct
```

### 🎪 **Step 5: Run the Actual Test**
```bash
cd ~/fractal_nvme_test

# Monitor GPU in background (in separate terminal)
# Terminal 1:
watch -n 1 nvidia-smi

# Terminal 2: Run the test
./probe_256_nvme 2>&1 | tee nvme_test_output.log
```

### 📊 **Step 6: What to Look For**

#### Expected Output:
1. **First:** 13 "NEW GUARDIAN" messages
2. **Cycles 0-599:** Warmup, guardian formation
3. **Cycles 600-649:** "INJ" in probe column (mass injection)
4. **Cycle 800:** Probe B (shear rotation)
5. **Cycles 1100-1199:** Probe C (VRM silence) - **EXPECTED CRASH HERE**
6. **If no crash:** Continue to Probe D (1400-1499)

#### Critical Metrics:
1. **Power draw:** Should be reasonable for your GPU
2. **Temperature:** Should stay below 80°C
3. **Memory usage:** Should stay within GPU VRAM
4. **Crash point:** Note the exact cycle if it crashes

### 🛠️ **Step 7: If It Works (No Crash)**
If it runs past 1112 without crashing:
```bash
# Let it run longer
./probe_256_nvme 2>&1 | tee long_run.log

# Or test with power limits
sudo nvidia-smi -pl 100  # Set power limit (adjust for your GPU)
./fractal_habit_256_nvme
```

### 📝 **Step 8: Report Back**
Tell me:
1. **GPU model:** (from `nvidia-smi`)
2. **NVMe status:** (found/not found, path)
3. **Test result:** (ran/crashed/errors)
4. **If crashed:** At what cycle? Error message?
5. **Power/temp:** What were the readings?
6. **Guardian count:** How many formed?

### ⚡ **Quick Test Script**
Save this as `quick_test.sh` on the-craw:
```bash
#!/bin/bash
cd ~/fractal_nvme_test
echo "Starting NVMe hybrid test..."
echo "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader)"
echo "Time: $(date)"
echo ""
./probe_256_nvme 2>&1 | head -100
```

### 🆘 **Troubleshooting:**

#### If compilation fails:
```bash
# Check CUDA
nvcc --version

# Check libraries
ldconfig -p | grep nvml

# Try different architecture
nvcc -O3 -arch=sm_75 -o probe_256_nvme probe_256.cu -lnvml
```

#### If no NVMe found:
```bash
# Check storage
lsblk
sudo fdisk -l

# Use regular SSD/HDD for test
mkdir -p ~/fractal_states
# Update code to use this path
```

#### If permission issues:
```bash
# Check file permissions
ls -la probe_256_nvme
chmod +x probe_256_nvme

# Check write permissions
touch ~/fractal_nvme_test/test.txt
```

### 🎯 **The Core Question:**
**Does the three-tiered memory hierarchy work with NVMe storage?**

We know the grid works. We know guardians form. Now we need to test if:
1. State can be saved to NVMe (crystallized memory)
2. System can recover from NVMe state
3. Performance is acceptable with NVMe writes

### 📞 **Next Action:**
**Run the quick test on the-craw and tell me what happens:**

```bash
cd ~/fractal_nvme_test
./probe_256_nvme 2>&1 | head -50
```

Just those 50 lines will tell us:
- If it compiles and runs
- How many guardians form  
- What the initial power draw is
- If there are any immediate errors

**That's all we need to start.** Then we can implement the actual NVMe checkpointing based on the results.