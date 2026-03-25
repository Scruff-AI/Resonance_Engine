@echo off
echo ========================================
echo COMPILING VORTEX + FFT
echo ========================================
echo.

REM Set up Visual Studio environment
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling vortex_fft.cu...
nvcc -O3 -arch=sm_89 -o vortex_fft.exe vortex_fft.cu -lnvml -lcufft
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Vortex + FFT compiled successfully

echo.
echo ========================================
echo READY FOR SPECTRAL WORK
echo ========================================
echo.
echo CONSTITUTION:
echo 1. NO GUARDIANS without vorticity measurement
echo 2. NO SUCCESS without March 7 format match
echo 3. NO REPORTING without persistence filter (275k steps)
echo 4. NO EXCUSES without 250W+ power scaling
echo.
echo Features:
echo - Vorticity calculation (central difference)
echo - FFT spectral analysis (every 20k steps)
echo - Power spectrum computation
echo - March 7 JSON format
echo.
echo Target: >250W power draw
echo.
echo To run: vortex_fft.exe
echo.
pause