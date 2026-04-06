#!/bin/bash
# Clean restart: CUDA daemon + lattice observer (Third Wave disabled)
REPO_ROOT="/mnt/d/Resonance_Engine"
cd "$REPO_ROOT"

mkdir -p logs

echo "[RESTART] Starting khra_gixx_1024_v5 daemon..."
setsid ./beast-build/khra_gixx_1024_v5 > logs/v5_stdout.log 2> logs/v5_stderr.log < /dev/null &
DAEMON_PID=$!
disown $DAEMON_PID
echo "[RESTART] Daemon PID: $DAEMON_PID"

# Wait for ZMQ ports to bind
sleep 3

# Verify daemon is running
if kill -0 $DAEMON_PID 2>/dev/null; then
    echo "[RESTART] Daemon is running."
else
    echo "[RESTART] ERROR: Daemon failed to start. Check logs/v5_stderr.log"
    cat logs/v5_stderr.log
    exit 1
fi

echo "[RESTART] Starting lattice_observer.py..."
setsid python3 navigator/lattice_observer.py > logs/observer.log 2>&1 < /dev/null &
OBS_PID=$!
disown $OBS_PID
echo "[RESTART] Observer PID: $OBS_PID"

sleep 2

if kill -0 $OBS_PID 2>/dev/null; then
    echo "[RESTART] Observer is running."
else
    echo "[RESTART] ERROR: Observer failed to start. Check logs/observer.log"
    tail -20 logs/observer.log
    exit 1
fi

echo "[RESTART] Clean restart complete."
echo "[RESTART] Daemon PID=$DAEMON_PID, Observer PID=$OBS_PID"
echo "[RESTART] Third Wave: DISABLED (navigator/lattice_observer.py)"
