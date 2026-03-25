@echo off
echo ========================================
echo COMPILING SIMPLE REALITY CHECK
echo ========================================
echo.

REM Set up Visual Studio environment
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling simple_reality_check.cu...
nvcc -O3 -arch=sm_89 -o simple_reality_check.exe simple_reality_check.cu -lnvml
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Simple reality check compiled successfully

echo.
echo ========================================
echo READY FOR SIMPLE REALITY CHECK
echo ========================================
echo.
echo This test will verify:
echo 1. Basic LBM physics works
echo 2. Actual steps/sec (target: ~5.5k)
echo 3. Power scaling (37W -> 290W)
echo.
echo Expected runtime: ~15 minutes for 500k steps
echo Output: simple_reality_check.csv
echo.
echo To run: simple_reality_check.exe
echo.
pause