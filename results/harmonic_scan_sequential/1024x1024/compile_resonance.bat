@echo off
echo ========================================
echo COMPILING RESONANCE TRACKER
echo ========================================
echo.

REM Set up Visual Studio environment
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling resonance_tracker.cu...
nvcc -O3 -arch=sm_89 -o resonance_tracker.exe resonance_tracker.cu -lnvml
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Resonance tracker compiled successfully

echo.
echo ========================================
echo READY FOR RESONANCE METRICS
echo ========================================
echo.
echo RESONANCE DEFINITION:
echo  LTP (Long-Term Potentiation): Connection gets stronger with use
echo  Metrics: Lifetime, Coherence, Growth Rate, Stability
echo  Threshold: |ω| > 0.0000001, Min Lifetime: 10000 steps
echo.
echo To run: resonance_tracker.exe
echo.
pause