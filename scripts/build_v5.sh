#!/bin/bash
# Build v5 daemon script
set -e

echo "=== STEP 4: CLEAN BUILD v5 ==="

# Setup environment
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# Backup old binary
echo "Backing up old binary..."
cd /mnt/d/Resonance_Engine/beast-build
BACKUP_NAME="lbm_cuda_daemon.pre_v5.backup.$(date +%Y%m%d_%H%M%S)"
mv lbm_cuda_daemon "$BACKUP_NAME" 2>/dev/null || echo "No existing binary to backup"
echo "Backup: $BACKUP_NAME"

# Verify source
echo ""
echo "Verifying v5 source..."
ls -la /mnt/d/Resonance_Engine/cuda/khra_gixx_1024_v5.cu

# Compile
echo ""
echo "Compiling v5 (this may take 2-3 minutes)..."
cd /mnt/d/Resonance_Engine/cuda

nvcc khra_gixx_1024_v5.cu \
    -o /mnt/d/Resonance_Engine/beast-build/lbm_cuda_daemon \
    -lzmq -lnvidia-ml \
    -O3 \
    -arch=sm_89 \
    2>&1 | tee /mnt/d/Resonance_Engine/logs/v5_build.log

echo ""
echo "=== BUILD COMPLETE ==="
ls -la /mnt/d/Resonance_Engine/beast-build/lbm_cuda_daemon

echo ""
echo "Verifying binary has v5 features..."
strings /mnt/d/Resonance_Engine/beast-build/lbm_cuda_daemon | grep -i "inject_density\|v5" | head -5
