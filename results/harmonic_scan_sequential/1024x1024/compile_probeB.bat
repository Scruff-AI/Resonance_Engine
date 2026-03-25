@echo off
echo ========================================
echo COMPILING PROBE B 1024x1024
echo ========================================
echo.

REM Set up Visual Studio environment
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling probeB_1024x1024.cu...
nvcc -O3 -arch=sm_89 -o probeB_1024x1024.exe probeB_1024x1024.cu -lnvml -lcufft
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    echo.
    echo Checking for linker errors...
    pause
    exit /b 1
)
echo ✓ Probe B 1024x1024 compiled successfully

echo.
echo ========================================
echo READY FOR 60-MINUTE SPRINT
echo ========================================
echo.
echo This test will:
echo 1. Run baseline physics (0-25 min)
echo 2. Apply Probe B shear at 800k steps (25-45 min)
echo 3. Monitor recovery (45-60 min)
echo 4. Track guardians with mass/position/velocity CSV
echo.
echo CONSTITUTION:
echo - If step rate > 10k, stop (FFT/LBM bypassed)
echo - If entropy = 6.81, stop (physics dead)
echo - If power < 50W, stop (GPU not working)
echo.
echo Expected: ~5.5k steps/sec, 37W -> 290W scaling
echo.
echo To run: probeB_1024x1024.exe
echo.
pause