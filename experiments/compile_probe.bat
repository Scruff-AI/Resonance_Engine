@echo off
echo ========================================
echo COMPILING PROBE 256 (Working Beast Code)
echo ========================================
echo.

call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling probe_256.cu...
echo This is the ACTUAL working code from weekend experiments
echo.

nvcc -O3 -arch=sm_89 -o probe_256.exe probe_256.cu -lnvml
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Compiled successfully

echo.
echo ========================================
echo READY TO RUN WORKING BEAST CODE
echo ========================================
echo.
echo This is the ACTUAL weekend experiment code:
echo - Grid: 256x256 (GTX 1050 adapted from 1024x1024)
echo - Target: 13 guardians (scaled from 194)
echo - Probes: A,B,C,D stress tests
echo - Precipitation: Density threshold 1.00022
echo.
echo Running for 30 seconds...
echo.
probe_256.exe
pause