@echo off
echo ========================================
echo COMPILING SEED BRAIN TIMED
echo ========================================
echo.

call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling seed_brain_timed.cu...
echo Using EXACT weekend parameters with GTX 1050 timing...
echo.

nvcc -O3 -arch=sm_89 -o seed_brain_timed.exe seed_brain_timed.cu -lnvml
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Compiled successfully

echo.
echo ========================================
echo READY TO RUN WEEKEND REPRODUCTION
echo ========================================
echo.
echo This reproduces the weekend experiment:
echo - Grid: 512x512 (GTX 1050 adaptation)
echo - Tau: 0.7273 (omega: 1.375)
echo - Target: 5500 steps/sec (GTX 1050 performance)
echo - Cognitive cycles: 16.67 seconds each
echo - Guardian detection every 10k steps
echo.
echo Goal: Reproduce 194 guardians with mass ~3000
echo.
echo Running for 60 seconds (test)...
echo.
seed_brain_timed.exe
pause