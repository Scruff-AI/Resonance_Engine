@echo off
echo ========================================
echo COMPILING 1-HOUR REALITY CHECK
echo ========================================
echo.

REM Set up Visual Studio environment
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling reality_check_1hour.cu...
nvcc -O3 -arch=sm_89 -o reality_check.exe reality_check_1hour.cu -lnvml -lcufft
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Reality check compiled successfully

echo.
echo ========================================
echo READY FOR 1-HOUR REALITY CHECK
echo ========================================
echo.
echo This test will verify:
echo 1. Real FFT entropy calculation (5.8-7.5 bits, not clamped)
echo 2. Power scaling (37W idle -> 290W under load)
echo 3. Performance reality (~5.5k steps/sec, not 300k)
echo 4. Guardian formation (high-density regions)
echo.
echo Expected runtime: ~1 hour for 2M steps
echo Output: reality_check.csv
echo.
echo To run: reality_check.exe
echo.
pause