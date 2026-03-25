@echo off
echo Testing probe_256_opt.exe with RHO_THRESH=1.0015
echo.
.\probe_256_opt.exe > test_output.txt 2>&1
timeout /t 10 /nobreak > nul
taskkill /f /im probe_256_opt.exe > nul 2>&1
echo.
echo Output (last 20 lines):
echo ======================
tail -20 test_output.txt
echo.
echo Checking for guardians:
findstr "part |" test_output.txt | tail -5
echo.
del test_output.txt