#!/bin/bash
# compile_v2.sh — Build khra_gixx_1024_v2 (bidirectional + NVML)
export PATH=/usr/local/cuda-12.6/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH

cd /mnt/d/fractal-brain/beast-build

echo "=== COMPILING khra_gixx_1024_v2 ==="
echo "  PUB telemetry on 5556 | SUB commands on 5557 | NVML hardware"
echo "nvcc: $(nvcc --version 2>&1 | grep release)"
echo "Target: sm_89 (RTX 4090)"
echo ""

nvcc -o khra_gixx_1024_v2 khra_gixx_1024_v2.cu \
    -lzmq -lnvidia-ml \
    -O3 -arch=sm_89 \
    2>&1

if [ $? -eq 0 ]; then
    echo ""
    echo "=== BUILD SUCCESS ==="
    ls -la khra_gixx_1024_v2
    echo ""
    echo "To run:"
    echo "  Kill old daemon:  kill \$(pgrep -f lbm_1024)"
    echo "  Start v2:         ./khra_gixx_1024_v2"
else
    echo ""
    echo "=== BUILD FAILED ==="
    exit 1
fi
