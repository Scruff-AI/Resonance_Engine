# Monitor the crash test and capture data
$logfile = "crash_test_20260311_220633.log"
$csvfile = "cycles_20260311_220633.csv"

Write-Host "Monitoring crash test..." -ForegroundColor Yellow
Write-Host "Log file: $logfile" -ForegroundColor Cyan
Write-Host "CSV file: $csvfile" -ForegroundColor Cyan

$cycles = @()
$lastCycle = 0
$silentProbeDetected = $false

while ($true) {
    # Check if log file exists
    if (Test-Path $logfile) {
        # Read the last 50 lines
        $logContent = Get-Content $logfile -Tail 50
        
        foreach ($line in $logContent) {
            # Parse cycle data - match the format from the log
            if ($line -match '^\s*(\d+)\s*\|\s*(\d+:\d+:\d+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.e\+\-]+)\s*\|\s*\[([\d\.]+),([\d\.]+)\]\s*\|\s*([\d\.e\+\-]+)\s*\|\s*(\d+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.]+)\s*\|\s*(\w+)') {
                $cycle = [int]$Matches[1]
                
                # Only add new cycles
                if ($cycle -gt $lastCycle) {
                    $cycleObj = [PSCustomObject]@{
                        Cycle = $cycle
                        Time = $Matches[2]
                        Omega = [float]$Matches[3]
                        SpeedRange = $Matches[4]
                        RhoMin = [float]$Matches[5]
                        RhoMax = [float]$Matches[6]
                        Enstrophy = $Matches[7]
                        Particles = [int]$Matches[8]
                        ParticleMass = [float]$Matches[9]
                        TotalMass = [float]$Matches[10]
                        Probe = $Matches[11]
                        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                    }
                    $cycles += $cycleObj
                    $lastCycle = $cycle
                    
                    # Display progress every 50 cycles
                    if ($cycle % 50 -eq 0) {
                        Write-Host "  Cycle $cycle | Omega: $($cycleObj.Omega) | Particles: $($cycleObj.Particles) | Probe: $($cycleObj.Probe)" -ForegroundColor Gray
                    }
                    
                    # Check for SILENT probe (crash zone 1100-1199)
                    if ($cycle -ge 1100 -and $cycle -le 1199 -and $cycleObj.Probe -eq "SILENT") {
                        if (-not $silentProbeDetected) {
                            Write-Host "  ⚠️  SILENT PROBE DETECTED: Cycle $cycle | Omega: $($cycleObj.Omega)" -ForegroundColor Yellow
                            $silentProbeDetected = $true
                        }
                    }
                }
            }
            
            # Check for crash indicators
            if ($line -match 'ERROR|error|Error|CUDA error|cudaError|NVML error|nvmlError|Access violation|Segmentation fault') {
                Write-Host "  🔴 ERROR DETECTED: $line" -ForegroundColor Red
            }
        }
        
        # Save data periodically
        if ($cycles.Count -gt 0 -and $cycles.Count % 100 -eq 0) {
            $cycles | Export-Csv -Path $csvfile -NoTypeInformation
            Write-Host "  Data saved: $($cycles.Count) cycles" -ForegroundColor Green
        }
    }
    
    # Check if the probe process is still running
    $probeProcess = Get-Process -Name "probe_256_final" -ErrorAction SilentlyContinue
    if (-not $probeProcess) {
        Write-Host "  🔴 Probe process has terminated" -ForegroundColor Red
        
        # Save final data
        if ($cycles.Count -gt 0) {
            $cycles | Export-Csv -Path $csvfile -NoTypeInformation
            Write-Host "  Final data saved: $($cycles.Count) cycles" -ForegroundColor Green
        }
        
        # Get exit code if possible
        Write-Host "  Last cycle: $lastCycle" -ForegroundColor Cyan
        
        # Check if crash was in SILENT probe zone
        if ($lastCycle -ge 1100 -and $lastCycle -le 1199) {
            Write-Host "  🔴 CRASH IN SILENT PROBE ZONE (cycles 1100-1199)" -ForegroundColor Red
        }
        
        break
    }
    
    # Wait before checking again
    Start-Sleep -Seconds 5
}