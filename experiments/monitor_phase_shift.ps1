# monitor_phase_shift.ps1
# Real-time monitoring and analytics for probe_256_final.exe phase shift test
# Detects crash at cycle ~1112 (SILENT probe bug) and provides detailed analysis

param(
    [string]$ExePath = ".\probe_256_final.exe",
    [int]$CrashZoneStart = 1100,
    [int]$CrashZoneEnd = 1200,
    [string]$LogFile = "crash_analysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

# ANSI color codes for better visibility
$ColorRed = "`e[31m"
$ColorGreen = "`e[32m"
$ColorYellow = "`e[33m"
$ColorBlue = "`e[34m"
$ColorMagenta = "`e[35m"
$ColorCyan = "`e[36m"
$ColorReset = "`e[0m"

# Initialize analytics
$Analytics = @{
    StartTime = Get-Date
    LastCycle = 0
    CrashCycle = $null
    CrashTime = $null
    ExitCode = $null
    ProbeState = "---"
    PreCrashPatterns = @()
    ErrorMessages = @()
    CyclePatterns = @()
    PowerReadings = @()
    OmegaValues = @()
}

function Write-Analytics {
    param([string]$Message, [string]$Color = $ColorReset, [switch]$Important)
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    
    if ($Important) {
        Write-Host "$Color`n════════════════════════════════════════════════════════════════`n" -NoNewline
        Write-Host "$Color$logEntry$ColorReset" -NoNewline
        Write-Host "$Color`n════════════════════════════════════════════════════════════════`n$ColorReset"
    } else {
        Write-Host "$Color$logEntry$ColorReset"
    }
    
    # Log to file
    Add-Content -Path $LogFile -Value $logEntry
}

function Parse-CycleLine {
    param([string]$Line)
    
    # Pattern: " 1112 | 0:30:01 | 1.2500 | 8.958159e-08 | [1.00030,1.00030] | 4.782e-12 |   13 |     6.08 |    65561.88 | SILENT"
    $pattern = '^\s*(\d+)\s*\|\s*(\d+:\d+:\d+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.e\+\-]+)\s*\|\s*\[([\d\.]+),([\d\.]+)\]\s*\|\s*([\d\.e\+\-]+)\s*\|\s*(\d+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.]+)\s*\|\s*(\w+)'
    
    if ($Line -match $pattern) {
        return @{
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
        }
    }
    return $null
}

function Detect-CrashPatterns {
    param([hashtable]$CycleData)
    
    $patterns = @()
    
    # Check for SILENT probe issues
    if ($CycleData.Probe -eq "SILENT") {
        # Omega locked at exactly 1.25?
        if ([math]::Abs($CycleData.Omega - 1.25) -lt 0.001) {
            $patterns += "OMEGA_LOCKED_1.25"
        }
        
        # Check for unusual omega values
        if ($CycleData.Omega -lt 0.6 -or $CycleData.Omega -gt 1.95) {
            $patterns += "OMEGA_OUT_OF_RANGE"
        }
    }
    
    # Check for guardian count changes
    if ($Analytics.LastCycle -gt 0 -and $CycleData.Guardians -ne $Analytics.CyclePatterns[-1].Guardians) {
        $patterns += "GUARDIAN_COUNT_CHANGED"
    }
    
    # Check for mass accumulation issues
    if ($CycleData.Mass -gt 100) {
        $patterns += "MASS_EXCESSIVE"
    }
    
    # Check for power anomalies
    if ($CycleData.Power -match 'e' -and [double]$CycleData.Power -gt 1e-5) {
        $patterns += "POWER_SPIKE"
    }
    
    return $patterns
}

function Show-AnalyticsDashboard {
    Clear-Host
    Write-Host "$ColorCyan╔══════════════════════════════════════════════════════════════╗$ColorReset"
    Write-Host "$ColorCyan║                PHASE SHIFT MONITOR - LIVE ANALYTICS          ║$ColorReset"
    Write-Host "$ColorCyan╠══════════════════════════════════════════════════════════════╣$ColorReset"
    
    if ($Analytics.CrashCycle) {
        Write-Host "$ColorRed║  STATUS: CRASH DETECTED at cycle $($Analytics.CrashCycle)                   ║$ColorReset"
        Write-Host "$ColorRed║  Exit code: $($Analytics.ExitCode) | Time: $($Analytics.CrashTime)                ║$ColorReset"
    } else {
        $runtime = (Get-Date) - $Analytics.StartTime
        $runtimeStr = "{0:hh\:mm\:ss}" -f $runtime
        Write-Host "$ColorGreen║  STATUS: RUNNING | Cycle: $($Analytics.LastCycle) | Time: $runtimeStr          ║$ColorReset"
    }
    
    Write-Host "$ColorCyan╠══════════════════════════════════════════════════════════════╣$ColorReset"
    
    if ($Analytics.CyclePatterns.Count -gt 0) {
        $latest = $Analytics.CyclePatterns[-1]
        Write-Host "$ColorYellow║  CURRENT STATE:                                               ║$ColorReset"
        Write-Host "$ColorYellow║    Probe: $($latest.Probe.PadRight(8)) Omega: $($latest.Omega.ToString("F4").PadRight(8)) ║$ColorReset"
        Write-Host "$ColorYellow║    Guardians: $($latest.Guardians.ToString().PadRight(3)) Mass: $($latest.Mass.ToString("F2").PadRight(8)) ║$ColorReset"
        Write-Host "$ColorYellow║    M_total: $($latest.MTotal.ToString("F2").PadRight(10))                    ║$ColorReset"
    }
    
    Write-Host "$ColorCyan╠══════════════════════════════════════════════════════════════╣$ColorReset"
    
    # Show crash zone warning if approaching
    if ($Analytics.LastCycle -ge $CrashZoneStart -and $Analytics.LastCycle -le $CrashZoneEnd) {
        Write-Host "$ColorRed║  ⚠️  CRASH ZONE: Cycles $CrashZoneStart-$CrashZoneEnd (SILENT probe)  ║$ColorReset"
        Write-Host "$ColorRed║  Expected crash: cycle ~1112 (omega locked at 1.25)          ║$ColorReset"
    } elseif ($Analytics.LastCycle -gt $CrashZoneEnd) {
        Write-Host "$ColorGreen║  ✅ PASSED CRASH ZONE: Survived SILENT probe!                ║$ColorReset"
    } else {
        $cyclesToCrash = $CrashZoneStart - $Analytics.LastCycle
        if ($cyclesToCrash -gt 0) {
            Write-Host "$ColorYellow║  Cycles to crash zone: $cyclesToCrash                                 ║$ColorReset"
        }
    }
    
    Write-Host "$ColorCyan╠══════════════════════════════════════════════════════════════╣$ColorReset"
    
    # Show recent patterns
    if ($Analytics.PreCrashPatterns.Count -gt 0) {
        Write-Host "$ColorMagenta║  RECENT PATTERNS:                                            ║$ColorReset"
        $recent = $Analytics.PreCrashPatterns | Select-Object -Last 3
        foreach ($pattern in $recent) {
            Write-Host "$ColorMagenta║    • $($pattern.PadRight(54)) ║$ColorReset"
        }
    }
    
    Write-Host "$ColorCyan╚══════════════════════════════════════════════════════════════╝$ColorReset"
    Write-Host ""
}

function Analyze-Crash {
    Write-Analytics "════════════════════════════════════════════════════════════════" -Color $ColorRed -Important
    Write-Analytics "💥 CRASH ANALYSIS REPORT" -Color $ColorRed -Important
    Write-Analytics "════════════════════════════════════════════════════════════════" -Color $ColorRed -Important
    
    Write-Analytics "Crash confirmed at cycle: $($Analytics.CrashCycle)" -Color $ColorYellow
    Write-Analytics "Exit code: $($Analytics.ExitCode)" -Color $ColorYellow
    Write-Analytics "Probe state: $($Analytics.ProbeState)" -Color $ColorYellow
    
    # Analyze crash pattern
    if ($Analytics.CrashCycle -ge 1100 -and $Analytics.CrashCycle -le 1199) {
        Write-Analytics "🔍 CRASH IN SILENT PROBE (cycles 1100-1199)" -Color $ColorRed
        Write-Analytics "   Probe C: VRM Silence (omega locked to 1.25)" -Color $ColorYellow
        Write-Analytics "   Possible causes:" -Color $ColorYellow
        Write-Analytics "   1. GPU memory error during omega lock" -Color $ColorYellow
        Write-Analytics "   2. CUDA kernel failure with locked parameters" -Color $ColorYellow
        Write-Analytics "   3. Numerical instability at fixed omega=1.25" -Color $ColorYellow
        Write-Analytics "   4. Buffer overflow in VRM silence logic" -Color $ColorYellow
    }
    
    # Show error messages
    if ($Analytics.ErrorMessages.Count -gt 0) {
        Write-Analytics "📄 ERROR MESSAGES:" -Color $ColorRed
        foreach ($errorMsg in $Analytics.ErrorMessages | Select-Object -First 5) {
            Write-Analytics "   $errorMsg" -Color $ColorYellow
        }
    }
    
    # Show last few cycles before crash
    if ($Analytics.CyclePatterns.Count -gt 0) {
        Write-Analytics "📝 LAST 5 CYCLES BEFORE CRASH:" -Color $ColorRed
        $lastCycles = $Analytics.CyclePatterns | Select-Object -Last 5
        foreach ($cycle in $lastCycles) {
            Write-Analytics "   Cycle $($cycle.Cycle): $($cycle.Probe) | Omega: $($cycle.Omega) | Guardians: $($cycle.Guardians)" -Color $ColorYellow
        }
    }
    
    # Recommendations
    Write-Analytics "════════════════════════════════════════════════════════════════" -Color $ColorGreen -Important
    Write-Analytics "🔧 RECOMMENDATIONS" -Color $ColorGreen -Important
    Write-Analytics "════════════════════════════════════════════════════════════════" -Color $ColorGreen -Important
    
    if ($Analytics.ExitCode -eq 1 -and $Analytics.CrashCycle -ge 1100 -and $Analytics.CrashCycle -le 1199) {
        Write-Analytics "1. ⚠️ SILENT PROBE BUG CONFIRMED" -Color $ColorRed
        Write-Analytics "   - Crash occurs in VRM Silence (omega locked 1.25)" -Color $ColorYellow
        Write-Analytics "   - Need to examine SILENT probe implementation" -Color $ColorYellow
        Write-Analytics "   - Possible fix: Remove or modify omega locking" -Color $ColorYellow
        
        Write-Analytics "`n2. IMMEDIATE ACTIONS:" -Color $ColorGreen
        Write-Analytics "   a) Check probe_256.cu lines for SILENT probe logic" -Color $ColorYellow
        Write-Analytics "   b) Look for 'omega = 1.25' or similar hardcoded values" -Color $ColorYellow
        Write-Analytics "   c) Check CUDA error handling in VRM silence" -Color $ColorYellow
        Write-Analytics "   d) Consider removing SILENT probe for stability" -Color $ColorYellow
        
        Write-Analytics "`n3. WORKAROUNDS:" -Color $ColorGreen
        Write-Analytics "   a) Run without probes (continuous operation)" -Color $ColorYellow
        Write-Analytics "   b) Modify MAX_CYCLES to stop before 1100" -Color $ColorYellow
        Write-Analytics "   c) Fix SILENT probe implementation" -Color $ColorYellow
        Write-Analytics "   d) Use fractal_habit_256.exe (no probes, 10M steps)" -Color $ColorYellow
    }
    
    Write-Analytics "`n📁 Full crash data saved to: $LogFile" -Color $ColorCyan
}

# Main execution
Write-Analytics "════════════════════════════════════════════════════════════════" -Color $ColorCyan -Important
Write-Analytics "🚀 PHASE SHIFT MONITOR STARTING" -Color $ColorCyan -Important
Write-Analytics "Monitoring: $ExePath" -Color $ColorCyan
Write-Analytics "Crash zone: cycles $CrashZoneStart-$CrashZoneEnd (SILENT probe)" -Color $ColorCyan
Write-Analytics "Log file: $LogFile" -Color $ColorCyan
Write-Analytics "════════════════════════════════════════════════════════════════" -Color $ColorCyan -Important

# Start the process
$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = $ExePath
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.UseShellExecute = $false
$processInfo.CreateNoWindow = $true

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $processInfo

try {
    $process.Start() | Out-Null
    Write-Analytics "Process started (PID: $($process.Id))" -Color $ColorGreen
    
    # Create output stream readers
    $stdoutReader = $process.StandardOutput
    $stderrReader = $process.StandardError
    
    # Initial dashboard
    Show-AnalyticsDashboard
    
    # Monitor output
    while (!$process.HasExited) {
        # Check for stdout
        if (!$stdoutReader.EndOfStream) {
            $line = $stdoutReader.ReadLine()
            
            # Parse cycle data
            $cycleData = Parse-CycleLine $line
            if ($cycleData) {
                $Analytics.LastCycle = $cycleData.Cycle
                $Analytics.ProbeState = $cycleData.Probe
                $Analytics.CyclePatterns += $cycleData
                
                # Detect patterns
                $patterns = Detect-CrashPatterns $cycleData
                if ($patterns.Count -gt 0) {
                    $Analytics.PreCrashPatterns += $patterns
                    foreach ($pattern in $patterns) {
                        Write-Analytics "Pattern detected: $pattern at cycle $($cycleData.Cycle)" -Color $ColorYellow
                    }
                }
                
                # Check if in crash zone
                if ($cycleData.Cycle -ge $CrashZoneStart -and $cycleData.Cycle -le $CrashZoneEnd) {
                    if ($cycleData.Probe -eq "SILENT") {
                        Write-Analytics "⚠️  ENTERED SILENT PROBE ZONE: Cycle $($cycleData.Cycle), Omega: $($cycleData.Omega)" -Color $ColorRed
                    }
                }
                
                # Update dashboard every 10 cycles
                if ($cycleData.Cycle % 10 -eq 0) {
                    Show-AnalyticsDashboard
                }
            }
            
            # Check for error indicators
            $errorIndicators = @("error", "Error", "ERROR", "exception", "Exception", "EXCEPTION", 
                                "fatal", "Fatal", "FATAL", "segmentation", "Segmentation",
                                "access violation", "Access violation", "cudaError", "CUDA error",
                                "nvmlError", "NVML error")
            
            foreach ($indicator in $errorIndicators) {
                if ($line -match $indicator) {
                    Write-Analytics "🔴 ERROR INDICATOR: $indicator in output" -Color $ColorRed
                    $Analytics.ErrorMessages += $line
                }
            }
        }
        
        # Check for stderr
        if (!$stderrReader.EndOfStream) {
            $errorLine = $stderrReader.ReadLine()
            Write-Analytics "🔴 STDERR: $errorLine" -Color $ColorRed
            $Analytics.ErrorMessages += $errorLine
        }
        
        # Small delay to prevent CPU hogging
        Start-Sleep -Milliseconds 10
    }
    
    # Process exited
    $Analytics.CrashCycle = $Analytics.LastCycle
    $Analytics.CrashTime = Get-Date
    $Analytics.ExitCode = $process.ExitCode
    
    # Final dashboard
    Show-AnalyticsDashboard
    
    # Analyze crash
    Analyze-Crash
    
} catch {
    Write-Analytics "❌ ERROR: $_" -Color $ColorRed
} finally {
    if ($process -and !$process.HasExited) {
        $process.Kill()
    }
}

Write-Analytics "════════════════════════════════════════════════════════════════" -Color $ColorCyan -Important
Write-Analytics "MONITORING COMPLETE" -Color $ColorCyan -Important
Write-Analytics "════════════════════════════════════════════════════════════════" -Color $ColorCyan -Important