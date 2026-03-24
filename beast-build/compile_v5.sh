#!/bin/bash
# Compile khra_gixx_1024_v5 — Golden-Weave integration
# Same deps as v4: zmq + nvml, no json-c, no cufft
export PATH=/usr/local/cuda-12.6/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH
cd /mnt/d/fractal-brain/beast-build

echo "Compiling khra_gixx_1024_v5..."
nvcc -O3 -arch=sm_89 \
    -o khra_gixx_1024_v5 \
    khra_gixx_1024_v5.cu \
    -lzmq -lnvidia-ml

if [ $? -eq 0 ]; then
    echo "BUILD OK: khra_gixx_1024_v5 ($(date))"
    ls -la khra_gixx_1024_v5
else
    echo "BUILD FAILED"
    exit 1
fi
