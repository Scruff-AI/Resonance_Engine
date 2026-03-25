@echo off
echo ========================================
echo COMPILING VORTEX DIAGNOSTIC
echo ========================================
echo.

REM Set up Visual Studio environment
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling vortex_diagnostic.cu...
nvcc -O3 -arch=sm_89 -o vortex_diagnostic.exe vortex_diagnostic.cu
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Vortex diagnostic compiled successfully

echo.
echo ========================================
echo READY FOR VORTICITY CALIBRATION
echo ========================================
echo.
echo This will:
echo 1. Run 10k LBM steps
echo 2. Compute vorticity map
echo 3. Analyze distribution
echo 4. Recommend threshold for ~194 guardians
echo.
echo To run: vortex_diagnostic.exe
echo.
pause