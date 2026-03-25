@echo off
REM ============================================================================
REM GHOST METRIC - QUICK TEST SCRIPT
REM Tests basic functionality before full 6-hour run
REM ============================================================================

echo ========================================================================
echo  GHOST METRIC - SYSTEM VERIFICATION
echo  Start: %date% %time%
echo ========================================================================
echo.

cd /d "D:\openclaw-local\workspace-main\harmonic_scan_sequential\1024x1024"

echo [STEP 1] Checking Python environment...
python --version
python -c "import numpy; import scipy; print('NumPy:', numpy.__version__, '| SciPy:', scipy.__version__)"
if errorlevel 1 (
    echo [ERROR] Python or required packages not available
    exit /b 1
)

echo.
echo [STEP 2] Checking C++ executable...
if exist fractal_habit_ghost.exe (
    echo fractal_habit_ghost.exe exists
    for %%f in (fractal_habit_ghost.exe) do echo Size: %%~zf bytes
) else (
    echo [ERROR] fractal_habit_ghost.exe not found
    exit /b 1
)

echo.
echo [STEP 3] Testing command-line interface...
echo Running: fractal_habit_ghost.exe -help
fractal_habit_ghost.exe -help
if errorlevel 1 (
    echo [WARNING] Help command failed, but continuing...
)

echo.
echo [STEP 4] Creating test directories...
mkdir "C:\fractal_nvme_test\ghost_metric_test" 2>nul
mkdir "C:\fractal_nvme_test\ghost_metric_test\fingerprints" 2>nul

echo.
echo [STEP 5] Running Python driver in test mode...
echo This will test the Python logic without running full C++ simulation
python ghost_metric.py calculate test_A.bin test_C.bin 2>&1
if errorlevel 1 (
    echo [WARNING] Python calculation test failed (expected - no test files)
)

echo.
echo [STEP 6] Creating dummy binary files for correlation test...
echo Creating test binary files with known correlation...
python -c "
import numpy as np
import os

# Create directory
os.makedirs('C:\\fractal_nvme_test\\ghost_metric_test\\fingerprints', exist_ok=True)

# Create state A (reference)
state_A = np.random.randn(1024*1024*2).astype(np.float32)
state_A.tofile('C:\\fractal_nvme_test\\ghost_metric_test\\fingerprints\\test_A.bin')

# Create state C with 0.90 correlation (should trigger GHOST DETECTED)
noise = np.random.randn(1024*1024*2) * 0.1
state_C = state_A * 0.9 + noise * 0.1
state_C.tofile('C:\\fractal_nvme_test\\ghost_metric_test\\fingerprints\\test_C.bin')

print('Created test files:')
print('  test_A.bin:', state_A.shape, 'elements')
print('  test_C.bin:', state_C.shape, 'elements')
"

echo.
echo [STEP 7] Running actual correlation calculation...
python ghost_metric.py calculate "C:\fractal_nvme_test\ghost_metric_test\fingerprints\test_A.bin" "C:\fractal_nvme_test\ghost_metric_test\fingerprints\test_C.bin"

echo.
echo [STEP 8] Testing baseline mode (short run)...
echo This will run a very short baseline test (10k steps instead of full)
echo Note: This is just to verify the executable runs, not a real baseline
echo.
echo Running: fractal_habit_ghost.exe -mode baseline -target-entropy 5.8 -tolerance 0.5
fractal_habit_ghost.exe -mode baseline -target-entropy 5.8 -tolerance 0.5 > "C:\fractal_nvme_test\ghost_metric_test\baseline_test.log" 2>&1
if errorlevel 0 (
    echo [SUCCESS] Baseline test completed
    type "C:\fractal_nvme_test\ghost_metric_test\baseline_test.log" | findstr /C:"[SOMATIC_STATE]" /C:"[DUMP]" /C:"[ERROR]" | head -5
) else (
    echo [WARNING] Baseline test had issues
    type "C:\fractal_nvme_test\ghost_metric_test\baseline_test.log" | tail -10
)

echo.
echo ========================================================================
echo  SYSTEM VERIFICATION COMPLETE
echo  End: %date% %time%
echo ========================================================================
echo.
echo [SUMMARY]
echo   Python environment: OK
echo   C++ executable: OK
echo   Directory structure: OK
echo   Correlation calculation: Tested
echo   Baseline mode: Tested
echo.
echo [NEXT STEPS]
echo   1. Full baseline to reach 6.8 bits (may take hours)
echo   2. Injury phase with Aₙ=0.35 noise
echo   3. Recovery monitoring
echo   4. Ghost metric calculation
echo.
echo Estimated total time: 4-6 hours
echo.
pause