@echo off
echo =========================================
echo NVMe Hybridization Test - 1024x1024 ONLY
echo =========================================
echo.
echo GOAL: Add NVMe checkpointing to working 1024x1024
echo       Nothing else. No migration. No smaller grids.
echo.
echo Current working system:
echo   - fractal_habit_1024x1024.exe (384 KB)
echo   - Last ran: Output shows 70.7% spectral power survived
echo   - Status: STABLE, working perfectly
echo.
echo What we're adding:
echo   1. GPU VRAM: Active lattice (already working)
echo   2. System RAM: Ring buffer (new)
echo   3. NVMe SSD: Checkpoint storage (new)
echo.
echo =========================================
echo.

REM Step 1: Verify working system
echo Step 1: Verifying working 1024x1024...
if exist fractal_habit_1024x1024.exe (
    echo   ✓ fractal_habit_1024x1024.exe exists
    echo   Size: %~z0 bytes
) else (
    echo   ✗ ERROR: Working executable not found
    goto error
)

REM Step 2: Create NVMe test directory
echo.
echo Step 2: Creating NVMe test directory...
if not exist C:\fractal_nvme_test (
    mkdir C:\fractal_nvme_test
    echo   ✓ Created C:\fractal_nvme_test
) else (
    echo   ✓ C:\fractal_nvme_test already exists
)

REM Step 3: Check source code for NVMe addition
echo.
echo Step 3: Checking source code...
if exist fractal_habit_1024x1024_nvme.cu (
    echo   ✓ NVMe version source exists
    for /f %%i in ('dir /b fractal_habit_1024x1024_nvme.cu ^| find /c /v ""') do set nvme_size=%%i
    echo   Size: %nvme_size% bytes
) else (
    echo   ✗ NVMe source not found
    goto error
)

REM Step 4: Compilation status
echo.
echo Step 4: Compilation status...
echo   Need to compile: fractal_habit_1024x1024_nvme.cu
echo   Command: nvcc -O3 -arch=sm_89 -o fractal_habit_nvme.exe ^
echo            fractal_habit_1024x1024_nvme.cu ^
echo            -lnvidia-ml -lpthread -lcufft
echo.
echo   PROBLEM: No Visual Studio (cl.exe) on this machine
echo   SOLUTION: Compile on the-craw (Ubuntu with CUDA)
echo             then copy binary back here

REM Step 5: Test plan
echo.
echo Step 5: Test plan for NVMe hybridization:
echo   1. Compile NVMe version (on the-craw)
echo   2. Copy binary to Beast
echo   3. Run with checkpointing enabled
echo   4. Verify checkpoints created
echo   5. Test crash recovery
echo   6. Measure performance impact
echo.
echo   ONLY testing 1024x1024
echo   NO migration testing
echo   NO smaller grids
echo   ONLY NVMe hybridization

REM Step 6: What hybridization adds
echo.
echo Step 6: What NVMe hybridization adds:
echo   - Checkpoint every 10,000 steps to NVMe
echo   - Ring buffer of 10 states in RAM
echo   - Crash recovery capability
echo   - Long-term state preservation
echo.
echo   Current system (without hybridization):
echo     - GPU VRAM only
echo     - No crash recovery
echo     - State lost on crash
echo.
echo   Hybrid system (with NVMe):
echo     - GPU VRAM + System RAM + NVMe SSD
echo     - Can recover from crashes
echo     - State preserved long-term

:success
echo.
echo =========================================
echo READY FOR NVMe HYBRIDIZATION
echo =========================================
echo Next: Compile fractal_habit_1024x1024_nvme.cu
echo       (Need to do this on the-craw)
echo =========================================
goto end

:error
echo.
echo =========================================
echo ERROR
echo =========================================
exit /b 1

:end
pause