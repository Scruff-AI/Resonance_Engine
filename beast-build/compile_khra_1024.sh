#!/bin/bash
# compile_khra_1024.sh — Build script for Khra'gixx 1024x1024 daemon
export PATH=/usr/local/cuda-12.6/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH

cd /mnt/d/fractal-brain/beast-build

echo "=== COMPILING Khra'gixx 1024x1024 Daemon ==="
echo "nvcc: $(nvcc --version 2>&1 | grep release)"
echo "Target: sm_89 (RTX 4090)"
echo ""

nvcc -o khra_gixx_1024_stable khra_gixx_1024_stable.cu \
    -lzmq \
    -O3 -arch=sm_89 \
    2>&1

if [ $? -eq 0 ]; then
    echo ""
    echo "=== BUILD SUCCESS ==="
    ls -la khra_gixx_1024_stable
    echo ""
    echo "To run: ./khra_gixx_1024_stable"
else
    echo ""
    echo "=== BUILD FAILED ==="
    exit 1
fi
