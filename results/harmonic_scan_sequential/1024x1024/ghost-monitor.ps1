# ============================================================================
# GHOST METRIC QUICK MONITOR
# One-liner for real-time entropy tracking
# ============================================================================

# Find latest log automatically
$log = Get-ChildItem "C:\fractal_nvme_test\ghost_metric_*\logs\baseline.log" -ErrorAction SilentlyContinue | 
       Sort-Object LastWriteTime -Descending | 
       Select-Object -First 1

if (-not $log) {
    Write-Host "❌ No ghost metric log files found" -ForegroundColor Red
    exit 1
}

Write-Host "Monitoring: $($log.FullName)" -ForegroundColor Gray
Write-Host "Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host ""

while($true) {
    if (Test-Path $log.FullName) {
        Clear-Host
        Write-Host "Time: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
        Write-Host "Status: Ghost Metric Observation`n" -ForegroundColor Cyan
        
        # Get recent somatic state
        $lines = Get-Content $log.FullName -Tail 10 | Select-String "\[SOMATIC_STATE\]"
        
        if ($lines) {
            $lines | ForEach-Object {
                if ($_ -match "Entropy: ([\d\.]+)") {
                    $entropy = [double]$Matches[1]
                    $color = if ($entropy -ge 6.75 -and $entropy -le 6.85) { "Green" } 
                             elseif ($entropy -ge 7.0) { "Red" } 
                             else { "Yellow" }
                    Write-Host $_ -ForegroundColor $color
                }
            }
            
            $lastLine = $lines[-1]
            if ($lastLine -match "Entropy: ([\d\.]+)") {
                $current = [double]$Matches[1]
                $percent = [math]::Min(100, [math]::Round(($current / 6.8) * 100, 1))
                Write-Host "`n📊 Progress: $percent% ($current/6.8 bits)" -ForegroundColor Cyan
                
                if ($current -ge 6.75 -and $current -le 6.85) {
                    Write-Host "🎯 TARGET REACHED - Waiting for stability..." -ForegroundColor Green
                }
            }
        } else {
            Write-Host "Waiting for somatic state data..." -ForegroundColor Yellow
        }
    }
    
    Write-Host "`n[Refreshing in 2s...]" -ForegroundColor DarkGray
    Start-Sleep -Seconds 2
}