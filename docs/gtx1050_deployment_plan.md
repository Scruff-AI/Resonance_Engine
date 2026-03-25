# GTX 1050 Deployment & Testing Plan

## 🎯 **Target Hardware:**
- **OS:** Ubuntu 24.04 LTS
- **CPU:** Intel i7-7700HQ @ 2.80GHz (4 cores, 8 threads)
- **RAM:** 32GB
- **GPU:** NVIDIA GTX 1050 4GB (nvidia-driver-470)
- **Disk:** 937GB NVMe (~87GB used, ~803GB free / 10%)

## 📦 **What We Know Works:**
1. **256×256 grid** - Compiled and tested on Windows/RTX 4090
2. **Guardian formation** - 13 guardians with RHO_THRESH=1.00022
3. **Probe sequence** - A, B, C, D stress tests defined
4. **Power scaling** - ~37W on RTX 4090 (expect ~40-60W on GTX 1050)

## 🚀 **Deployment Steps:**

### Phase 1: Environment Setup (Ubuntu)
```bash
# 1. Verify CUDA installation
nvidia-smi
nvcc --version

# 2. Install required libraries
sudo apt-get update
sudo apt-get install -y build-essential libnvml-dev

# 3. Verify GPU architecture support
# GTX 1050 = Pascal = sm_61
```

### Phase 2: Transfer & Compile
```bash
# 1. Copy source files to Ubuntu
scp probe_256.cu user@gtx1050:~/fractal/
scp fractal_habit_256_full.cu user@gtx1050:~/fractal/

# 2. Compile on target hardware
cd ~/fractal
nvcc -O3 -arch=sm_61 -o probe_256_gtx1050 probe_256.cu -lnvml
nvcc -O3 -arch=sm_61 -o fractal_habit_256 fractal_habit_256_full.cu -lnvml -lcufft
```

### Phase 3: Initial Test
```bash
# 1. Test basic execution
./fractal_habit_256

# 2. Check power usage
sudo nvidia-smi -pl 60  # Set power limit to 60W
./probe_256_gtx1050

# 3. Monitor with nvidia-smi
watch -n 1 nvidia-smi
```

## 🔬 **Testing Protocol:**

### Test 1: Basic Functionality
- Run `fractal_habit_256` for 100k steps
- Verify: Guardian formation (13 guardians)
- Monitor: Power draw, temperature, stability

### Test 2: Power Limiting
```bash
# Test different power limits
sudo nvidia-smi -pl 40  # Minimum sustainable
sudo nvidia-smi -pl 50  # Balanced
sudo nvidia-smi -pl 60  # Performance
sudo nvidia-smi -pl 75  # Max (default)
```

### Test 3: Full Probe Sequence
- Run `probe_256_gtx1050` with monitoring
- Focus on crash at cycle ~1112 (Probe C - VRM Silence)
- Collect complete data for all probe phases

### Test 4: Long-term Stability
- Run for extended period (10,000+ cycles)
- Monitor for memory leaks, GPU errors
- Check thermal throttling

## 📊 **Data Collection:**

### Essential Metrics:
1. **Power:** Watts (nvidia-smi)
2. **Temperature:** GPU core temp
3. **Performance:** Cycles per second
4. **Stability:** Guardian count, omega values
5. **Memory:** GPU memory usage

### Monitoring Script:
```bash
#!/bin/bash
# monitor_gtx1050.sh
while true; do
    nvidia-smi --query-gpu=power.draw,temperature.gpu,utilization.gpu,memory.used --format=csv
    sleep 1
done
```

## ⚠️ **Potential Issues & Solutions:**

### Issue 1: CUDA Compatibility
- **Check:** GTX 1050 = sm_61 architecture
- **Fix:** Compile with `-arch=sm_61`

### Issue 2: Power Limiting
- **Check:** GTX 1050 power limits (40-75W)
- **Fix:** Use `nvidia-smi -pl` to set limits

### Issue 3: Memory Constraints
- **Check:** 4GB VRAM usage
- **Fix:** Monitor with `nvidia-smi --query-gpu=memory.used`

### Issue 4: Thermal Throttling
- **Check:** Temperature > 80°C
- **Fix:** Improve cooling, reduce power limit

## 🎯 **Success Criteria:**

### Minimum Viable Product:
1. ✅ 256×256 grid runs on GTX 1050
2. ✅ 13 guardians form and persist
3. ✅ Power draw < 60W sustained
4. ✅ Temperature < 80°C
5. ✅ No crashes in first 1000 cycles

### Extended Goals:
1. ✅ Complete probe sequence (A-D) without crash
2. ✅ Stable operation for 10,000+ cycles
3. ✅ Power efficiency optimization
4. ✅ Documentation of performance characteristics

## 📋 **Immediate Action Items:**

1. **Transfer files** to Ubuntu system
2. **Compile** with correct architecture (sm_61)
3. **Set power limit** to 60W for testing
4. **Run basic test** - verify guardian formation
5. **Execute full probe sequence** - monitor for crash at cycle ~1112

## 🕒 **Time Estimate:**
- Setup: 30 minutes
- Compilation: 10 minutes
- Basic test: 15 minutes
- Full probe sequence: 30-60 minutes
- **Total:** 1.5-2 hours

## 🎪 **Next Steps After Successful Deployment:**

1. **Performance optimization** - tune parameters for GTX 1050
2. **Extended testing** - 24-hour stability run
3. **Documentation** - create GTX 1050 performance profile
4. **Scaling tests** - try 384×384 if 256×256 is stable
5. **Application development** - build on stable foundation

---
**Key Insight:** The forensic audit showed the system works correctly but has power scaling inefficiencies. On GTX 1050, we're targeting the actual hardware constraints (40-60W), so these "inefficiencies" may actually be acceptable or even optimal for this hardware class.