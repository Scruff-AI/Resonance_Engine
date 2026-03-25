@echo off
echo ========================================
echo OBSERVER MODE - Guardian Birth Watch
echo ========================================
echo.

call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling probe_1024_proper.cu...
echo OBSERVER MODE: Watching for first PULSE state transition
echo.

nvcc -O3 -arch=sm_89 -o probe_1024_observer.exe probe_1024_proper.cu -lnvml
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Compiled successfully

echo.
echo ========================================
echo STARTING OBSERVER MODE
echo ========================================
echo.
echo Watching for:
echo   1. Density threshold break (ρ > 1.00022)
echo   2. First guardian precipitation
echo   3. PULSE state transition
echo   4. Mass accretion start
echo.
echo Will stop after observing first 3 guardians.
echo.
echo Starting at: %time%
echo.

probe_1024_observer.exe
echo.
echo Observation completed at: %time%
pause