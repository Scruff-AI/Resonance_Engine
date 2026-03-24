#!/bin/bash
# Start CUDA daemon + lattice observer
cd /mnt/d/fractal-brain/beast-build

echo "[LAUNCHER] Starting khra_gixx_1024_v5 daemon..."
nohup ./khra_gixx_1024_v5 > v5_stdout.log 2> v5_stderr.log &
DAEMON_PID=$!
echo "[LAUNCHER] Daemon PID: $DAEMON_PID"

# Wait for ZMQ ports to bind
sleep 3

# Verify daemon is running
if kill -0 $DAEMON_PID 2>/dev/null; then
    echo "[LAUNCHER] Daemon is running."
else
    echo "[LAUNCHER] ERROR: Daemon failed to start. Check v5_stderr.log"
    cat v5_stderr.log
    exit 1
fi

echo "[LAUNCHER] Starting lattice_observer.py..."
exec python3 lattice_observer.py 2>&1 | tee observer.log
