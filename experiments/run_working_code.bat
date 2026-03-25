@echo off
echo ========================================
echo RUNNING ACTUAL WORKING CODE
echo ========================================
echo.

call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling probe_256_working.cu...
echo This is the ACTUAL weekend code that produced results
echo.

nvcc -O3 -arch=sm_89 -o probe_256_working.exe probe_256_working.cu -lnvml
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Compiled successfully

echo.
echo ========================================
echo STARTING WORKING CODE TEST
echo ========================================
echo.
echo This is the EXACT code that worked on weekend:
echo - Grid: 256x256 (GTX 1050 adaptation)
echo - Target: 13 guardians
echo - Full probe tests: A,B,C,D
echo - Proper mass accretion
echo - Particle advection
echo.
echo Running for 5 minutes to confirm...
echo Starting at: %time%
echo.

probe_256_working.exe
echo.
echo Test completed at: %time%
pause