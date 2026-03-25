# Comprehensive 256x256 @ 80W Parameter Sweep
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "256x256 @ 80W HARMONIC SYNERGY SEARCH" -ForegroundColor Cyan
Write-Host "Looking for 'inexplicable energy rises'" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$baseDir = "D:\openclaw-local\workspace-main"
$experimentDir = "$baseDir\harmonic_synergy_256x256"
$sourceDir = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src"

# Create experiment directory
if (-not (Test-Path $experimentDir)) {
    New-Item -ItemType Directory -Path $experimentDir -Force | Out-Null
}

# Parameter space to explore
$guardianCounts = @(8, 12, 16)  # Scaled from 194: 12 is proper scaling
$rhoThresholds = @(0.8, 0.9, 1.0, 1.1, 1.2)
$powerCaps = @(60, 80, 100)  # 80W target, explore around it
$testDuration = 50000  # steps per test

Write-Host "`nPARAMETER SPACE:" -ForegroundColor Yellow
Write-Host "  Guardian counts: $($guardianCounts -join ', ')" -ForegroundColor Gray
Write-Host "  Rho thresholds: $($rhoThresholds -join ', ')" -ForegroundColor Gray
Write-Host "  Power caps: $($powerCaps -join 'W, ')W" -ForegroundColor Gray
Write-Host "  Tests per combination: $testDuration steps" -ForegroundColor Gray
Write-Host "  Total combinations: $($guardianCounts.Count * $rhoThresholds.Count * $powerCaps.Count)" -ForegroundColor Gray

# Signal directory for GPU control
$signalDir = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain-build\gpu_clock_signal"
$requestFile = "$signalDir\request.json"

# Ensure signal directory exists
if (-not (Test-Path $signalDir)) {
    New-Item -ItemType Directory -Path $signalDir -Force | Out-Null
}

# Results collection
$allResults = @()

# We'll need to handle guardian parameter scaling
# For now, we'll test with fractal_habit (fluid only) and monitor what we can
# Later we can integrate precipitation modifications

Write-Host "`n1. Setting up baseline 256x256..." -ForegroundColor Yellow

$gridDir = "$experimentDir\256x256_baseline"
if (-not (Test-Path $gridDir)) {
    New-Item -ItemType Directory -Path $gridDir -Force | Out-Null
}

