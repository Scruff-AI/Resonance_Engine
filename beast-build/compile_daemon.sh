#!/bin/bash
export PATH=/usr/local/cuda-12.6/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH

cd /mnt/d/fractal-brain/beast-build

echo "=== COMPILING LBM CUDA DAEMON ==="
echo "nvcc: $(nvcc --version 2>&1 | grep release)"
echo "gcc: $(gcc --version 2>&1 | head -1)"
echo "Target: sm_89 (RTX 4090)"
echo ""

nvcc -o lbm_cuda_daemon lbm_cuda_daemon.cu \
    -lzmq -ljson-c -lnvidia-ml \
    -O3 -arch=sm_89 \
    2>&1

if [ $? -eq 0 ]; then
    echo ""
    echo "=== BUILD SUCCESS ==="
    ls -la lbm_cuda_daemon
    echo ""
    echo "To run: ./lbm_cuda_daemon"
else
    echo ""
    echo "=== BUILD FAILED ==="
    exit 1
fi
