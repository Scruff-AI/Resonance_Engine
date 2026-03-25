# READY FOR NODE PAIRING - the-craw NVMe Test

## 🎯 **Once the-craw is paired as a node, I can:**

### 1. **Direct Hardware Check:**
```bash
# Check GPU
nvidia-smi

# Check NVMe
lsblk | grep nvme
df -h | grep nvme

# Check CUDA
nvcc --version
```

### 2. **Automatic File Transfer:**
- Send `probe_256.cu` to the-craw
- Send `fractal_habit_256_full.cu` to the-craw  
- Send `fractal_gtx1050/` (512×512 Seed Brain) to the-craw

### 3. **Automatic Compilation:**
```bash
# Compile for the-craw's GPU architecture
ARCH=$(detect_gpu_architecture)  # sm_61, sm_75, etc.
nvcc -O3 -arch=$ARCH -o probe_256_craw probe_256.cu -lnvml
```

### 4. **Automated Testing:**
- Run 10-second quick test
- Monitor GPU power/temperature
- Test NVMe write speed
- Run full probe sequence (A,B,C,D)

### 5. **Real-time Monitoring:**
- Watch `nvidia-smi` output in real-time
- Monitor NVMe I/O
- Capture crash logs automatically

## 📋 **Test Sequence (Once Paired):**

### Phase 1: Hardware Discovery (2 minutes)
```bash
# Run on the-craw via node commands
nodes run --node the-craw "nvidia-smi; lsblk; nvcc --version"
```

### Phase 2: File Transfer (1 minute)
```bash
# Send files to the-craw
nodes run --node the-craw "mkdir -p ~/fractal_test"
# Transfer probe_256.cu, etc.
```

### Phase 3: Compilation (2 minutes)
```bash
# Compile on the-craw
nodes run --node the-craw "cd ~/fractal_test && nvcc -O3 -arch=sm_61 -o probe_test probe_256.cu -lnvml"
```

### Phase 4: Quick Test (1 minute)
```bash
# 10-second test
nodes run --node the-craw "cd ~/fractal_test && timeout 10 ./probe_test 2>&1 | head -30"
```

### Phase 5: NVMe Test (5 minutes)
```bash
# Test NVMe write speed
nodes run --node the-craw "dd if=/dev/zero of=/mnt/nvme/test.bin bs=1M count=100 oflag=direct 2>&1 | tail -1"
```

## 🎪 **Benefits of Node Pairing:**

1. **No manual SSH** - Fully automated
2. **Real-time control** - Immediate command execution
3. **Direct monitoring** - Watch GPU/NVMe in real-time
4. **Automatic logging** - All results captured automatically
5. **Easy iteration** - Quick test/modify/test cycles

## ⏳ **While You Work on Pairing:**

I'll:
1. Keep all test files ready on NAS (`Z:\nvme_hybrid_test\`)
2. Prepare test scripts
3. Document the test procedures
4. Be ready to execute as soon as pairing is complete

## 📞 **When Pairing is Ready:**

Just tell me:
1. "Node pairing complete"
2. What's the node name? (probably "the-craw" or similar)
3. Any special permissions needed?

Then I'll immediately:
1. Check the-craw's hardware
2. Transfer test files
3. Run the NVMe hybrid system test
4. Report results back here

## 🎯 **The Goal:**

Test the **three-tiered memory hierarchy** on real hardware:
1. ✅ GPU VRAM (computation - we know this works)
2. ❓ System RAM (buffer - needs testing)
3. ❓ NVMe SSD (crystallized storage - needs testing)

**Ready when you are!** Just say "pairing complete" and I'll start the automated testing.