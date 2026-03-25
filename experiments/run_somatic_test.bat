@echo off
echo ========================================
echo 1-HOUR SOMATIC MEMORY VALIDATION TEST
echo ========================================
echo.

call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Compiling somatic_memory_1hr_test.cu...
echo Testing Scar Tissue Metaphor: Ghost Metric
echo.

nvcc -O3 -arch=sm_89 -o somatic_test.exe somatic_memory_1hr_test.cu -lnvml
if %errorlevel% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)
echo ✓ Compiled successfully

echo.
echo ========================================
echo STARTING 1-HOUR VALIDATION TEST
echo ========================================
echo.
echo Hypothesis: Somatic memory exists if:
echo   - Correlation(A, C) < 0.95 (structural difference)
echo   - Despite same entropy (macroscopic similarity)
echo   - Precipitation rate changes (elevated vigilance)
echo.
echo Test Phases:
echo   0-15min: Baseline (Microstate A)
echo   15-30min: Stress application
echo   30-45min: Recovery
echo   45-60min: Post-stress (Microstate C)
echo.
echo Starting at: %time%
echo.

somatic_test.exe
echo.
echo Test completed at: %time%
echo Results saved: somatic_memory_1hr_results.txt
pause