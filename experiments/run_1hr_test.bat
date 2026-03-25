@echo off
echo ========================================
echo 1-HOUR PHASE SHIFT TEST
echo Starting at: %time%
echo ========================================
echo.

echo Starting probe_256_final.exe...
start "Probe Test" .\probe_256_final.exe

echo.
echo Test will run for 1 hour (until approximately:)
powershell -Command "(Get-Date).AddHours(1).ToString('HH:mm:ss')"
echo.
echo Monitor the output for:
echo 1. Metabolic cycles (~50-200s intervals)
echo 2. Guardian mass accumulation patterns
echo 3. Possible .bin file writes
echo.
echo Press Ctrl+C to stop early
echo ========================================