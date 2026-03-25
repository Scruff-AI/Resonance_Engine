@echo off
echo ========================================
echo 30-MINUTE CONFIRMATION TEST
echo ========================================
echo.

call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Recompiling for 30-minute test...
nvcc -O3 -arch=sm_89 -o probe_1024_30min.exe probe_1024.cu -lnvml
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Compiled successfully

echo.
echo ========================================
echo STARTING 30-MINUTE CONFIRMATION TEST
echo ========================================
echo.
echo Parameters:
echo   Grid: 1024x1024 (1,048,576 nodes)
echo   Target: 194 guardians
echo   Runtime: 30 minutes (1800 seconds)
echo   Stop condition: Time OR 194 guardians
echo.
echo Output files:
echo   - Console output (guardian creation log)
echo   - beast_guardian_census_30min.json
echo   - telemetry_30min.csv (if added)
echo.
echo Starting test at: %time%
echo.

probe_1024_30min.exe
echo.
echo Test completed at: %time%
pause