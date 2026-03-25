@echo off
echo ========================================
echo COMPILING REAL FRACTAL HABIT (1024x1024)
echo ========================================
echo.

REM Set up Visual Studio environment
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling fractal_habit_1024x1024.cu...
nvcc -O3 -arch=sm_89 -o fractal_habit_real.exe fractal_habit_1024x1024.cu -lnvml -lcufft
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    echo.
    echo Checking environment...
    where nvcc
    where cl
    pause
    exit /b 1
)
echo ✓ Real fractal habit compiled successfully

echo.
echo ========================================
echo READY FOR REALITY CHECK
echo ========================================
echo.
echo This is the REAL code with:
echo 1. FFT spectral analysis
echo 2. Real entropy calculation
echo 3. Power monitoring via NVML
echo.
echo Expected: 100k steps in ~18 seconds
echo.
echo To run: fractal_habit_real.exe
echo.
pause