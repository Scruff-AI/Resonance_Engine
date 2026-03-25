@echo off
echo ========================================
echo CONTINUOUS PHASE SHIFT TEST
echo Starting at: %time%
echo ========================================
echo.

set cycle=1
set max_cycles=4  ; Run 4 times (2 hours total)

:loop
echo.
echo [CYCLE %cycle%/%max_cycles%] Starting probe_256_final.exe...
echo Start time: %time%

.\probe_256_final.exe

echo.
echo [CYCLE %cycle%/%max_cycles%] Completed
echo End time: %time%
echo Exit code: %errorlevel%

if %cycle% equ %max_cycles% goto :done
set /a cycle=cycle+1
echo.
echo Waiting 10 seconds before next cycle...
timeout /t 10 /nobreak >nul
goto :loop

:done
echo.
echo ========================================
echo TEST COMPLETE
echo Total cycles: %cycle%
echo End time: %time%
echo ========================================