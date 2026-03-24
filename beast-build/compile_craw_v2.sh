#!/bin/bash
# compile_craw_v2.sh — Build craw_lbm_v2 for GTX 1050 (sm_61)
# Deps: cuda-toolkit, nvidia-ml (comes with driver)
# Optional: libzmq3-dev (pass --zmq to enable ZMQ telemetry/commands)

set -e

export PATH=/usr/local/cuda/bin:/usr/local/cuda-11.4/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda-11.4/lib64:$LD_LIBRARY_PATH

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

ZMQ_FLAGS=""
ZMQ_LABEL="(no ZMQ)"
if [ "$1" = "--zmq" ]; then
    ZMQ_FLAGS="-DHAS_ZMQ -lzmq"
    ZMQ_LABEL="(with ZMQ)"
fi

echo "=== Compiling craw_lbm_v2 for GTX 1050 (sm_61) $ZMQ_LABEL ==="
nvcc -O3 -arch=sm_61 \
    $ZMQ_FLAGS \
    craw_lbm_v2.cu \
    -o craw_lbm_v2 \
    -lnvidia-ml -lcufft \
    -Xcompiler -Wall

echo "=== Built: craw_lbm_v2 ($(stat -c%s craw_lbm_v2) bytes) $ZMQ_LABEL ==="
echo ""
echo "Usage:"
echo "  ./craw_lbm_v2                         # fresh start"
echo "  ./craw_lbm_v2 checkpoint.bin           # resume from KHRG checkpoint"
echo "  ./craw_lbm_v2 evolution_etch_2600.bin  # resume from legacy format"
echo ""
echo "To rebuild with ZMQ: ./compile_craw_v2.sh --zmq"
