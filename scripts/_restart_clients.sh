#!/bin/bash
kill -9 975 2>/dev/null
sleep 1
cd /mnt/d/Resonance_Engine
nohup python3 navigator/lattice_observer.py > logs/observer.log 2>&1 &
nohup python3 navigator/sentry_monitor.py > logs/sentry.log 2>&1 &
sleep 3
pgrep -a -f 'khra_gixx|lattice_observer|sentry_monitor'
tail -3 logs/observer.log
echo "---"
tail -3 logs/sentry.log