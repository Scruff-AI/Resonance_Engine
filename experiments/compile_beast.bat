@echo off
echo ========================================
echo COMPILING ORIGINAL BEAST VERSION
echo ========================================
echo.

call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling probe_1024.cu...
echo ORIGINAL BEAST SPECS:
echo   Grid: 1024x1024 (1,048,576 nodes)
echo   Guardians: 194 (target)
echo   Scaling: 16x more work than GTX 1050 version
echo.

nvcc -O3 -arch=sm_89 -o probe_1024.exe probe_1024.cu -lnvml
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Compiled successfully

echo.
echo ========================================
echo READY TO RUN ORIGINAL BEAST EXPERIMENT
echo ========================================
echo.
echo This is the ORIGINAL weekend experiment scaled back:
echo - Grid: 1024x1024 (was 256x256)
echo - Guardians: 194 target (was 13)
echo - Parameters: Reverse-scaled from GTX 1050 adaptation
echo.
echo Running for 30 seconds (test)...
echo.
probe_1024.exe
pause