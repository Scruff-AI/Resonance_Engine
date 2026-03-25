@echo off
echo ========================================
echo COMPILING SEED BRAIN SIMPLE
echo ========================================
echo.

REM Set up Visual Studio environment
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling seed_brain_simple.cu...
echo Using EXACT weekend parameters:
echo   Grid: 512x512 (GTX 1050 adaptation)
echo   Tau: 0.7273 (omega: 1.375)
echo   TDP target: 75W
echo.

nvcc -O3 -arch=sm_89 -o seed_brain_simple.exe seed_brain_simple.cu -lnvml
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Seed Brain Simple compiled successfully

echo.
echo ========================================
echo READY TO RUN WEEKEND EXPERIMENT
echo ========================================
echo.
echo This uses EXACT weekend parameters:
echo - Grid: 512x512 (not 1024x1024)
echo - Tau: 0.7273 (omega: 1.375)
echo - Dual-resonance timing (200s metabolic, 16.67s cognitive)
echo - Guardian detection with cycle tracking (C1, C2, ...)
echo - JSON output in weekend format
echo.
echo Target: Reproduce 194 guardians with mass ~3000
echo.
echo To run: seed_brain_simple.exe
echo.
pause