# Check if already compiled
$exePath = "$gridDir\fractal_habit_256x256.exe"
if (-not (Test-Path $exePath)) {
    # Read and modify source
    $sourceFile = "$sourceDir\fractal_habit.cu"
    $sourceContent = Get-Content $sourceFile -Raw
    
    $modifiedContent = $sourceContent
    $modifiedContent = $modifiedContent -replace '#define NX\s+1024', '#define NX    256'
    $modifiedContent = $modifiedContent -replace '#define NY\s+1024', '#define NY    256'
    $modifiedContent = $modifiedContent -replace '#define TOTAL_STEPS\s+10000000', "#define TOTAL_STEPS      $testDuration"
    $modifiedContent = $modifiedContent -replace '10M steps', "$($testDuration/1000)k steps"
    $modifiedContent = $modifiedContent -replace 'Steps:     10000000', "Steps:       $testDuration"
    
    $modifiedFile = "$gridDir\fractal_habit_256x256.cu"
    $modifiedContent | Out-File -FilePath $modifiedFile -Encoding ASCII
    
    # Compile
    Write-Host "   Compiling baseline..." -ForegroundColor Gray
    
    $compileCmd = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" > nul 2>&1
cd /d "{0}"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 fractal_habit_256x256.cu -o fractal_habit_256x256.exe -lnvml -lcufft
echo Exit code: %errorlevel%
'@ -f $gridDir
    
    $batchFile = "$gridDir\compile.bat"
    $compileCmd | Out-File -FilePath $batchFile -Encoding ASCII
    
    $result = cmd /c "`"$batchFile`" 2>&1"
    Remove-Item $batchFile -Force
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ Baseline compiled" -ForegroundColor Green
    } else {
        Write-Host "   ❌ Compilation failed" -ForegroundColor Red
        $result
        exit 1
    }
} else {
    Write-Host "   ✅ Baseline already compiled" -ForegroundColor Green
}

# Prepare brain state
$buildDir = "$gridDir\build"
if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
}

$brainStateSource = "D:\openclaw-local\workspace-main\harmonic_brain_states\build_256x256\f_state_post_relax.bin"
$brainStateDest = "$buildDir\f_state_post_relax.bin"

if (Test-Path $brainStateSource) {
    Copy-Item $brainStateSource $brainStateDest -Force
    $size = (Get-Item $brainStateDest).Length
    Write-Host "   Brain state: $([math]::Round($size/1MB,2)) MB" -ForegroundColor Green
} else {
    Write-Host "   ❌ Brain state not found" -ForegroundColor Red
    exit 1
}

Write-Host "`n2. Running parameter sweep..." -ForegroundColor Yellow
Write-Host "   Looking for harmonic synergy at 80W" -ForegroundColor Gray
Write-Host "   Monitoring for 'inexplicable energy rises'" -ForegroundColor Gray

$testCount = 0
$totalTests = $powerCaps.Count

foreach ($powerCap in $powerCaps) {
    $testCount++
    Write-Host "`n   --- Test $testCount/$totalTests: $powerCap W ---" -ForegroundColor Cyan
    
    # Set power cap
    Write-Host "   Setting power limit to $powerCap W..." -ForegroundColor Gray
    
    $powerRequest = @{
        timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.ffffff"
        command = "pl"
        parameters = @{watts = $powerCap}
        status = "pending"
    } | ConvertTo-Json
    
    $powerRequest | Out-File -FilePath $requestFile -Encoding ASCII -Force
    Start-Sleep -Seconds 3  # Wait for service
    
    # Verify power limit
    $powerInfo = nvidia-smi -q -d POWER 2>&1
    $currentLimit = ($powerInfo | Select-String "Current Power Limit").ToString() -replace '.*Current Power Limit\s*:\s*(\d+\.\d+).*', '$1'
    Write-Host "   Current limit: $currentLimit W" -ForegroundColor Gray
    
    # Run experiment
    $outputFile = "$gridDir\output_256x256_${powerCap}W.log"
    $runCmd = "cd /d `"$gridDir`" && fractal_habit_256x256.exe"
    
    Write-Host "   Running $testDuration steps..." -ForegroundColor Gray
    $process = Start-Process cmd -ArgumentList "/c $runCmd" -NoNewWindow -PassThru -RedirectStandardOutput $outputFile
    
    # Wait for completion
    $timeout = 120  # seconds (generous)
    $startTime = Get-Date
    $completed = $false
    
    while (((Get-Date) - $startTime).TotalSeconds -lt $timeout) {
        if ($process.HasExited) {
            $completed = $true
            break
        }
        Start-Sleep -Seconds 5
    }
    
    if (-not $completed) {
        Write-Host "   ⚠️  Timeout - killing process" -ForegroundColor Yellow
        $process.Kill()
        Start-Sleep -Seconds 2
    }
    
    # Extract results
    if (Test-Path $outputFile) {
        $content = Get-Content $outputFile -Raw
        
        # Extract key metrics
        $slopeMatch = [regex]::Match($content, 'sl=([-\d.]+)')
        $powerMatch = [regex]::Match($content, '\| ([\d.]+)W')
        $energyMatch = [regex]::Match($content, 'Ev=([\d.e+-]+)')
        $entropyMatch = [regex]::Match($content, 'H=([\d.]+)')
        
        $slope = if ($slopeMatch.Success) { [float]$slopeMatch.Groups[1].Value } else { $null }
        $power = if ($powerMatch.Success) { [float]$powerMatch.Groups[1].Value } else { $null }
        $energy = if ($energyMatch.Success) { [float]$energyMatch.Groups[1].Value } else { $null }
        $entropy = if ($entropyMatch.Success) { [float]$entropyMatch.Groups[1].Value } else { $null }
        
        # Calculate efficiency metric
        $efficiency = if ($power -and $energy) { $energy / $power } else { $null }
        
        $result = [PSCustomObject]@{
            PowerCap = $powerCap
            ActualPower = $power
            SpectralSlope = $slope
            Energy = $energy
            Entropy = $entropy
            Efficiency = $efficiency
            Status = if ($completed) { "Completed" } else { "Timeout" }
            File = $outputFile
        }
        
        $allResults += $result
        
        # Quick analysis
        if ($slope -ne $null) {
            if ($slope -lt -2.0) {
                Write-Host "   ✅ COHERENT (sl=$slope)" -ForegroundColor Green
            } elseif ($slope -gt -0.5) {
                Write-Host "   ❌ NOISE (sl=$slope)" -ForegroundColor Red
            } else {
                Write-Host "   ⚠️  TRANSITIONAL (sl=$slope)" -ForegroundColor Yellow
            }
        }
        
        Write-Host "   Power: $power W, Energy: $energy, Entropy: $entropy" -ForegroundColor Gray
    }
}

# Reset to 150W for safety
Write-Host "`n3. Resetting to 150W..." -ForegroundColor Yellow
$resetRequest = @{
    timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.ffffff"
    command = "pl"
    parameters = @{watts = 150}
    status = "pending"
} | ConvertTo-Json

$resetRequest | Out-File -FilePath $requestFile -Encoding ASCII -Force
Start-Sleep -Seconds 3

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "PARAMETER SWEEP RESULTS" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan

# Display results
$allResults | Format-Table -Property PowerCap, ActualPower, SpectralSlope, Energy, Efficiency, Status -AutoSize

Write-Host "`nANALYSIS:" -ForegroundColor Yellow

# Look for "inexplicable energy rises"
$coherentResults = $allResults | Where-Object { $_.SpectralSlope -ne $null -and $_.SpectralSlope -lt -2.0 }
if ($coherentResults.Count -gt 0) {
    Write-Host "   ✅ Found coherent runs" -ForegroundColor Green
    
    # Find most efficient
    $mostEfficient = $coherentResults | Sort-Object Efficiency -Descending | Select-Object -First 1
    Write-Host "   Most efficient: $($mostEfficient.PowerCap)W → sl=$($mostEfficient.SpectralSlope), eff=$($mostEfficient.Efficiency)" -ForegroundColor Green
    
    # Check for energy rises
    $energyTrend = $coherentResults | Sort-Object PowerCap | ForEach-Object { $_.Energy }
    if ($energyTrend.Count -ge 2) {
        $energyChange = ($energyTrend[-1] - $energyTrend[0]) / $energyTrend[0]
        if ($energyChange -gt 0) {
            Write-Host "   📈 Energy INCREASE detected: $([math]::Round($energyChange * 100, 1))%" -ForegroundColor Cyan
        }
    }
} else {
    Write-Host "   ❌ No coherent runs found" -ForegroundColor Red
}

# Check power efficiency
$powerEfficiency = $allResults | Where-Object { $_.ActualPower -ne $null -and $_.ActualPower -lt 100 }
if ($powerEfficiency.Count -gt 0) {
    Write-Host "   ⚡ Low power achieved: $([math]::Round(($powerEfficiency | Measure-Object ActualPower -Minimum).Minimum, 1))W" -ForegroundColor Green
}

Write-Host "`nNEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Analyze detailed spectra for standing wave patterns" -ForegroundColor White
Write-Host "2. Modify precipitation.cu for guardian parameter testing" -ForegroundColor White
Write-Host "3. Test guardian count variations" -ForegroundColor White
Write-Host "4. Look for octave relationships in spectral data" -ForegroundColor White

Write-Host "`nData files in: $gridDir" -ForegroundColor Gray