@echo off
REM ============================================================================
REM METABOLIC PULSES PROTOCOL v1.2 - CORRECTED
REM Fixed directory creation and error handling
REM ============================================================================

echo ========================================================================
echo  METABOLIC PULSES PROTOCOL v1.2 - CORRECTED
echo  Start: %date% %time%
echo ========================================================================
echo.

REM Create protocol directory with simple timestamp
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set datetime=%datetime:~0,14%
set PROTOCOL_DIR=C:\fractal_nvme_test\metabolic_pulses_%datetime%
mkdir "%PROTOCOL_DIR%" 2>nul
mkdir "%PROTOCOL_DIR%\cycles" 2>nul

if not exist "%PROTOCOL_DIR%" (
    echo ERROR: Could not create protocol directory
    echo Using fallback directory
    set PROTOCOL_DIR=C:\fractal_nvme_test\metabolic_pulses_fallback
    mkdir "%PROTOCOL_DIR%" 2>nul
)

cd /d "D:\openclaw-local\workspace-main\harmonic_scan_sequential\1024x1024"

echo [PROTOCOL] Directory: %PROTOCOL_DIR%
echo [PROTOCOL] Starting test cycle...
echo.

REM Run a single test cycle to verify everything works
echo [TEST] Running fractal_habit_1M_test.exe...
fractal_habit_1M_test.exe > "%PROTOCOL_DIR%\test_cycle.log" 2>&1

if %errorlevel% equ 0 (
    echo [TEST] SUCCESS - Program executed successfully
    echo [TEST] Check %PROTOCOL_DIR%\test_cycle.log for results
) else (
    echo [TEST] FAILED - Error code: %errorlevel%
    echo [TEST] Check %PROTOCOL_DIR%\test_cycle.log for error details
)

echo.
echo ========================================================================
echo  TEST COMPLETE
echo  End: %date% %time%
echo ========================================================================
echo.
pause
