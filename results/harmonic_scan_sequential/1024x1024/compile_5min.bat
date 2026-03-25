@echo off
echo ========================================
echo COMPILING 5-MINUTE TEST
echo ========================================
echo.

REM Set up Visual Studio environment
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling probeB_5min.cu...
nvcc -O3 -arch=sm_89 -o probeB_5min.exe probeB_5min.cu -lnvml
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ 5-minute test compiled successfully

echo.
echo ========================================
echo READY FOR 5-MINUTE TELEMETRY
echo ========================================
echo.
echo This test will run for 5 minutes and report:
echo 1. Real-time power usage (W)
echo 2. Guardian formation count
echo 3. Steps/sec performance
echo.
echo Expected: ~5.5k steps/sec, 37W -> 290W scaling
echo Target: 13 guardians in first 5 minutes
echo.
echo To run: probeB_5min.exe
echo.
pause