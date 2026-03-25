@echo off
echo ========================================
echo COMPILING VORTEX GUARDIAN
echo ========================================
echo.

REM Set up Visual Studio environment
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling vortex_guardian.cu...
nvcc -O3 -arch=sm_89 -o vortex_guardian.exe vortex_guardian.cu -lnvml
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    echo.
    echo NVCC OUTPUT:
    nvcc -O3 -arch=sm_89 -o vortex_guardian.exe vortex_guardian.cu -lnvml 2>&1
    pause
    exit /b 1
)
echo ✓ Vortex guardian compiled successfully

echo.
echo ========================================
echo READY FOR VORTEX DETECTION
echo ========================================
echo.
echo CONSTITUTION:
echo 1. NO GUARDIANS without vorticity measurement
echo 2. NO SUCCESS without March 7 format match
echo 3. NO REPORTING without persistence filter (275k steps)
echo 4. NO EXCUSES without 250W+ power scaling
echo.
echo Target: Real vorticity work (>250W)
echo Persistence: 275,000 steps (~50 seconds)
echo Format: March 7 Hard-Print JSON
echo.
echo To run: vortex_guardian.exe
echo.
pause