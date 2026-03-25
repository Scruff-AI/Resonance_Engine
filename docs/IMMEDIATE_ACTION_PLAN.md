# IMMEDIATE ACTION PLAN
## What to Do RIGHT NOW on GTX 1050

### ✅ **What We Know Works:**
1. **256×256 grid** - Compiled and tested
2. **13 guardians** - Form with RHO_THRESH=1.00022
3. **Probe sequence** - A, B, C, D defined
4. **Power target** - 40-60W sustainable on GTX 1050

### 🚀 **STEP 1: Quick Test (5 minutes)**
```bash
# On GTX 1050 Ubuntu system:
cd ~/fractal_habit  # or wherever you put the files

# Set power limit to 60W (GTX 1050 can handle this)
sudo nvidia-smi -pl 60

# Run a quick test
./probe_256_gtx1050  # or whichever 256 executable you have
```

**Watch for:**
- Do 13 guardians form? (Should see "NEW GUARDIAN" messages)
- Does it run without crashing?
- What's the power draw? (run `nvidia-smi` in another terminal)

### 🔬 **STEP 2: If Step 1 Works (15 minutes)**
Run the FULL probe sequence and capture the crash at cycle ~1112:

```bash
# Run with output logging
./probe_256_gtx1050 2>&1 | tee probe_run_$(date +%Y%m%d_%H%M%S).log

# Monitor GPU in another terminal:
watch -n 1 nvidia-smi
```

**What to look for:**
1. **Cycle 600-649:** Probe A (mass injection) - should see "INJ" in probe column
2. **Cycle 800:** Probe B (shear rotation) - instantaneous
3. **Cycle 1100-1199:** Probe C (VRM silence) - **THIS IS WHERE IT CRASHES**
4. **Cycle 1400-1499:** Probe D (vacuum trap)

### 📊 **STEP 3: Data Collection**
If it crashes at ~1112 (as expected), collect:
1. **Error messages** from the crash
2. **Last few cycles** before crash
3. **GPU status** at time of crash (temperature, power, memory)

### 🛠️ **STEP 4: If It Doesn't Crash**
If it runs past 1112 without crashing:
1. **Celebrate!** The system is more stable than expected
2. **Continue running** to see if it crashes later
3. **Monitor** for any other issues

### ⚡ **ALTERNATIVE: Quick Power Test**
If you want to test power scaling first:
```bash
# Test different power limits
for power in 40 50 60 75; do
    echo "Testing at ${power}W..."
    sudo nvidia-smi -pl $power
    timeout 30 ./fractal_habit_256  # Run for 30 seconds
    echo "Power draw: $(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits)W"
done
```

### 🎯 **MINIMUM VIABLE CHECK:**
Just answer these questions:
1. **Does it run?** (Yes/No)
2. **Do guardians form?** (How many?)
3. **What power does it draw?** (Watts)
4. **Does it crash?** (If yes, at what cycle?)

### 📋 **WHAT YOU SHOULD SEE:**
Based on Windows/RTX 4090 testing:
- **First output:** "NEW GUARDIAN" messages (13 of them)
- **Cycles 0-599:** Warmup, guardian formation
- **Cycles 600-649:** "INJ" in probe column (mass injection)
- **Stable operation** until cycle ~1112
- **Expected crash** during VRM silence (omega locked to 1.25)

### 🆘 **IF IT DOESN'T WORK AT ALL:**
1. **Check CUDA:** `nvcc --version` (should show CUDA installed)
2. **Check GPU:** `nvidia-smi` (should show GTX 1050)
3. **Check compilation:** Recompile with `nvcc -O3 -arch=sm_61 -o probe_256 probe_256.cu -lnvml`
4. **Check permissions:** `chmod +x probe_256`

### 🎪 **BOTTOM LINE:**
**Run this command and tell me what happens:**
```bash
sudo nvidia-smi -pl 60 && ./probe_256_gtx1050
```

The forensic audit showed the system works. Now we need to see if it works **on the actual target hardware** (GTX 1050) with **actual power constraints** (60W).

**Report back with:**
1. Does it run?
2. How many guardians form?
3. What's the power draw?
4. Does it crash? If yes, when?

That's all we need to know for the next step.