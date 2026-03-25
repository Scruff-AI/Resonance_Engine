# Simple 256x256 @ 80W test
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "256x256 @ 80W HARMONIC TEST" -ForegroundColor Cyan
Write-Host "Baseline coherence check" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$baseDir = "D:\openclaw-local\workspace-main"
$testDir = "$baseDir\test_256x256"
$sourceDir = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src"

# Signal directory
$signalDir = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain-build\gpu_clock_signal"
$requestFile = "$signalDir\request.json"

# Ensure signal directory exists
if (-not (Test-Path $signalDir)) {
    New-Item -ItemType Directory -Path $signalDir -Force | Out-Null
}

Write-Host "`n1. Setting power limit to 80W..." -ForegroundColor Yellow

$powerRequest = @{
    timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.ffffff"
    command = "pl"
    parameters = @{watts = 80}
    status = "pending"
} | ConvertTo-Json

$powerRequest | Out-File -FilePath $requestFile -Encoding ASCII -Force
Start-Sleep -Seconds 3

# Verify
$powerInfo = nvidia-smi -q -d POWER 2>&1
$currentLimit = ($powerInfo | Select-String "Current Power Limit").ToString() -replace '.*Current Power Limit\s*:\s*(\d+\.\d+).*', '$1'
Write-Host "   Current limit: $currentLimit W" -ForegroundColor Gray

Write-Host "`n2. Running 256x256 test (50k steps)..." -ForegroundColor Yellow

# Check if compiled
$exePath = "$testDir\fractal_habit_256x256.exe"
if (-not (Test-Path $exePath)) {
    Write-Host "   ❌ Executable not found" -ForegroundColor Red
    exit 1
}

# Prepare brain state
$buildDir = "$testDir\build"
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

# Run test
$outputFile = "$testDir\output_256x256_80W.log"
$runCmd = "cd /d `"$testDir`" && fractal_habit_256x256.exe"

Write-Host "   Starting 50k steps..." -ForegroundColor Gray
$process = Start-Process cmd -ArgumentList "/c $runCmd" -NoNewWindow -PassThru -RedirectStandardOutput $outputFile

# Wait for completion
$timeout = 90
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

Write-Host "`n3. Results:" -ForegroundColor Yellow

if (Test-Path $outputFile) {
    $content = Get-Content $outputFile -Raw
    
    # Show key lines
    $lines = $content -split "`n"
    $relevantLines = $lines | Where-Object { $_ -match 'sl=|Ev=|W$' }
    
    Write-Host "   Key metrics:" -ForegroundColor Gray
    $relevantLines | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
    
    # Extract and analyze
    $slopeMatch = [regex]::Match($content, 'sl=([-\d.]+)')
    $powerMatch = [regex]::Match($content, '\| ([\d.]+)W')
    $energyMatch = [regex]::Match($content, 'Ev=([\d.e+-]+)')
    
    $slope = if ($slopeMatch.Success) { [float]$slopeMatch.Groups[1].Value } else { $null }
    $power = if ($powerMatch.Success) { [float]$powerMatch.Groups[1].Value } else { $null }
    $energy = if ($energyMatch.Success) { [float]$energyMatch.Groups[1].Value } else { $null }
    
    Write-Host "`n   Analysis:" -ForegroundColor Cyan
    
    if ($slope -ne $null) {
        if ($slope -lt -2.0) {
            Write-Host "   ✅ COHERENT: sl=$slope (steep spectrum)" -ForegroundColor Green
        } elseif ($slope -gt -0.5) {
            Write-Host "   ❌ NOISE: sl=$slope (white noise)" -ForegroundColor Red
        } else {
            Write-Host "   ⚠️  TRANSITIONAL: sl=$slope" -ForegroundColor Yellow
        }
    }
    
    if ($power -ne $null) {
        Write-Host "   Power: $power W" -ForegroundColor Gray
        if ($power -lt 100) {
            Write-Host "   ⚡ Low power operation achieved" -ForegroundColor Green
        }
    }
    
    if ($energy -ne $null) {
        Write-Host "   Energy: $energy" -ForegroundColor Gray
    }
    
    # Look for "inexplicable energy rises" - check if energy increases
    $energyLines = $lines | Where-Object { $_ -match 'Ev=' } | ForEach-Object {
        if ($_ -match 'Ev=([\d.e+-]+)') { [float]$matches[1] }
    }
    
    if ($energyLines.Count -ge 2) {
        $energyChange = ($energyLines[-1] - $energyLines[0]) / $energyLines[0]
        if ($energyChange -gt 0.1) {
            Write-Host "   📈 SIGNIFICANT ENERGY RISE: $([math]::Round($energyChange * 100, 1))%" -ForegroundColor Cyan
            Write-Host "   Possible harmonic synergy detected!" -ForegroundColor Cyan
        } elseif ($energyChange -gt 0) {
            Write-Host "   ↗️  Energy maintained or slightly increased" -ForegroundColor Green
        }
    }
}

# Reset to 150W
Write-Host "`n4. Resetting to 150W..." -ForegroundColor Yellow
$resetRequest = @{
    timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.ffffff"
    command = "pl"
    parameters = @{watts = 150}
    status = "pending"
} | ConvertTo-Json

$resetRequest | Out-File -FilePath $requestFile -Encoding ASCII -Force
Start-Sleep -Seconds 3

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "TEST COMPLETE" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan

Write-Host "`nOutput file: $outputFile" -ForegroundColor Gray