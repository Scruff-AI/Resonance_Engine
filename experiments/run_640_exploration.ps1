# Explore 640x640 with different power caps
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "EXPLORATION: 640x640 Response Surface" -ForegroundColor Cyan
Write-Host "Testing different power constraints" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$baseDir = "D:\openclaw-local\workspace-main"
$experimentDir = "$baseDir\exploration_640x640"
$sourceDir = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src"

# Power caps to test
$powerCaps = @(120, 150, 180)

# Signal directory for GPU control
$signalDir = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain-build\gpu_clock_signal"
$requestFile = "$signalDir\request.json"

# Create experiment directory
if (-not (Test-Path $experimentDir)) {
    New-Item -ItemType Directory -Path $experimentDir -Force | Out-Null
}

Write-Host "`n1. Compiling 640x640 version..." -ForegroundColor Yellow

$gridDir = "$experimentDir\640x640"
if (-not (Test-Path $gridDir)) {
    New-Item -ItemType Directory -Path $gridDir -Force | Out-Null
}

# Read and modify source for 100k steps
$sourceFile = "$sourceDir\fractal_habit.cu"
$sourceContent = Get-Content $sourceFile -Raw

$modifiedContent = $sourceContent
$modifiedContent = $modifiedContent -replace '#define NX\s+1024', '#define NX    640'
$modifiedContent = $modifiedContent -replace '#define NY\s+1024', '#define NY    640'
$modifiedContent = $modifiedContent -replace '#define TOTAL_STEPS\s+10000000', '#define TOTAL_STEPS      100000'
$modifiedContent = $modifiedContent -replace '10M steps', '100k steps'
$modifiedContent = $modifiedContent -replace 'Steps:     10000000', 'Steps:       100000'

$modifiedFile = "$gridDir\fractal_habit_640x640.cu"
$modifiedContent | Out-File -FilePath $modifiedFile -Encoding ASCII

# Compile
Write-Host "   Compiling..." -ForegroundColor Gray

$compileCmd = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" > nul 2>&1
cd /d "{0}"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 fractal_habit_640x640.cu -o fractal_habit_640x640.exe -lnvml -lcufft
echo Exit code: %errorlevel%
'@ -f $gridDir

$batchFile = "$gridDir\compile.bat"
$compileCmd | Out-File -FilePath $batchFile -Encoding ASCII

$result = cmd /c "`"$batchFile`" 2>&1"
Remove-Item $batchFile -Force

if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ Compiled successfully" -ForegroundColor Green
} else {
    Write-Host "   ❌ Compilation failed" -ForegroundColor Red
    $result
    exit 1
}

# Prepare brain state
$buildDir = "$gridDir\build"
if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
}

$brainStateSource = "D:\openclaw-local\workspace-main\harmonic_brain_states\build_640x640\f_state_post_relax.bin"
$brainStateDest = "$buildDir\f_state_post_relax.bin"

if (Test-Path $brainStateSource) {
    Copy-Item $brainStateSource $brainStateDest -Force
    $size = (Get-Item $brainStateDest).Length
    Write-Host "   Brain state: $([math]::Round($size/1MB,2)) MB" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  Using placeholder brain state" -ForegroundColor Yellow
    "" | Out-File -FilePath $brainStateDest -Encoding ASCII
}

# Run experiments with different power caps
Write-Host "`n2. Running exploration tests..." -ForegroundColor Yellow
Write-Host "   Testing power caps: $($powerCaps -join 'W, ')W" -ForegroundColor Gray

$results = @()

foreach ($powerCap in $powerCaps) {
    Write-Host "`n   --- Testing $powerCap W ---" -ForegroundColor Cyan
    
    # Set power cap
    Write-Host "   Setting power limit to $powerCap W..." -ForegroundColor Gray
    
    $powerRequest = @{
        timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.ffffff"
        command = "pl"
        parameters = @{watts = $powerCap}
        status = "pending"
    } | ConvertTo-Json
    
    if (-not (Test-Path $signalDir)) {
        New-Item -ItemType Directory -Path $signalDir -Force | Out-Null
    }
    
    $powerRequest | Out-File -FilePath $requestFile -Encoding ASCII -Force
    Start-Sleep -Seconds 2  # Wait for service to process
    
    # Verify
    $powerInfo = nvidia-smi -q -d POWER 2>&1
    $currentLimit = ($powerInfo | Select-String "Current Power Limit").ToString() -replace '.*Current Power Limit\s*:\s*(\d+\.\d+).*', '$1'
    Write-Host "   Current limit: $currentLimit W" -ForegroundColor Gray
    
    # Run experiment
    $outputFile = "$gridDir\output_640x640_${powerCap}W.log"
    $runCmd = "cd /d `"$gridDir`" && fractal_habit_640x640.exe"
    
    Write-Host "   Running 100k steps..." -ForegroundColor Gray
    $process = Start-Process cmd -ArgumentList "/c $runCmd" -NoNewWindow -PassThru -RedirectStandardOutput $outputFile
    
    # Wait for completion (100k steps ~ 60 seconds)
    $timeout = 90  # seconds
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
        
        # Extract spectral slope
        $slopeMatch = [regex]::Match($content, 'sl=([-\d.]+)')
        $powerMatch = [regex]::Match($content, '\| ([\d.]+)W')
        
        $slope = if ($slopeMatch.Success) { $slopeMatch.Groups[1].Value } else { "N/A" }
        $power = if ($powerMatch.Success) { $powerMatch.Groups[1].Value } else { "N/A" }
        
        $result = [PSCustomObject]@{
            PowerCap = $powerCap
            ActualPower = $power
            SpectralSlope = $slope
            Status = if ($completed) { "Completed" } else { "Timeout" }
        }
        
        $results += $result
        
        Write-Host "   Results: sl=$slope, power=$power W" -ForegroundColor Green
    }
}

# Reset to 150W for consistency
Write-Host "`n3. Resetting to 150W..." -ForegroundColor Yellow
$resetRequest = @{
    timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.ffffff"
    command = "pl"
    parameters = @{watts = 150}
    status = "pending"
} | ConvertTo-Json

$resetRequest | Out-File -FilePath $requestFile -Encoding ASCII -Force
Start-Sleep -Seconds 2

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "EXPLORATION RESULTS: 640x640" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan

$results | Format-Table -AutoSize

Write-Host "`nAnalysis:" -ForegroundColor Yellow

# Check for coherence
$coherentResults = $results | Where-Object { $_.SpectralSlope -ne "N/A" -and [float]$_.SpectralSlope -lt -2.0 }
if ($coherentResults.Count -gt 0) {
    Write-Host "   ✅ 640x640 shows coherence at some power levels" -ForegroundColor Green
    $best = $coherentResults | Sort-Object { [math]::Abs([float]$_.SpectralSlope + 2.5) } | Select-Object -First 1
    Write-Host "   Best: $($best.PowerCap)W gives sl=$($best.SpectralSlope)" -ForegroundColor Green
} else {
    Write-Host "   ❌ 640x640 may be too small (no coherence)" -ForegroundColor Red
}

Write-Host "`nNext: Compare with 768x768 and 896x896 results" -ForegroundColor Cyan