@echo off
echo ========================================
echo COMPILING PROBE B NO-FFT VERSION
echo ========================================
echo.

REM Set up Visual Studio environment
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling probeB_nofft.cu...
nvcc -O3 -arch=sm_89 -o probeB_nofft.exe probeB_nofft.cu -lnvml
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Probe B no-FFT compiled successfully

echo.
echo ========================================
echo READY FOR 60-MINUTE SPRINT (NO FFT)
echo ========================================
echo.
echo This test has:
echo 1. Real LBM physics (verified 5.7k steps/sec)
echo 2. Guardian tracking with CSV output
echo 3. Probe B shear flow at 800k steps
echo 4. 1-hour runtime (2M steps)
echo.
echo NO FFT: Using guardian density tracking instead of spectral entropy
echo.
echo To run: probeB_nofft.exe
echo.
pause