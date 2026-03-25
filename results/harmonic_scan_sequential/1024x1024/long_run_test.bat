@echo off
REM ============================================================================
REM LONG RUN TEST - Simple and focused
REM Just run multiple 1M step tests back-to-back to verify stability
REM ============================================================================

echo ========================================================================
echo   LONG RUN TEST - Verifying stability over extended period
echo   Started: %date% %time%
echo ========================================================================
echo.

cd /d "D:\openclaw-local\workspace-main\harmonic_scan_sequential\1024x1024"

set LOG_DIR=C:\fractal_nvme_test\long_run_%date:~-4%%date:~3,2%%date:~0,2%
mkdir "%LOG_DIR%" 2>nul

echo Running 3 x 1M step tests (~10 minutes total)...
echo Logs: %LOG_DIR%
echo.

for %%i in (1 2 3) do (
    echo [Run %%i/3] Starting at %time%
    echo [Run %%i/3] %date% %time% > "%LOG_DIR%\run_%%i.log"
    fractal_habit_1M_test.exe >> "%LOG_DIR%\run_%%i.log" 2>&1
    echo [Run %%i/3] Completed at %time%
    echo.
)

echo ========================================================================
echo   LONG RUN COMPLETE
echo ========================================================================
echo.

REM Extract key metrics
echo Results Summary:
echo.
for %%i in (1 2 3) do (
    echo Run %%i:
    type "%LOG_DIR%\run_%%i.log" | findstr /C:"Entropy:" | tail -1
    type "%LOG_DIR%\run_%%i.log" | findstr /C:"Runtime:" | tail -1
    echo.
)

echo Crystal files: C:\fractal_nvme_test\1M_test\
echo Logs: %LOG_DIR%
echo.
echo Next: Test crash recovery by loading a crystal file
pause