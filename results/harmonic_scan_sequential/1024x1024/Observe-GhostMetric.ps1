# ============================================================================
# GHOST METRIC OBSERVATION SCRIPT
# Real-time monitoring of somatic state evolution
# ============================================================================

param(
    [string]$LogPath = "",
    [int]$RefreshSeconds = 2
)

function Show-Header {
    Clear-Host
    Write-Host "=======================================================================" -ForegroundColor Cyan
    Write-Host "  GHOST METRIC OBSERVATION STATION" -ForegroundColor White
    Write-Host "  Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host "=======================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Find-LatestLog {
    # Find the latest ghost metric log file
    $testDirs = Get-ChildItem "C:\fractal_nvme_test\ghost_metric_*" -Directory -ErrorAction SilentlyContinue | 
                Sort-Object CreationTime -Descending
    
    if ($testDirs) {
        $latestDir = $testDirs[0]
        $logFile = "$($latestDir.FullName)\logs\baseline.log"
        
        if (Test-Path $logFile) {
            return $logFile
        }
    }
    
    return $null
}

function Get-ProcessStatus {
    # Check if ghost metric process is running
    $process = Get-Process -Name "fractal_habit_ghost*" -ErrorAction SilentlyContinue
    
    if ($process) {
        return @{
            Running = $true
            Name = $process.ProcessName
            PID = $process.Id
            CPU = [math]::Round($process.CPU/60, 1)
            Memory = [math]::Round($process.WorkingSet64/1MB, 1)
            StartTime = $process.StartTime
        }
    } else {
        return @{ Running = $false }
    }
}

function Analyze-EntropyTrend($entropyValues) {
    # Analyze entropy trend
    if ($entropyValues.Count -lt 2) {
        return "Insufficient data"
    }
    
    $current = $entropyValues[-1]
    $previous = $entropyValues[-2]
    $delta = $current - $previous
    
    if ($delta -gt 0.01) {
        return "↗️ Rising"
    } elseif ($delta -lt -0.01) {
        return "↘️ Falling"
    } else {
        return "➡️ Stable"
    }
}

function Get-PhaseEstimate($currentEntropy, $targetEntropy) {
    # Estimate current phase based on entropy
    $distance = [math]::Abs($currentEntropy - $targetEntropy)
    
    if ($distance -lt 0.05) {
        return "🎯 Target Zone (6.75-6.85 bits)"
    } elseif ($currentEntropy -gt 7.0) {
        return "🔥 Injury Phase (>7.0 bits)"
    } elseif ($currentEntropy -lt 6.0) {
        return "😴 Sleep State (<6.0 bits)"
    } else {
        return "🔄 Active Homeostasis (6.0-7.0 bits)"
    }
}

# Main observation loop
if (-not $LogPath) {
    $LogPath = Find-LatestLog
    if (-not $LogPath) {
        Write-Host "❌ No ghost metric log files found" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Using log file: $LogPath" -ForegroundColor Gray
Write-Host "Refresh interval: ${RefreshSeconds}s" -ForegroundColor Gray
Write-Host "Press Ctrl+C to stop monitoring" -ForegroundColor Gray
Write-Host ""

$entropyHistory = @()
$lastFileSize = 0

while ($true) {
    Show-Header
    
    # Check process status
    $procStatus = Get-ProcessStatus
    if ($procStatus.Running) {
        Write-Host "✅ PROCESS STATUS" -ForegroundColor Green
        Write-Host "   Name: $($procStatus.Name)" -ForegroundColor Gray
        Write-Host "   PID: $($procStatus.PID)" -ForegroundColor Gray
        Write-Host "   CPU: $($procStatus.CPU) minutes" -ForegroundColor Gray
        Write-Host "   Memory: $($procStatus.Memory) MB" -ForegroundColor Gray
        Write-Host "   Started: $($procStatus.StartTime)" -ForegroundColor Gray
    } else {
        Write-Host "❌ PROCESS STATUS: NOT RUNNING" -ForegroundColor Red
    }
    
    Write-Host ""
    
    # Check log file
    if (Test-Path $LogPath) {
        $currentSize = (Get-Item $LogPath).Length
        
        if ($currentSize -eq $lastFileSize) {
            Write-Host "⚠️  LOG STATUS: No new data (file size unchanged)" -ForegroundColor Yellow
        } else {
            Write-Host "✅ LOG STATUS: Active (size: $([math]::Round($currentSize/1KB,1)) KB)" -ForegroundColor Green
            $lastFileSize = $currentSize
        }
        
        Write-Host ""
        
        # Get recent somatic state entries
        $somaticLines = Get-Content $LogPath -Tail 50 | Select-String "\[SOMATIC_STATE\]"
        
        if ($somaticLines) {
            Write-Host "📊 RECENT SOMATIC STATE" -ForegroundColor Cyan
            Write-Host ""
            
            # Show last 5 entries
            $recentLines = $somaticLines[-5..-1]
            foreach ($line in $recentLines) {
                if ($line -match "Step: (\d+) \| Entropy: ([\d\.]+) \| Target: ([\d\.]+)") {
                    $step = [int]$Matches[1]
                    $entropy = [double]$Matches[2]
                    $target = [double]$Matches[3]
                    
                    # Color coding
                    if ($entropy -ge 6.75 -and $entropy -le 6.85) {
                        $color = "Green"
                    } elseif ($entropy -ge 7.0) {
                        $color = "Red"
                    } elseif ($entropy -lt 6.0) {
                        $color = "DarkGray"
                    } else {
                        $color = "Yellow"
                    }
                    
                    Write-Host "   Step: $step | Entropy: $entropy bits | Target: $target bits" -ForegroundColor $color
                    
                    # Add to history
                    $entropyHistory += $entropy
                    if ($entropyHistory.Count -gt 100) {
                        $entropyHistory = $entropyHistory[-100..-1]
                    }
                }
            }
            
            # Analyze current state
            $lastLine = $somaticLines[-1]
            if ($lastLine -match "Entropy: ([\d\.]+)") {
                $currentEntropy = [double]$Matches[1]
                $targetEntropy = 6.8
                
                Write-Host ""
                Write-Host "🎯 CURRENT ANALYSIS" -ForegroundColor Cyan
                
                # Progress
                $percent = [math]::Min(100, [math]::Round(($currentEntropy / $targetEntropy) * 100, 1))
                Write-Host "   Progress: $percent% ($currentEntropy/$targetEntropy bits)" -ForegroundColor White
                
                # Distance from target
                $distance = [math]::Abs($currentEntropy - $targetEntropy)
                if ($distance -lt 0.05) {
                    Write-Host "   Status: WITHIN TARGET RANGE (±0.05 bits)" -ForegroundColor Green
                } else {
                    Write-Host "   Status: $distance bits from target" -ForegroundColor Yellow
                }
                
                # Phase estimate
                $phase = Get-PhaseEstimate $currentEntropy $targetEntropy
                Write-Host "   Phase: $phase" -ForegroundColor Gray
                
                # Trend analysis
                if ($entropyHistory.Count -gt 1) {
                    $trend = Analyze-EntropyTrend $entropyHistory
                    Write-Host "   Trend: $trend" -ForegroundColor Gray
                }
                
                # Check for target achievement
                if ($distance -lt 0.05) {
                    Write-Host ""
                    Write-Host "🎯 TARGET ACHIEVED!" -ForegroundColor Green
                    Write-Host "   System should dump fingerprint when stable for 5 minutes" -ForegroundColor Gray
                }
            }
            
            # Check for completion messages
            $completionLines = Get-Content $LogPath -Tail 10 | Select-String "TIMEOUT|COMPLETE|SUCCESS|ERROR"
            if ($completionLines) {
                Write-Host ""
                Write-Host "🚨 COMPLETION STATUS" -ForegroundColor Magenta
                $completionLines | ForEach-Object {
                    Write-Host "   $_" -ForegroundColor $(if ($_ -match "ERROR|TIMEOUT") { "Red" } else { "Green" })
                }
            }
        } else {
            Write-Host "⏳ WAITING FOR SOMATIC STATE DATA" -ForegroundColor Yellow
            Write-Host "   Last 5 lines of log:" -ForegroundColor Gray
            Get-Content $LogPath -Tail 5 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
        }
    } else {
        Write-Host "❌ LOG FILE NOT FOUND: $LogPath" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "=======================================================================" -ForegroundColor DarkGray
    Write-Host "  Next update in ${RefreshSeconds}s | Press Ctrl+C to exit" -ForegroundColor DarkGray
    
    Start-Sleep -Seconds $RefreshSeconds
}