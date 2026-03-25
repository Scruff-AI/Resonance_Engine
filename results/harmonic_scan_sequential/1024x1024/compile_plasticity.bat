@echo off
echo ========================================
echo COMPILING PLASTICITY TRACKER
echo ========================================
echo.

REM Set up Visual Studio environment
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling plasticity_tracker.cu...
nvcc -O3 -arch=sm_89 -o plasticity_tracker.exe plasticity_tracker.cu -lnvml
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Plasticity tracker compiled successfully

echo.
echo ========================================
echo READY FOR PLASTICITY METRICS
echo ========================================
echo.
echo PLASTICITY DEFINITION:
echo  Nodal Growth = Grid's ability to reshape itself
echo  Goal: Find "cooler" paths (lower resistance, more efficient)
echo  Rate: 0.001000 per adaptation cycle
echo.
echo To run: plasticity_tracker.exe
echo.
pause