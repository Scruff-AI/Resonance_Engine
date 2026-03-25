# Run 1024x1024 test at 150W
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "EXPERIMENT 1: 1024x1024 at 150W" -ForegroundColor Cyan
Write-Host "Baseline Coherence Test" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$baseDir = "D:\openclaw-local\workspace-main"
$experimentDir = "$baseDir\harmonic_scan_sequential"
$sourceDir = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src"

# Create experiment directory
if (-not (Test-Path $experimentDir)) {
    New-Item -ItemType Directory -Path $experimentDir -Force | Out-Null
}

$gridDir = "$experimentDir\1024x1024"
if (-not (Test-Path $gridDir)) {
    New-Item -ItemType Directory -Path $gridDir -Force | Out-Null
}

Write-Host "`n1. Compiling 1024x1024 with 100k step limit..." -ForegroundColor Yellow

# Read and modify source
$sourceFile = "$sourceDir\fractal_habit.cu"
$sourceContent = Get-Content $sourceFile -Raw

# Modify for 100k steps (2 samples)
$modifiedContent = $sourceContent
$modifiedContent = $modifiedContent -replace '#define TOTAL_STEPS\s+10000000', '#define TOTAL_STEPS      100000'
$modifiedContent = $modifiedContent -replace '10M steps', '100k steps'
$modifiedContent = $modifiedContent -replace 'Steps:     10000000', 'Steps:       100000'

$modifiedFile = "$gridDir\fractal_habit_1024x1024.cu"
$modifiedContent | Out-File -FilePath $modifiedFile -Encoding ASCII

Write-Host "   Source modified: 100k steps" -ForegroundColor Green

# Compile
Write-Host "`n2. Compiling..." -ForegroundColor Yellow

$compileCmd = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" > nul 2>&1
cd /d "{0}"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 fractal_habit_1024x1024.cu -o fractal_habit_1024x1024.exe -lnvml -lcufft
echo Exit code: %errorlevel%
'@ -f $gridDir

$batchFile = "$gridDir\compile.bat"
$compileCmd | Out-File -FilePath $batchFile -Encoding ASCII

$result = cmd /c "`"$batchFile`" 2>&1"
Remove-Item $batchFile -Force

if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ Compiled successfully" -ForegroundColor Green
    $exeSize = (Get-Item "$gridDir\fractal_habit_1024x1024.exe").Length
    Write-Host "   Executable: $($exeSize.ToString('N0')) bytes" -ForegroundColor Gray
} else {
    Write-Host "   ❌ Compilation failed" -ForegroundColor Red
    $result
    exit 1
}

# Prepare brain state
Write-Host "`n3. Preparing brain state..." -ForegroundColor Yellow

$buildDir = "$gridDir\build"
if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
}

$brainStateSource = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain-build\f_state_post_relax.bin"
$brainStateDest = "$buildDir\f_state_post_relax.bin"

if (Test-Path $brainStateSource) {
    Copy-Item $brainStateSource $brainStateDest -Force
    $size = (Get-Item $brainStateDest).Length
    Write-Host "   Brain state: $([math]::Round($size/1MB,2)) MB" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  Using placeholder brain state" -ForegroundColor Yellow
    # Create empty file
    "" | Out-File -FilePath $brainStateDest -Encoding ASCII
}

# Run experiment
Write-Host "`n4. Running 1024x1024 at 150W..." -ForegroundColor Yellow
Write-Host "   Expected time: 30-60 seconds" -ForegroundColor Gray
Write-Host "   Monitoring spectral slope (sl) evolution..." -ForegroundColor Gray

$outputFile = "$gridDir\output_1024x1024.log"
$runCmd = "cd /d `"$gridDir`" && fractal_habit_1024x1024.exe"

Write-Host "`n   Starting..." -ForegroundColor Cyan
$process = Start-Process cmd -ArgumentList "/c $runCmd" -NoNewWindow -PassThru -RedirectStandardOutput $outputFile

Write-Host "   Process ID: $($process.Id)" -ForegroundColor Gray
Write-Host "   Output file: $outputFile" -ForegroundColor Gray

# Wait a moment
Start-Sleep -Seconds 5

# Check if running
if ($process.HasExited) {
    Write-Host "   Process exited quickly, checking output..." -ForegroundColor Yellow
    if (Test-Path $outputFile) {
        Get-Content $outputFile -Tail 10 | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
    }
} else {
    Write-Host "   Process running..." -ForegroundColor Green
    Write-Host "   Will monitor and report results" -ForegroundColor Gray
}

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "EXPERIMENT 1 RUNNING" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan

Write-Host "`nKey metrics to watch:" -ForegroundColor Yellow
Write-Host "   - Power: Should be ~149W (at 150W cap)" -ForegroundColor White
Write-Host "   - Slope (sl): Target -2.0 to -2.5" -ForegroundColor White
Write-Host "   - Entropy (H): Should grow slowly" -ForegroundColor White
Write-Host "`nWill report back with results in ~60 seconds." -ForegroundColor Cyan