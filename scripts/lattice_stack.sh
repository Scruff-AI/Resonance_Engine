#!/bin/bash
# Lattice Stack Control — Start/stop the khra_gixx daemon and observer

DAEMON_DIR="/mnt/d/Resonance_Engine/beast-build"
DAEMON_BIN="$DAEMON_DIR/khra_gixx_1024_v6"
OBSERVER_SCRIPT="$DAEMON_DIR/lattice_observer.py"

function is_running() {
    pgrep -f "khra_gixx_1024_v[56]" > /dev/null
}

function get_daemon_pid() {
    pgrep -f "khra_gixx_1024_v[56]" | head -1
}

function get_observer_pid() {
    pgrep -f "lattice_observer.py" | head -1
}

case "$1" in
    start)
        if is_running; then
            echo "Lattice daemon already running (PID: $(get_daemon_pid))"
            exit 1
        fi
        echo "Starting lattice daemon..."
        cd "$DAEMON_DIR"
        nohup "$DAEMON_BIN" > /tmp/khra_daemon.log 2>&1 &
        sleep 2
        if is_running; then
            echo "Daemon started (PID: $(get_daemon_pid))"
        else
            echo "Failed to start daemon"
            exit 1
        fi
        ;;
    
    stop)
        if ! is_running; then
            echo "Lattice daemon not running"
            exit 1
        fi
        echo "Stopping lattice daemon..."
        pkill -f "khra_gixx_1024_v[56]"
        pkill -f "lattice_observer.py"
        sleep 1
        if is_running; then
            echo "Force killing..."
            pkill -9 -f "khra_gixx_1024_v[56]"
        fi
        echo "Stopped."
        ;;
    
    status)
        if is_running; then
            PID=$(get_daemon_pid)
            POWER=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1)
            echo "Lattice daemon: RUNNING (PID: $PID)"
            echo "GPU Power: ${POWER}W"
            curl -s http://127.0.0.1:28820/status | python3 -m json.tool 2>/dev/null || echo "Observer API not responding"
        else
            echo "Lattice daemon: STOPPED"
        fi
        ;;
    
    lowpower)
        echo "Setting lattice to low-power mode..."
        python3 "$DAEMON_DIR/lattice_ctl.py" kill
        ;;
    
    *)
        echo "Usage: $0 {start|stop|status|lowpower}"
        echo ""
        echo "Commands:"
        echo "  start     — Start the lattice daemon"
        echo "  stop      — Stop the lattice daemon"
        echo "  status    — Check status and GPU power"
        echo "  lowpower  — Set to low-power mode (zero amplitudes, max damping)"
        exit 1
        ;;
esac
