# Capture probe data to CSV
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "probe_full_$timestamp.log"
$csvFile = "probe_data_$timestamp.csv"

Write-Host "Starting probe capture..."
Write-Host "Log file: $logFile"
Write-Host "CSV file: $csvFile"

# Start the process
$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = ".\probe_256_final.exe"
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.UseShellExecute = $false
$processInfo.CreateNoWindow = $true

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $processInfo

$cycles = @()
$startTime = Get-Date

try {
    $process.Start() | Out-Null
    Write-Host "Process started (PID: $($process.Id))"
    
    $stdout = $process.StandardOutput
    $stderr = $process.StandardError
    
    # Write header to CSV
    "Cycle,Time,Omega,Enstrophy,RhoMin,RhoMax,Power,Guardians,Mass,MTotal,Probe,Timestamp" | Out-File -FilePath $csvFile -Encoding UTF8
    
    # Monitor loop
    while (!$process.HasExited) {
        # Read stdout
        if (!$stdout.EndOfStream) {
            $line = $stdout.ReadLine()
            
            # Write to log
            $line | Out-File -FilePath $logFile -Append -Encoding UTF8
            
            # Parse cycle data
            if ($line -match '^\s*(\d+)\s*\|\s*(\d+:\d+:\d+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.e\+\-]+)\s*\|\s*\[([\d\.]+),([\d\.]+)\]\s*\|\s*([\d\.e\+\-]+)\s*\|\s*(\d+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.]+)\s*\|\s*(\w+)') {
                $cycle = [PSCustomObject]@{
                    Cycle = [int]$Matches[1]
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
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
                }
                
                $cycles += $cycle
                
                # Write to CSV
                "$($cycle.Cycle),$($cycle.Time),$($cycle.Omega),$($cycle.Enstrophy),$($cycle.RhoMin),$($cycle.RhoMax),$($cycle.Power),$($cycle.Guardians),$($cycle.Mass),$($cycle.MTotal),$($cycle.Probe),$($cycle.Timestamp)" | Out-File -FilePath $csvFile -Append -Encoding UTF8
                
                # Show progress every 50 cycles
                if ($cycle.Cycle % 50 -eq 0) {
                    $runtime = (Get-Date) - $startTime
                    $runtimeStr = "{0:hh\:mm\:ss}" -f $runtime
                    Write-Host "Cycle $($cycle.Cycle) | Time: $runtimeStr | Omega: $($cycle.Omega) | Guardians: $($cycle.Guardians) | Mass: $($cycle.Mass)"
                }
            }
        }
        
        # Read stderr
        if (!$stderr.EndOfStream) {
            $errorLine = $stderr.ReadLine()
            $errorLine | Out-File -FilePath $logFile -Append -Encoding UTF8
            Write-Host "STDERR: $errorLine" -ForegroundColor Red
        }
        
        Start-Sleep -Milliseconds 10
    }
    
    # Process exited
    $exitCode = $process.ExitCode
    $runtime = (Get-Date) - $startTime
    $runtimeStr = "{0:hh\:mm\:ss}" -f $runtime
    
    Write-Host "`nProcess completed with exit code: $exitCode"
    Write-Host "Total runtime: $runtimeStr"
    Write-Host "Total cycles captured: $($cycles.Count)"
    
    # Summary
    if ($cycles.Count -gt 0) {
        $lastCycle = $cycles[-1]
        Write-Host "`nLast cycle: $($lastCycle.Cycle)"
        Write-Host "Final omega: $($lastCycle.Omega)"
        Write-Host "Final guardians: $($lastCycle.Guardians)"
        Write-Host "Final mass: $($lastCycle.Mass)"
        Write-Host "Final probe: $($lastCycle.Probe)"
        
        # Check if reached target
        if ($lastCycle.Cycle -ge 1700) {
            Write-Host "✅ SUCCESS: Reached target 1700 cycles!" -ForegroundColor Green
        } else {
            Write-Host "⚠️  WARNING: Stopped at cycle $($lastCycle.Cycle), target was 1700" -ForegroundColor Yellow
        }
    }
    
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
} finally {
    if ($process -and !$process.HasExited) {
        $process.Kill()
    }
}

Write-Host "`nData saved to:"
Write-Host "  Log: $logFile"
Write-Host "  CSV: $csvFile"