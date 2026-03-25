@echo off
echo ========================================
echo Compiling NVMe Hybrid Version
echo ========================================
echo.

REM Set up Visual Studio environment
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

REM First, let's fix the original compilation
echo Step 1: Fixing M_PI issue in original code...
powershell -Command "(Get-Content fractal_habit_1024x1024.cu) -replace 'M_PI', '3.14159265358979323846' | Set-Content fractal_habit_1024x1024_fixed.cu"

echo Step 2: Compiling original (fixed) version...
nvcc -O3 -arch=sm_89 -o fractal_habit_original_fixed.exe fractal_habit_1024x1024_fixed.cu -lnvidia-ml -lpthread -lcufft
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    goto error
)
echo ✓ Original code compiled successfully

echo Step 3: Creating NVMe directory...
mkdir C:\fractal_nvme_test 2>nul
echo ✓ NVMe directory ready

echo Step 4: Creating simple NVMe test...
echo # Simple test to verify NVMe writes
echo # We'll create a proper NVMe version next
echo.

echo Step 5: Quick test of original code...
timeout 3 fractal_habit_original_fixed.exe
echo.

echo ========================================
echo READY FOR NVMe HYBRIDIZATION
echo ========================================
echo Next: Create proper NVMe version by adding:
echo   1. Checkpoint function
echo   2. Save every 10,000 steps
echo   3. Test crash recovery
echo ========================================
goto end

:error
echo ERROR in compilation
exit /b 1

:end
pause