#!/bin/bash
# Compile khra_gixx_1024_v5 — Golden-Weave integration
# Same deps as v4: zmq + nvml, no json-c, no cufft
export PATH=/usr/local/cuda-12.6/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "Compiling khra_gixx_1024_v5..."
nvcc -O3 -arch=sm_89 \
    -o build/khra_gixx_1024_v5 \
    cuda/khra_gixx_1024_v5.cu \
    -lzmq -lnvidia-ml

if [ $? -eq 0 ]; then
    echo "BUILD OK: build/khra_gixx_1024_v5 ($(date))"
    ls -la build/khra_gixx_1024_v5
else
    echo "BUILD FAILED"
    exit 1
fi
