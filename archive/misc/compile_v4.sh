#!/bin/bash
# Compile khra_gixx_1024_v4 — Phase 1 enhanced daemon
# Same deps as v3: zmq + nvml, no json-c, no cufft
export PATH=/usr/local/cuda-12.6/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH
cd /mnt/d/fractal-brain/beast-build

echo "Compiling khra_gixx_1024_v4..."
nvcc -O3 -arch=sm_89 \
    -o khra_gixx_1024_v4 \
    khra_gixx_1024_v4.cu \
    -lzmq -lnvidia-ml

if [ $? -eq 0 ]; then
    echo "BUILD OK: khra_gixx_1024_v4 ($(date))"
    ls -la khra_gixx_1024_v4
else
    echo "BUILD FAILED"
    exit 1
fi
