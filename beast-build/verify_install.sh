#!/bin/bash
export PATH=/usr/local/cuda-12.6/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH

echo "=== VERIFY INSTALL ==="
echo -n "nvcc: "
nvcc --version 2>&1 | grep "release" || echo "NOT FOUND"
echo ""
echo -n "zmq: "
dpkg -l libzmq3-dev 2>/dev/null | grep "^ii" | awk '{print $2, $3}' || echo "NOT FOUND"
echo -n "json-c: "
dpkg -l libjson-c-dev 2>/dev/null | grep "^ii" | awk '{print $2, $3}' || echo "NOT FOUND"
echo -n "nvml-dev: "
dpkg -l cuda-nvml-dev-12-6 2>/dev/null | grep "^ii" | awk '{print $2, $3}' || echo "NOT FOUND"

# Add to bashrc if not already
if ! grep -q "cuda-12" ~/.bashrc 2>/dev/null; then
    echo 'export PATH=/usr/local/cuda-12.6/bin:$PATH' >> ~/.bashrc
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
    echo "Added CUDA to .bashrc"
else
    echo "CUDA already in .bashrc"
fi

echo ""
echo "=== READY ==="
