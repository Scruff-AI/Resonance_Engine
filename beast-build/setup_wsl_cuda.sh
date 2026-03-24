#!/bin/bash
# WSL2 CUDA + Dependencies Setup for LBM Daemon
# Run inside WSL: bash /mnt/d/fractal-brain/beast-build/setup_wsl_cuda.sh
set -e

echo "=== WSL2 CUDA SETUP FOR LBM DAEMON ==="
echo ""

# Step 1: CUDA repo pin
echo "[1/5] Setting up CUDA repository..."
wget -q https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-wsl-ubuntu.pin -O /tmp/cuda-wsl-ubuntu.pin
sudo mv /tmp/cuda-wsl-ubuntu.pin /etc/apt/preferences.d/cuda-repository-pin-600

# Step 2: Add CUDA keyring (network repo - simpler than .deb for WSL)
wget -q https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-keyring_1.1-1_all.deb -O /tmp/cuda-keyring.deb
sudo dpkg -i /tmp/cuda-keyring.deb

# Step 3: Install CUDA toolkit + dependencies
echo "[2/5] Updating package list..."
sudo apt-get update -qq

echo "[3/5] Installing CUDA toolkit..."
sudo apt-get install -y cuda-toolkit-12-6

echo "[4/5] Installing ZeroMQ and json-c..."
sudo apt-get install -y libzmq3-dev libjson-c-dev

echo "[5/5] Setting up PATH..."
# Add CUDA to PATH for this session and permanently
export PATH=/usr/local/cuda-12.6/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH

# Make persistent
if ! grep -q "cuda-12" ~/.bashrc 2>/dev/null; then
    echo 'export PATH=/usr/local/cuda-12.6/bin:$PATH' >> ~/.bashrc
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
    echo "  Added CUDA to ~/.bashrc"
fi

echo ""
echo "=== VERIFICATION ==="
echo -n "nvcc: "; nvcc --version 2>&1 | grep "release" || echo "NOT FOUND"
echo -n "zmq: "; dpkg -l libzmq3-dev 2>/dev/null | grep -c "ii" && echo "OK" || echo "NOT FOUND"
echo -n "json-c: "; dpkg -l libjson-c-dev 2>/dev/null | grep -c "ii" && echo "OK" || echo "NOT FOUND"
echo ""
echo "=== READY TO COMPILE ==="
echo "Next: cd /mnt/d/fractal-brain/beast-build"
echo "      nvcc -o lbm_cuda_daemon lbm_cuda_daemon.cu -lzmq -ljson-c -lnvidia-ml -O3 -arch=sm_89"
