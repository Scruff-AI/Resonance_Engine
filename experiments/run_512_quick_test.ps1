# Quick test of 512x512 at 150W
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "FINAL TEST: 512x512 at 150W" -ForegroundColor Cyan
Write-Host "Completing the pattern" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$baseDir = "D:\openclaw-local\workspace-main"
$gridDir = "$baseDir\harmonic_scan_sequential\512x512"
$sourceDir = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src"

if (-not (Test-Path $gridDir)) {
    New-Item -ItemType Directory -Path $gridDir -Force | Out-Null
}

Write-Host "`n1. Compiling 512x512 (50k steps)..." -ForegroundColor Yellow

# Check if already compiled
$exePath = "$gridDir\fractal_habit_512x512.exe"
if (-not (Test-Path $exePath)) {
    # Read and modify source
    $sourceFile = "$sourceDir\fractal_habit.cu"
    $sourceContent = Get-Content $sourceFile -Raw
    
    $modifiedContent = $sourceContent
    $modifiedContent = $modifiedContent -replace '#define NX\s+1024', '#define NX    512'
    $modifiedContent = $modifiedContent -replace '#define NY\s+1024', '#define NY    512'
    $modifiedContent = $modifiedContent -replace '#define TOTAL_STEPS\s+10000000', '#define TOTAL_STEPS      50000'
    $modifiedContent = $modifiedContent -replace '10M steps', '50k steps'
    $modifiedContent = $modifiedContent -replace 'Steps:     10000000', 'Steps:        50000'
    
    $modifiedFile = "$gridDir\fractal_habit_512x512.cu"
    $modifiedContent | Out-File -FilePath $modifiedFile -Encoding ASCII
    
    # Compile
    $compileCmd = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" > nul 2>&1
cd /d "{0}"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 fractal_habit_512x512.cu -o fractal_habit_512x512.exe -lnvml -lcufft
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
} else {
    Write-Host "   ✅ Already compiled" -ForegroundColor Green
}

# Prepare brain state
$buildDir = "$gridDir\build"
if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
}

$brainStateSource = "D:\openclaw-local\workspace-main\harmonic_brain_states\build_512x512\f_state_post_relax.bin"
$brainStateDest = "$buildDir\f_state_post_relax.bin"

if (Test-Path $brainStateSource) {
    Copy-Item $brainStateSource $brainStateDest -Force
    $size = (Get-Item $brainStateDest).Length
    Write-Host "   Brain state: $([math]::Round($size/1MB,2)) MB" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  Creating placeholder brain state" -ForegroundColor Yellow
    "" | Out-File -FilePath $brainStateDest -Encoding ASCII
}

# Run test
Write-Host "`n2. Running 512x512 at 150W..." -ForegroundColor Yellow
Write-Host "   Expected time: 30 seconds" -ForegroundColor Gray

$outputFile = "$gridDir\output_512x512.log"
$runCmd = "cd /d `"$gridDir`" && fractal_habit_512x512.exe"

$process = Start-Process cmd -ArgumentList "/c $runCmd" -NoNewWindow -PassThru -RedirectStandardOutput $outputFile

# Wait for completion
$timeout = 60
$startTime = Get-Date
$completed = $false

while (((Get-Date) - $startTime).TotalSeconds -lt $timeout) {
    if ($process.HasExited) {
        $completed = $true
        break
    }
    Start-Sleep -Seconds 2
}

if (-not $completed) {
    Write-Host "   ⚠️  Timeout - killing process" -ForegroundColor Yellow
    $process.Kill()
}

# Get results
if (Test-Path $outputFile) {
    Write-Host "`n3. Results:" -ForegroundColor Yellow
    
    $content = Get-Content $outputFile -Raw
    
    # Extract key metrics
    $slopeMatch = [regex]::Match($content, 'sl=([-\d.]+)')
    $powerMatch = [regex]::Match($content, '\| ([\d.]+)W')
    
    $slope = if ($slopeMatch.Success) { $slopeMatch.Groups[1].Value } else { "N/A" }
    $power = if ($powerMatch.Success) { $powerMatch.Groups[1].Value } else { "N/A" }
    
    Write-Host "   Power: $power W" -ForegroundColor Gray
    Write-Host "   Spectral slope: $slope" -ForegroundColor Gray
    
    # Determine coherence
    if ($slope -ne "N/A" -and [float]$slope -lt -2.0) {
        Write-Host "   ✅ COHERENT (sl < -2.0)" -ForegroundColor Green
    } elseif ($slope -ne "N/A" -and [float]$slope -gt -0.5) {
        Write-Host "   ❌ NOISE (sl ≈ -0.5)" -ForegroundColor Red
    } else {
        Write-Host "   ⚠️  INDETERMINATE" -ForegroundColor Yellow
    }
}

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "COMPLETE HARMONIC SCAN RESULTS" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan