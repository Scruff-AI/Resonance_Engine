@echo off
echo ========================================
echo COMPILING METRICS ONLY
echo ========================================
echo.

REM Set up Visual Studio environment
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling metrics_only.cu...
nvcc -O3 -arch=sm_89 -o metrics_only.exe metrics_only.cu -lnvml
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Metrics only compiled successfully

echo.
echo ========================================
echo READY FOR METRICS COLLECTION
echo ========================================
echo.
echo PHILOSOPHY:
echo 1. NO POWER BOUNDARIES - Let data speak
echo 2. NO EARLY STOPPING - Run full experiment
echo 3. NO JUDGMENTS - Collect all metrics
echo 4. MARCH 7 FORMAT - Standardized output
echo.
echo To run: metrics_only.exe
echo.
pause