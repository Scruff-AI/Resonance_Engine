@echo off
echo =========================================
echo 256x256 @ 80W TEST
echo Looking for harmonic synergy
echo =========================================

echo.
echo 1. Setting power limit to 80W...
echo {"timestamp":"2026-03-11T12:30:00.000000","command":"pl","parameters":{"watts":80},"status":"pending"} > "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain-build\gpu_clock_signal\request.json"
timeout /t 3 /nobreak > nul

echo.
echo 2. Running 256x256 (50k steps)...
cd /d "D:\openclaw-local\workspace-main\test_256x256"
fractal_habit_256x256.exe > output_80W.log

echo.
echo 3. Results:
type output_80W.log | findstr "sl= Ev= W$"

echo.
echo 4. Resetting to 150W...
echo {"timestamp":"2026-03-11T12:31:00.000000","command":"pl","parameters":{"watts":150},"status":"pending"} > "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain-build\gpu_clock_signal\request.json"
timeout /t 3 /nobreak > nul

echo.
echo =========================================
echo TEST COMPLETE
echo =========================================
pause