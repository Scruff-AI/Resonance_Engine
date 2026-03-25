@echo off
REM ============================================================================
REM 1-HOUR ANALYTICS TEST - Practical pattern analysis
REM Runs 12 x 1M step tests with enhanced metric capture
REM ============================================================================

echo ========================================================================
echo  1-HOUR ANALYTICS TEST - Pattern analysis
echo  Started: %date% %time%
echo ========================================================================
echo.

set ANALYTICS_DIR=C:\fractal_nvme_test\analytics_1hour_%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%
set ANALYTICS_DIR=%ANALYTICS_DIR: =0%
mkdir "%ANALYTICS_DIR%" 2>nul
mkdir "%ANALYTICS_DIR%\metrics" 2>nul
mkdir "%ANALYTICS_DIR%\spectra" 2>nul

cd /d "D:\openclaw-local\workspace-main\harmonic_scan_sequential\1024x1024"

echo [ANALYTICS] Enhanced metric capture enabled
echo [ANALYTICS] Directory: %ANALYTICS_DIR%
echo [ANALYTICS] Will capture: entropy evolution, spectral changes, pattern metrics
echo.

REM Create analytics header
echo step,entropy,slope,peak_k,energy,active_modes,kx0_fraction,runtime_seconds > "%ANALYTICS_DIR%\metrics\evolution.csv"
echo run,start_time,end_time,entropy,slope,peak_k,energy,steps_per_sec > "%ANALYTICS_DIR%\metrics\runs_summary.csv"

set TOTAL_RUNS=12
set /a RUN_COUNT=0
set START_OVERALL=%time%

echo Running %TOTAL_RUNS% x 1M step tests (~1 hour total)...
echo.

:LOOP_START
set /a RUN_COUNT+=1
if %RUN_COUNT% gtr %TOTAL_RUNS% goto :LOOP_END

echo [Run %RUN_COUNT%/%TOTAL_RUNS%] Starting at %time%
set RUN_START=%time%

REM Run the test and capture output
fractal_habit_1M_test.exe > "%ANALYTICS_DIR%\run_%RUN_COUNT%.log" 2>&1

set RUN_END=%time%
echo [Run %RUN_COUNT%/%TOTAL_RUNS%] Completed at %RUN_END%

REM Extract metrics from log
set ENTROPY=0
set SLOPE=0
set PEAK_K=0
set ENERGY=0
set ACTIVE_MODES=0
set RUNTIME=0
set STEPS_PER_SEC=0

REM Parse the log file for metrics
for /f "tokens=2" %%a in ('type "%ANALYTICS_DIR%\run_%RUN_COUNT%.log" ^| findstr /C:"Entropy:"') do set ENTROPY=%%a
for /f "tokens=2" %%a in ('type "%ANALYTICS_DIR%\run_%RUN_COUNT%.log" ^| findstr /C:"Slope:"') do set SLOPE=%%a
for /f "tokens=4" %%a in ('type "%ANALYTICS_DIR%\run_%RUN_COUNT%.log" ^| findstr /C:"Peak k:"') do set PEAK_K=%%a
for /f "tokens=3" %%a in ('type "%ANALYTICS_DIR%\run_%RUN_COUNT%.log" ^| findstr /C:"Total energy:"') do set ENERGY=%%a
for /f "tokens=4" %%a in ('type "%ANALYTICS_DIR%\run_%RUN_COUNT%.log" ^| findstr /C:"Active modes:"') do set ACTIVE_MODES=%%a
for /f "tokens=2" %%a in ('type "%ANALYTICS_DIR%\run_%RUN_COUNT%.log" ^| findstr /C:"Runtime:"') do set RUNTIME=%%a
for /f "tokens=3 delims=()" %%a in ('type "%ANALYTICS_DIR%\run_%RUN_COUNT%.log" ^| findstr /C:"Runtime:"') do set STEPS_PER_SEC=%%a

REM Write to CSV
echo %RUN_COUNT%,%RUN_START%,%RUN_END%,%ENTROPY%,%SLOPE%,%PEAK_K%,%ENERGY%,%STEPS_PER_SEC% >> "%ANALYTICS_DIR%\metrics\runs_summary.csv"

echo   Metrics: Entropy=%ENTROPY%, Slope=%SLOPE%, Peak k=%PEAK_K%, Runtime=%RUNTIME% s
echo.

REM Check crystal files for this run
dir "C:\fractal_nvme_test\1M_test\crystal_*.crys" /b > "%ANALYTICS_DIR%\crystals_run_%RUN_COUNT%.txt"

REM Check if we should continue (1 hour total)
if %RUN_COUNT% equ %TOTAL_RUNS% goto :LOOP_END

REM Optional: Add variation for pattern analysis
if %RUN_COUNT% equ 4 (
    echo [PATTERN] Run 4 complete - system should be in steady state
    echo Steady state reached at run 4 >> "%ANALYTICS_DIR%\pattern_notes.txt"
)
if %RUN_COUNT% equ 8 (
    echo [PATTERN] Run 8 complete - checking for long-term stability
    echo Long-term stability check >> "%ANALYTICS_DIR%\pattern_notes.txt"
)

goto :LOOP_START

:LOOP_END
set END_OVERALL=%time%

echo ========================================================================
echo  1-HOUR TEST COMPLETE
echo ========================================================================
echo.

echo Overall: Started %START_OVERALL%, Ended %END_OVERALL%
echo Total runs: %RUN_COUNT%
echo Total steps: %RUN_COUNT% million
echo Analytics directory: %ANALYTICS_DIR%
echo.

echo [ANALYTICS] Generated files:
echo   metrics\evolution.csv - Time series of key metrics
echo   metrics\runs_summary.csv - Summary of each run
echo   pattern_notes.txt - Pattern observations
echo   run_*.log - Full output logs
echo   crystals_*.txt - Crystal file lists
echo.

echo [ANALYTICS] Pattern analysis ready:
echo   1. Check entropy evolution across runs
echo   2. Analyze spectral slope changes
echo   3. Look for pattern complexity
echo   4. Compare with the-craw metrics
echo.

echo Next: Analyze the CSV files for patterns and system potential
pause