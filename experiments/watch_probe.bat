@echo off
chcp 65001 >nul
echo ================================================================
echo PROBE MONITOR - Watching for crash at cycle ~1112
echo ================================================================
echo.

set LOGFILE=monitor_%date:~-4,4%%date:~-7,2%%date:~-10,2%_%time:~0,2%%time:~3,2%%time:~6,2%.log
echo Log file: %LOGFILE%

echo Starting probe_256_final.exe...
echo.

probe_256_final.exe > "%LOGFILE%" 2>&1

echo.
echo ================================================================
echo PROCESS EXITED
echo.

REM Check exit code
if %errorlevel% equ 0 (
    echo ✅ Clean exit (no crash)
) else (
    echo 🔴 Crash detected (exit code: %errorlevel%)
)

echo.
echo Full output saved to: %LOGFILE%
echo ================================================================
pause