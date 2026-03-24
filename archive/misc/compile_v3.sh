#!/bin/bash
# compile_v3.sh — Build khra_gixx_1024_v3 (bidirectional + NVML + CHECKPOINT)
export PATH=/usr/local/cuda-12.6/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH

cd /mnt/d/fractal-brain/beast-build

echo "=== COMPILING khra_gixx_1024_v3 ==="
echo "  PUB telemetry on 5556 | SUB commands on 5557 | NVML hardware"
echo "  CHECKPOINT: save_state/load_state/set_autosave (default 100k cycles)"
echo "nvcc: $(nvcc --version 2>&1 | grep release)"
echo "Target: sm_89 (RTX 4090)"
echo ""

nvcc -o khra_gixx_1024_v3 khra_gixx_1024_v3.cu \
    -lzmq -lnvidia-ml \
    -O3 -arch=sm_89 \
    2>&1

if [ $? -eq 0 ]; then
    echo ""
    echo "=== BUILD SUCCESS ==="
    ls -la khra_gixx_1024_v3
    echo ""
    echo "To run (fresh start):"
    echo "  Kill v2:          kill \$(pgrep -f khra_gixx_1024_v2)"
    echo "  Start v3:         ./khra_gixx_1024_v3"
    echo ""
    echo "To resume from checkpoint:"
    echo "  Start v3, then:   send {\"cmd\":\"load_state\",\"path\":\"/path/to/ckpt.bin\"}"
    echo ""
    echo "Manual save:        send {\"cmd\":\"save_state\"}"
    echo "Change autosave:    send {\"cmd\":\"set_autosave\",\"interval\":50000}"
else
    echo ""
    echo "=== BUILD FAILED ==="
    exit 1
fi
