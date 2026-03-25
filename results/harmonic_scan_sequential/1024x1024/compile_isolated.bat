@echo off
echo ========================================
echo COMPILING ISOLATED TEST
echo ========================================
echo.

REM Set up Visual Studio environment
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling probeB_isolated.cu...
nvcc -O3 -arch=sm_89 -o probeB_isolated.exe probeB_isolated.cu -lnvml
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Isolated test compiled successfully

echo.
echo ========================================
echo READY FOR ISOLATED TEST
echo ========================================
echo.
echo This test runs with:
echo 1. NO OpenClaw interference (gateway stopped)
echo 2. Fixed guardian tracking (threshold: 1.05)
echo 3. Optimized memory (cudaMalloc not Managed)
echo 4. Reduced guardian check overhead (every 50k steps)
echo.
echo Expected: ~5.5k steps/sec, 37W -> 290W scaling
echo Target: ~13 guardians in 5 minutes
echo.
echo To run: probeB_isolated.exe
echo.
pause