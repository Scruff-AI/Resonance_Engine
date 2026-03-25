# Simple monitor for crash test
$logfile = "crash_test_20260311_220633.log"
$csvfile = "cycles_20260311_220633.csv"

Write-Host "Simple crash test monitor" -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop" -ForegroundColor Gray

$lastCycle = 0
$cycles = @()

try {
    while ($true) {
        if (Test-Path $logfile) {
            $content = Get-Content $logfile -Tail 20
            
            foreach ($line in $content) {
                if ($line -match '^\s*(\d+)\s*\|\s*(\d+:\d+:\d+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.e\+\-]+)\s*\|\s*\[([\d\.]+),([\d\.]+)\]\s*\|\s*([\d\.e\+\-]+)\s*\|\s*(\d+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.]+)\s*\|\s*(\w+)') {
                    $cycle = [int]$Matches[1]
                    
                    if ($cycle -gt $lastCycle) {
                        $lastCycle = $cycle
                        
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
                        
                        # Show progress
                        if ($cycle % 100 -eq 0) {
                            Write-Host "Cycle $cycle | Omega: $($cycleObj.Omega) | Probe: $($cycleObj.Probe)" -ForegroundColor Gray
                        }
                        
                        # Check for SILENT probe
                        if ($cycle -ge 1100 -and $cycle -le 1199 -and $cycleObj.Probe -eq "SILENT") {
                            Write-Host "SILENT probe at cycle $cycle" -ForegroundColor Yellow
                        }
                    }
                }
                
                # Check for errors
                if ($line -match 'ERROR|error|Error') {
                    Write-Host "Error: $line" -ForegroundColor Red
                }
            }
            
            # Save data
            if ($cycles.Count -gt 0) {
                $cycles | Export-Csv -Path $csvfile -NoTypeInformation
            }
        }
        
        # Check if probe is still running
        $probe = Get-Process -Name "probe_256_final" -ErrorAction SilentlyContinue
        if (-not $probe) {
            Write-Host "Probe has terminated. Last cycle: $lastCycle" -ForegroundColor Cyan
            
            if ($lastCycle -ge 1100 -and $lastCycle -le 1199) {
                Write-Host "CRASH IN SILENT PROBE ZONE (1100-1199)" -ForegroundColor Red
            }
            
            break
        }
        
        Start-Sleep -Seconds 2
    }
}
catch {
    Write-Host "Monitor stopped: $_" -ForegroundColor Red
}

Write-Host "Monitor finished. Total cycles: $($cycles.Count)" -ForegroundColor Cyan