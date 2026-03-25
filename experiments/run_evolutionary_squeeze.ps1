# Evolutionary Squeeze Experimentation Script
# Run each grid size and learn from the results

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "EVOLUTIONARY SQUEEZE EXPERIMENT" -ForegroundColor Cyan
Write-Host "24-Hour Learning Protocol" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Grid sizes and run durations (2 hours each for 24-hour total)
$experiments = @(
    @{Name="768x768"; Exe="fractal_habit_768x768.exe"; BuildDir="build_768x768"; Duration="2:00:00"},
    @{Name="512x512"; Exe="fractal_habit_512x512.exe"; BuildDir="build_512x512"; Duration="2:30:00"},
    @{Name="384x384"; Exe="fractal_habit_384x384.exe"; BuildDir="build_384x384"; Duration="2:30:00"},
    @{Name="256x256"; Exe="fractal_habit_256x256.exe"; BuildDir="build_256x256"; Duration="2:30:00"},
    @{Name="192x192"; Exe="fractal_habit_192x192.exe"; BuildDir="build_192x192"; Duration="2:30:00"}
)

$baseDir = "D:\openclaw-local\workspace-main"
$squeezeDir = "$baseDir\squeeze_versions"
$scaledStatesDir = "$baseDir\scaled_brain_states"

# Create results directory
$resultsDir = "$baseDir\evolutionary_squeeze_results"
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}

# Log file for experiment summary
$logFile = "$resultsDir\experiment_log_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"
"Evolutionary Squeeze Experiment - Started $(Get-Date)" | Out-File -FilePath $logFile -Encoding UTF8
"==================================================" | Out-File -FilePath $logFile -Encoding UTF8 -Append

foreach ($exp in $experiments) {
    Write-Host "`n=== RUNNING: $($exp.Name) ===" -ForegroundColor Yellow
    Write-Host "Duration: $($exp.Duration)" -ForegroundColor Yellow
    
    # Log experiment start
    "`n[$(Get-Date)] Starting $($exp.Name)" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    
    # Create run directory
    $runDir = "$resultsDir\$($exp.Name)"
    if (-not (Test-Path $runDir)) {
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    }
    
    # Copy executable
    $exeSource = "$squeezeDir\$($exp.Name)\$($exp.Exe)"
    $exeDest = "$runDir\$($exp.Exe)"
    if (Test-Path $exeSource) {
        Copy-Item $exeSource $exeDest -Force
        Write-Host "  Copied executable: $($exp.Exe)" -ForegroundColor Green
    } else {
        Write-Host "  ERROR: Executable not found: $exeSource" -ForegroundColor Red
        continue
    }
    
    # Create build directory with brain state
    $buildDir = "$runDir\build"
    if (-not (Test-Path $buildDir)) {
        New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
    }
    
    $stateSource = "$scaledStatesDir\$($exp.BuildDir)\f_state_post_relax.bin"
    $stateDest = "$buildDir\f_state_post_relax.bin"
    if (Test-Path $stateSource) {
        Copy-Item $stateSource $stateDest -Force
        Write-Host "  Copied brain state: $stateDest" -ForegroundColor Green
        "  Brain state: $([math]::Round((Get-Item $stateDest).Length/1MB,2)) MB" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    } else {
        Write-Host "  ERROR: Brain state not found: $stateSource" -ForegroundColor Red
        continue
    }
    
    # Create output files
    $outputFile = "$runDir\output.log"
    $metricsFile = "$runDir\metrics.csv"
    
    # Create header for metrics CSV
    "Step,Time,Ev,Hv,slv,pkv,Er,Hr,slr,kx0,PowerW" | Out-File -FilePath $metricsFile -Encoding UTF8
    
    Write-Host "  Starting execution..." -ForegroundColor Cyan
    
    # Start the process
    $process = Start-Process -FilePath $exeDest -WorkingDirectory $runDir -NoNewWindow -PassThru -RedirectStandardOutput $outputFile
    
    # Log process start
    "  Process ID: $($process.Id)" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    "  Output file: $outputFile" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    
    # Wait for duration (simplified - in real script would monitor)
    Write-Host "  Running for $($exp.Duration)..." -ForegroundColor Cyan
    Write-Host "  (In full implementation, would monitor and capture metrics)" -ForegroundColor Gray
    
    # For now, just note we would run it
    "  Planned duration: $($exp.Duration)" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    
    # In actual implementation:
    # 1. Monitor process output
    # 2. Parse metrics in real-time
    # 3. Capture guardian formation patterns
    # 4. Record power consumption
    # 5. Stop after duration
    
    Write-Host "  [SIMULATION] Would run actual experiment here" -ForegroundColor Gray
    
    # Log completion
    "[$(Get-Date)] Completed $($exp.Name) simulation" | Out-File -FilePath $logFile -Encoding UTF8 -Append
}

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "EXPERIMENT DESIGN COMPLETE" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "`nWhat we would learn from 24-hour experiment:" -ForegroundColor Yellow
Write-Host "1. Natural guardian counts at each grid size" -ForegroundColor White
Write-Host "2. Adaptation patterns under compression" -ForegroundColor White
Write-Host "3. Power scaling with grid size" -ForegroundColor White
Write-Host "4. Entropy evolution under constraints" -ForegroundColor White
Write-Host "5. Coherence metrics for 'harmonious' operation" -ForegroundColor White
Write-Host "`nLog file: $logFile" -ForegroundColor Cyan
Write-Host "Results directory: $resultsDir" -ForegroundColor Cyan