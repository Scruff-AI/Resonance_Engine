@echo off
chcp 65001 >nul
echo ================================================================
echo REAL ANALYTICS - Capturing EVERYTHING
echo ================================================================
echo.

set TIMESTAMP=%date:~-4,4%%date:~-7,2%%date:~-10,2%_%time:~0,2%%time:~3,2%%time:~6,2%
set LOGFILE=analytics_%TIMESTAMP%.log
set CSVPREFIX=cycles_%TIMESTAMP%

echo Timestamp: %TIMESTAMP%
echo Log file: %LOGFILE%
echo CSV prefix: %CSVPREFIX%
echo.

echo Starting probe_256_final.exe with full analytics...
echo.

REM Run and capture ALL output
probe_256_final.exe > "%LOGFILE%" 2>&1

echo.
echo ================================================================
echo PROCESS COMPLETE
echo.

if %errorlevel% equ 0 (
    echo ✅ Clean exit (no crash)
) else (
    echo 🔴 Crash detected (exit code: %errorlevel%)
)

echo.
echo Raw log: %LOGFILE%
echo.
echo ================================================================
echo ANALYZING LOG FILE...
echo.

REM Extract cycle data to CSV
powershell -Command "& { $log = Get-Content '%LOGFILE%'; $cycles = @(); foreach ($line in $log) { if ($line -match '^\s*(\d+)\s*\|\s*(\d+:\d+:\d+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.e\+\-]+)\s*\|\s*\[([\d\.]+),([\d\.]+)\]\s*\|\s*([\d\.e\+\-]+)\s*\|\s*(\d+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.]+)\s*\|\s*(\w+)') { $cycles += [PSCustomObject]@{ Cycle=[int]$Matches[1]; Time=$Matches[2]; Omega=[float]$Matches[3]; Enstrophy=$Matches[4]; RhoMin=[float]$Matches[5]; RhoMax=[float]$Matches[6]; Power=$Matches[7]; Guardians=[int]$Matches[8]; Mass=[float]$Matches[9]; MTotal=[float]$Matches[10]; Probe=$Matches[11] } } }; $cycles | Export-Csv -Path '%CSVPREFIX%.csv' -NoTypeInformation; Write-Host 'Extracted ' $cycles.Count ' cycles to %CSVPREFIX%.csv' }"

REM Check for SILENT probe data
powershell -Command "& { $csv = Import-Csv '%CSVPREFIX%.csv'; $silent = $csv | Where-Object { $_.Probe -eq 'SILENT' }; if ($silent) { Write-Host 'SILENT probe cycles found: ' $silent.Count; $silent | Select-Object -First 3 | Format-Table Cycle, Omega, Guardians, Mass -AutoSize } else { Write-Host 'No SILENT probe cycles found' } }"

echo.
echo ================================================================
echo ANALYTICS COMPLETE
echo ================================================================
pause