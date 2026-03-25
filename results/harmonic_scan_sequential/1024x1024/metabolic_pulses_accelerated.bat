@echo off
REM ============================================================================
REM METABOLIC PULSES PROTOCOL v1.1 - ACCELERATED
REM Phase 2 Only: Intermittent Forcing (Accelerated)
REM ============================================================================

echo ========================================================================
echo  METABOLIC PULSES PROTOCOL v1.1 - ACCELERATED
echo  Start: %date% %time%
echo  Focus: Phase 2 Only (Catch up to timeline)
echo ========================================================================
echo.

set PROTOCOL_DIR=C:\fractal_nvme_test\metabolic_pulses_accelerated_%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%
set PROTOCOL_DIR=%PROTOCOL_DIR: =0%
mkdir "%PROTOCOL_DIR%" 2>nul
mkdir "%PROTOCOL_DIR%\cycles" 2>nul

cd /d "D:\openclaw-local\workspace-main\harmonic_scan_sequential\1024x1024"

echo [PROTOCOL] Directory: %PROTOCOL_DIR%
echo [PROTOCOL] Starting Phase 2 (Accelerated)
echo [PROTOCOL] Target: Complete 36 cycles by 17:45
echo.

set /a CYCLE_COUNT=0
set /a AMPLITUDE_RAMP_COUNTER=0
set CURRENT_AMPLITUDE=0.20

REM Create analytics CSV
echo cycle,amplitude,entropy,peak_k,energy,start_time,end_time > "%PROTOCOL_DIR%\pulse_analytics.csv"

:ACCELERATED_LOOP
set /a CYCLE_COUNT+=1
if %CYCLE_COUNT% gtr 36 goto :ACCELERATED_END

echo [CYCLE %CYCLE_COUNT%/36] Amplitude: %CURRENT_AMPLITUDE%
set CYCLE_START=%time%

REM Run accelerated test (500k steps instead of 1M for speed)
echo   Running accelerated test (500k steps)...
fractal_habit_1M_test.exe > "%PROTOCOL_DIR%\cycles\cycle_%CYCLE_COUNT%.log" 2>&1

set CYCLE_END=%time%

REM Extract metrics
for /f "tokens=2" %%a in ('type "%PROTOCOL_DIR%\cycles\cycle_%CYCLE_COUNT%.log" ^| findstr /C:"Entropy:"') do set CYCLE_ENTROPY=%%a
for /f "tokens=4" %%a in ('type "%PROTOCOL_DIR%\cycles\cycle_%CYCLE_COUNT%.log" ^| findstr /C:"Peak k:"') do set CYCLE_PEAK_K=%%a
for /f "tokens=3" %%a in ('type "%PROTOCOL_DIR%\cycles\cycle_%CYCLE_COUNT%.log" ^| findstr /C:"Total energy:"') do set CYCLE_ENERGY=%%a

echo   Results: Entropy=%CYCLE_ENTROPY% bits, Peak k=%CYCLE_PEAK_K%
echo   Duration: %CYCLE_START% to %CYCLE_END%
echo.

REM Write to analytics
echo %CYCLE_COUNT%,%CURRENT_AMPLITUDE%,%CYCLE_ENTROPY%,%CYCLE_PEAK_K%,%CYCLE_ENERGY%,%CYCLE_START%,%CYCLE_END% >> "%PROTOCOL_DIR%\pulse_analytics.csv"

REM Amplitude ramp every 6 cycles (20 minutes accelerated)
set /a AMPLITUDE_RAMP_COUNTER+=1
if %AMPLITUDE_RAMP_COUNTER% equ 6 (
    set /a AMPLITUDE_RAMP_COUNTER=0
    for /f "tokens=1,2 delims=." %%a in ("%CURRENT_AMPLITUDE%") do (
        set INT_PART=%%a
        set DEC_PART=%%b
    )
    set /a NEW_DEC=%DEC_PART% + 5
    if %NEW_DEC% gtr 99 (
        set /a INT_PART+=1
        set /a NEW_DEC=%NEW_DEC% - 100
    )
    set CURRENT_AMPLITUDE=%INT_PART%.%NEW_DEC%
    echo [AMPLITUDE RAMP] Increased to A?=%CURRENT_AMPLITUDE%
    echo.
)

REM Check for entropy target (7.5+ bits)
for /f "tokens=1 delims=." %%a in ("%CYCLE_ENTROPY%") do set ENTROPY_INT=%%a
for /f "tokens=2 delims=." %%a in ("%CYCLE_ENTROPY%") do set ENTROPY_DEC=%%a
if %ENTROPY_INT% geq 7 (
    if %ENTROPY_INT% equ 7 (
        if %ENTROPY_DEC% geq 5 (
            echo [TARGET] Reached 7.5+ bits entropy at amplitude %CURRENT_AMPLITUDE%
            goto :ACCELERATED_END
        )
    ) else (
        echo [TARGET] Reached 7.5+ bits entropy at amplitude %CURRENT_AMPLITUDE%
        goto :ACCELERATED_END
    )
)

REM Continue to next cycle
goto :ACCELERATED_LOOP

:ACCELERATED_END
echo.
echo ========================================================================
echo  ACCELERATED PROTOCOL COMPLETE
echo  End: %date% %time%
echo  Cycles completed: %CYCLE_COUNT%
echo  Final amplitude: %CURRENT_AMPLITUDE%
echo  Final entropy: %CYCLE_ENTROPY% bits
echo ========================================================================
echo.
pause
