# Run probe_256_final.exe with full analytics until crash
# Captures ALL data, saves to CSV, runs continuously

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logfile = "crash_test_${timestamp}.log"
$csvfile = "cycles_${timestamp}.csv"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "CRASH TEST - Running until failure" -ForegroundColor Cyan
Write-Host "Log: $logfile" -ForegroundColor Cyan
Write-Host "CSV: $csvfile" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# Start the probe
$process = Start-Process -FilePath ".\probe_256_final.exe" -NoNewWindow -PassThru -RedirectStandardOutput $logfile

Write-Host "Process started (PID: $($process.Id))" -ForegroundColor Green
Write-Host "Monitoring for crash..." -ForegroundColor Yellow

# Monitor process
$cycles = @()
$lastCycle = 0
$crashDetected = $false

while (-not $process.HasExited) {
    Start-Sleep -Seconds 2
    
    # Read latest log entries
    if (Test-Path $logfile) {
        $logContent = Get-Content $logfile -Tail 100
        
        foreach ($line in $logContent) {
            # Parse cycle data
            if ($line -match '^\s*(\d+)\s*\|\s*(\d+:\d+:\d+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.e\+\-]+)\s*\|\s*\[([\d\.]+),([\d\.]+)\]\s*\|\s*([\d\.e\+\-]+)\s*\|\s*(\d+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.]+)\s*\|\s*(\w+)') {
                $cycle = [int]$Matches[1]
                
                # Only add new cycles
                if ($cycle -gt $lastCycle) {
                    $cycleObj = [PSCustomObject]@{
                        Cycle = $cycle
                        Time = $Matches[2]
                        Omega = [float]$Matches[3]
                        Enstrophy = $Matches[4]
                        RhoMin = [float]$Matches[5]
                        RhoMax = [float]$Matches[6]
                        Power = $Matches[7]
                        Guardians = [int]$Matches[8]
                        Mass = [float]$Matches[9]
                        MTotal = [float]$Matches[10]
                        Probe = $Matches[11]
                        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                    }
                    $cycles += $cycleObj
                    $lastCycle = $cycle
                    
                    # Display progress
                    if ($cycle % 100 -eq 0) {
                        Write-Host "  Cycle $cycle | Omega: $($cycleObj.Omega) | Guardians: $($cycleObj.Guardians) | Mass: $($cycleObj.Mass)" -ForegroundColor Gray
                    }
                    
                    # Check for SILENT probe (crash zone)
                    if ($cycle -ge 1100 -and $cycle -le 1199 -and $cycleObj.Probe -eq "SILENT") {
                        Write-Host "  ⚠️  SILENT probe: Cycle $cycle | Omega: $($cycleObj.Omega)" -ForegroundColor Yellow
                    }
                }
            }
            
            # Check for crash indicators
            if ($line -match 'ERROR|error|Error|CUDA error|cudaError|NVML error|nvmlError|Access violation|Segmentation fault') {
                Write-Host "  🔴 ERROR DETECTED: $line" -ForegroundColor Red
                $crashDetected = $true
            }
        }
    }
}

# Process exited
$exitCode = $process.ExitCode
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "PROCESS EXITED" -ForegroundColor Cyan
Write-Host "Exit code: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Red" })
Write-Host "Cycles captured: $($cycles.Count)" -ForegroundColor Cyan
Write-Host "Last cycle: $lastCycle" -ForegroundColor Cyan

# Save cycle data
if ($cycles.Count -gt 0) {
    $cycles | Export-Csv -Path $csvfile -NoTypeInformation
    Write-Host "Cycle data saved to: $csvfile" -ForegroundColor Green
    
    # Analyze SILENT probe data
    $silentCycles = $cycles | Where-Object { $_.Probe -eq "SILENT" }
    if ($silentCycles.Count -gt 0) {
        Write-Host "SILENT probe cycles: $($silentCycles.Count)" -ForegroundColor Yellow
        $silentCycles | Select-Object -First 5 | Format-Table Cycle, Omega, Guardians, Mass -AutoSize
    }
}

# Analyze crash
if ($exitCode -ne 0) {
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host "CRASH ANALYSIS" -ForegroundColor Red
    
    # Get last 20 lines of log
    $lastLines = Get-Content $logfile -Tail 20
    Write-Host "Last log lines:" -ForegroundColor Red
    $lastLines | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    
    # Check crash cycle
    if ($lastCycle -ge 1100 -and $lastCycle -le 1199) {
        Write-Host "  🔴 CRASH IN SILENT PROBE (cycles 1100-1199)" -ForegroundColor Red
        Write-Host "  Last cycle: $lastCycle" -ForegroundColor Red
    }
}

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "TEST COMPLETE" -ForegroundColor Cyan
Write-Host "Log file: $logfile" -ForegroundColor Cyan
Write-Host "CSV file: $csvfile" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan