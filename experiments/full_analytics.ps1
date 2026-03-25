# full_analytics.ps1
# Complete crash analytics for probe_256_final.exe
# Captures cycles, errors, patterns, and analyzes crash at ~1112

$logFile = "crash_analytics_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$csvFile = "cycles_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$errorFile = "errors_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Initialize data structures
$cycles = @()
$errors = @()
$patterns = @()
$startTime = Get-Date

# ANSI colors
$Red = "`e[31m"
$Green = "`e[32m"
$Yellow = "`e[33m"
$Blue = "`e[34m"
$Magenta = "`e[35m"
$Cyan = "`e[36m"
$Reset = "`e[0m"

function Log-Message {
    param($Message, $Color = $Reset, [switch]$Important)
    
    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    $logEntry = "[$timestamp] $Message"
    
    if ($Important) {
        Write-Host "$Color`n════════════════════════════════════════════════════════════════`n" -NoNewline
        Write-Host "$Color$logEntry$Reset" -NoNewline
        Write-Host "$Color`n════════════════════════════════════════════════════════════════`n$Reset"
    } else {
        Write-Host "$Color$logEntry$Reset"
    }
    
    Add-Content -Path $logFile -Value $logEntry
}

function Parse-Cycle {
    param($Line)
    
    # Full pattern: " 1112 | 0:30:01 | 1.2500 | 8.958159e-08 | [1.00030,1.00030] | 4.782e-12 |   13 |     6.08 |    65561.88 | SILENT"
    $pattern = '^\s*(\d+)\s*\|\s*(\d+:\d+:\d+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.e\+\-]+)\s*\|\s*\[([\d\.]+),([\d\.]+)\]\s*\|\s*([\d\.e\+\-]+)\s*\|\s*(\d+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.]+)\s*\|\s*(\w+)'
    
    if ($Line -match $pattern) {
        return [PSCustomObject]@{
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
            Timestamp = Get-Date
            RawLine = $Line
        }
    }
    return $null
}

function Detect-Patterns {
    param($Cycle)
    
    $detected = @()
    
    # SILENT probe patterns
    if ($Cycle.Probe -eq "SILENT") {
        if ([math]::Abs($Cycle.Omega - 1.25) -lt 0.001) {
            $detected += "OMEGA_LOCKED_1.25"
        }
        
        if ($Cycle.Omega -lt 0.6 -or $Cycle.Omega -gt 1.95) {
            $detected += "OMEGA_OUT_OF_RANGE"
        }
    }
    
    # Guardian patterns
    if ($cycles.Count -gt 1) {
        $prev = $cycles[-1]
        if ($Cycle.Guardians -ne $prev.Guardians) {
            $detected += "GUARDIAN_COUNT_CHANGED"
        }
        
        if ($Cycle.Mass - $prev.Mass -gt 10) {
            $detected += "MASS_SPIKE"
        }
    }
    
    # Power patterns
    if ($Cycle.Power -match 'e' -and [double]$Cycle.Power -gt 1e-5) {
        $detected += "POWER_SPIKE"
    }
    
    # Density patterns
    if ($Cycle.RhoMax - $Cycle.RhoMin -gt 0.1) {
        $detected += "DENSITY_GRADIENT_HIGH"
    }
    
    return $detected
}

function Show-Status {
    Clear-Host
    Write-Host "$Cyan╔══════════════════════════════════════════════════════════════╗$Reset"
    Write-Host "$Cyan║                FULL CRASH ANALYTICS - LIVE                  ║$Reset"
    Write-Host "$Cyan╠══════════════════════════════════════════════════════════════╣$Reset"
    
    $runtime = (Get-Date) - $startTime
    $runtimeStr = "{0:hh\:mm\:ss}" -f $runtime
    
    if ($cycles.Count -gt 0) {
        $latest = $cycles[-1]
        Write-Host "$Green║  CYCLE: $($latest.Cycle.ToString().PadLeft(4)) | TIME: $runtimeStr | PROBE: $($latest.Probe.PadRight(6)) ║$Reset"
        Write-Host "$Green║  OMEGA: $($latest.Omega.ToString("F4").PadLeft(6)) | GUARDIANS: $($latest.Guardians.ToString().PadLeft(2)) | MASS: $($latest.Mass.ToString("F2").PadLeft(6)) ║$Reset"
        
        # Crash zone warning
        if ($latest.Cycle -ge 1100 -and $latest.Cycle -le 1199) {
            Write-Host "$Red║  ⚠️  CRASH ZONE: SILENT probe (omega locked 1.25)              ║$Reset"
            Write-Host "$Red║  Expected crash: cycle ~1112                                 ║$Reset"
        } elseif ($latest.Cycle -lt 1100) {
            $remaining = 1100 - $latest.Cycle
            Write-Host "$Yellow║  Cycles to crash zone: $remaining                                    ║$Reset"
        } else {
            Write-Host "$Green║  ✅ PASSED CRASH ZONE                                    ║$Reset"
        }
    } else {
        Write-Host "$Yellow║  Waiting for first cycle...                                ║$Reset"
    }
    
    Write-Host "$Cyan╠══════════════════════════════════════════════════════════════╣$Reset"
    
    # Recent patterns
    if ($patterns.Count -gt 0) {
        Write-Host "$Magenta║  RECENT PATTERNS:                                            ║$Reset"
        $recent = $patterns | Select-Object -Last 3
        foreach ($p in $recent) {
            Write-Host "$Magenta║    • $($p.PadRight(54)) ║$Reset"
        }
    }
    
    # Error count
    if ($errors.Count -gt 0) {
        Write-Host "$Red║  ERRORS: $($errors.Count) detected                                ║$Reset"
    }
    
    Write-Host "$Cyan╚══════════════════════════════════════════════════════════════╝$Reset"
}

function Analyze-Crash {
    param($ExitCode, $LastCycle)
    
    Log-Message "════════════════════════════════════════════════════════════════" -Color $Red -Important
    Log-Message "💥 CRASH ANALYSIS COMPLETE" -Color $Red -Important
    Log-Message "════════════════════════════════════════════════════════════════" -Color $Red -Important
    
    $runtime = (Get-Date) - $startTime
    $runtimeStr = "{0:hh\:mm\:ss}" -f $runtime
    
    Log-Message "Runtime: $runtimeStr" -Color $Yellow
    Log-Message "Last cycle: $LastCycle" -Color $Yellow
    Log-Message "Exit code: $ExitCode" -Color $Yellow
    
    if ($cycles.Count -gt 0) {
        $lastProbe = $cycles[-1].Probe
        Log-Message "Last probe: $lastProbe" -Color $Yellow
    }
    
    # SILENT probe crash analysis
    if ($ExitCode -eq 1 -and $LastCycle -ge 1100 -and $LastCycle -le 1199) {
        Log-Message "🔍 CONFIRMED: SILENT PROBE CRASH" -Color $Red
        Log-Message "   Crash at cycle $LastCycle (12 cycles into SILENT probe)" -Color $Yellow
        Log-Message "   Omega locked at 1.25 for 100 cycles (1100-1199)" -Color $Yellow
        
        Log-Message "`n📊 PRE-CRASH ANALYSIS:" -Color $Cyan
        
        # Last 5 cycles before crash
        $lastCycles = $cycles | Where-Object { $_.Cycle -ge $LastCycle - 5 } | Select-Object -Last 10
        foreach ($c in $lastCycles) {
            Log-Message "   Cycle $($c.Cycle): Omega=$($c.Omega) Guardians=$($c.Guardians) Mass=$($c.Mass)" -Color $Yellow
        }
        
        # Omega analysis
        $silentCycles = $cycles | Where-Object { $_.Probe -eq "SILENT" }
        if ($silentCycles.Count -gt 0) {
            $omegaAvg = ($silentCycles | Measure-Object -Property Omega -Average).Average
            $omegaMin = ($silentCycles | Measure-Object -Property Omega -Minimum).Minimum
            $omegaMax = ($silentCycles | Measure-Object -Property Omega -Maximum).Maximum
            
            Log-Message "`n📈 OMEGA DURING SILENT PROBE:" -Color $Cyan
            Log-Message "   Average: $($omegaAvg.ToString("F4"))" -Color $Yellow
            Log-Message "   Range: $($omegaMin.ToString("F4")) to $($omegaMax.ToString("F4"))" -Color $Yellow
            Log-Message "   Target: 1.2500 (locked)" -Color $Yellow
        }
        
        Log-Message "`n🔧 ROOT CAUSE HYPOTHESES:" -Color $Red
        Log-Message "   1. Numerical instability at exact omega=1.25" -Color $Yellow
        Log-Message "   2. GPU memory corruption after 100 cycles of fixed omega" -Color $Yellow
        Log-Message "   3. CUDA kernel divergence with constant parameters" -Color $Yellow
        Log-Message "   4. Buffer overflow in VRM silence logic" -Color $Yellow
        
        Log-Message "`n🛠️ RECOMMENDED FIXES:" -Color $Green
        Log-Message "   1. Remove omega locking in SILENT probe" -Color $Yellow
        Log-Message "   2. Add small noise to omega (1.25 ± 0.001)" -Color $Yellow
        Log-Message "   3. Skip SILENT probe entirely" -Color $Yellow
        Log-Message "   4. Use fractal_habit_256.exe (no probes)" -Color $Yellow
        
    } elseif ($ExitCode -eq 0) {
        Log-Message "✅ CLEAN EXIT - NO CRASH" -Color $Green
        Log-Message "   Program completed all 1700 cycles successfully" -Color $Yellow
    }
    
    # Save all data
    $cycles | Export-Csv -Path $csvFile -NoTypeInformation
    $errors | Out-File -FilePath $errorFile
    
    Log-Message "`n📁 DATA SAVED:" -Color $Cyan
    Log-Message "   Cycle data: $csvFile" -Color $Yellow
    Log-Message "   Error log: $errorFile" -Color $Yellow
    Log-Message "   Full log: $logFile" -Color $Yellow
}

# Main execution
Log-Message "════════════════════════════════════════════════════════════════" -Color $Cyan -Important
Log-Message "🚀 FULL CRASH ANALYTICS STARTING" -Color $Cyan -Important
Log-Message "Monitoring: probe_256_final.exe" -Color $Cyan
Log-Message "Target: Capture crash at cycle ~1112 (SILENT probe)" -Color $Cyan
Log-Message "Data files: $csvFile, $errorFile, $logFile" -Color $Cyan
Log-Message "════════════════════════════════════════════════════════════════" -Color $Cyan -Important

# Start process
$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = ".\probe_256_final.exe"
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.UseShellExecute = $false
$processInfo.CreateNoWindow = $true

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $processInfo

try {
    $process.Start() | Out-Null
    Log-Message "Process started (PID: $($process.Id))" -Color $Green
    
    $stdout = $process.StandardOutput
    $stderr = $process.StandardError
    
    # Initial status
    Show-Status
    
    # Monitor loop
    while (!$process.HasExited) {
        # Read stdout
        if (!$stdout.EndOfStream) {
            $line = $stdout.ReadLine()
            
            # Parse cycle
            $cycle = Parse-Cycle $line
            if ($cycle) {
                $cycles += $cycle
                
                # Detect patterns
                $detected = Detect-Patterns $cycle
                if ($detected.Count -gt 0) {
                    foreach ($pattern in $detected) {
                        $patterns += "$pattern at cycle $($cycle.Cycle)"
                        Log-Message "Pattern: $pattern at cycle $($cycle.Cycle)" -Color $Magenta
                    }
                }
                
                # Update status every 10 cycles
                if ($cycle.Cycle % 10 -eq 0) {
                    Show-Status
                }
                
                # Special warnings
                if ($cycle.Cycle -ge 1100 -and $cycle.Cycle -le 1199 -and $cycle.Probe -eq "SILENT") {
                    Log-Message "🚨 CRASH ZONE: Cycle $($cycle.Cycle) | Omega locked at $($cycle.Omega)" -Color $Red
                }
            }
            
            # Check for errors in output
            if ($line -match 'error|Error|ERROR|exception|Exception|EXCEPTION|fatal|Fatal|FATAL|segmentation|Segmentation|access violation|Access violation|cudaError|CUDA error|nvmlError|NVML error') {
                $errors += $line
                Log-Message "🔴 ERROR in output: $line" -Color $Red
            }
        }
        
        # Read stderr
        if (!$stderr.EndOfStream) {
            $errorLine = $stderr.ReadLine()
            $errors += $errorLine
            Log-Message "🔴 STDERR: $errorLine" -Color $Red
        }
        
        Start-Sleep -Milliseconds 10
    }
    
    # Process exited
    $exitCode = $process.ExitCode
    $lastCycle = if ($cycles.Count -gt 0) { $cycles[-1].Cycle } else { 0 }
    
    Show-Status
    Analyze-Crash -ExitCode $exitCode -LastCycle $lastCycle
    
} catch {
    Log-Message "❌ ERROR: $_" -Color $Red
} finally {
    if ($process -and !$process.HasExited) {
        $process.Kill()
    }
}

Log-Message "════════════════════════════════════════════════════════════════" -Color $Cyan -Important
Log-Message "ANALYTICS COMPLETE" -Color $Cyan -Important
Log-Message "════════════════════════════════════════════════════════════════" -Color $Cyan -Important