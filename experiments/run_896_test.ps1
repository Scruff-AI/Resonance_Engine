# Run 896x896 test at 150W
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "EXPERIMENT 2: 896x896 at 150W" -ForegroundColor Cyan
Write-Host "12.5% Reduction - Harmonic Step Test" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$baseDir = "D:\openclaw-local\workspace-main"
$experimentDir = "$baseDir\harmonic_scan_sequential"
$sourceDir = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src"

$gridDir = "$experimentDir\896x896"
if (-not (Test-Path $gridDir)) {
    New-Item -ItemType Directory -Path $gridDir -Force | Out-Null
}

Write-Host "`n1. Compiling 896x896 with 200k step limit..." -ForegroundColor Yellow

# Read source
$sourceFile = "$sourceDir\fractal_habit.cu"
$sourceContent = Get-Content $sourceFile -Raw

# Modify for 896x896, 200k steps
$modifiedContent = $sourceContent
$modifiedContent = $modifiedContent -replace '#define NX\s+1024', '#define NX    896'
$modifiedContent = $modifiedContent -replace '#define NY\s+1024', '#define NY    896'
$modifiedContent = $modifiedContent -replace '#define TOTAL_STEPS\s+10000000', '#define TOTAL_STEPS      200000'
$modifiedContent = $modifiedContent -replace '10M steps', '200k steps'
$modifiedContent = $modifiedContent -replace 'Steps:     10000000', 'Steps:       200000'

$modifiedFile = "$gridDir\fractal_habit_896x896.cu"
$modifiedContent | Out-File -FilePath $modifiedFile -Encoding ASCII

Write-Host "   Source modified: 896x896, 200k steps" -ForegroundColor Green

# Compile
Write-Host "`n2. Compiling..." -ForegroundColor Yellow

$compileCmd = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" > nul 2>&1
cd /d "{0}"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 fractal_habit_896x896.cu -o fractal_habit_896x896.exe -lnvml -lcufft
echo Exit code: %errorlevel%
'@ -f $gridDir

$batchFile = "$gridDir\compile.bat"
$compileCmd | Out-File -FilePath $batchFile -Encoding ASCII

$result = cmd /c "`"$batchFile`" 2>&1"
Remove-Item $batchFile -Force

if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ Compiled successfully" -ForegroundColor Green
    $exeSize = (Get-Item "$gridDir\fractal_habit_896x896.exe").Length
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

$brainStateSource = "D:\openclaw-local\workspace-main\harmonic_brain_states\build_896x896\f_state_post_relax.bin"
$brainStateDest = "$buildDir\f_state_post_relax.bin"

if (Test-Path $brainStateSource) {
    Copy-Item $brainStateSource $brainStateDest -Force
    $size = (Get-Item $brainStateDest).Length
    Write-Host "   Brain state: $([math]::Round($size/1MB,2)) MB" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  Brain state not found, creating from 1024x1024" -ForegroundColor Yellow
    # Use 1024x1024 as fallback
    Copy-Item "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain-build\f_state_post_relax.bin" $brainStateDest -Force
}

# Run experiment
Write-Host "`n4. Running 896x896 at 150W..." -ForegroundColor Yellow
Write-Host "   Expected time: 2-3 minutes" -ForegroundColor Gray
Write-Host "   Monitoring for slope stability..." -ForegroundColor Gray

$outputFile = "$gridDir\output_896x896.log"
$runCmd = "cd /d `"$gridDir`" && fractal_habit_896x896.exe"

Write-Host "`n   Starting..." -ForegroundColor Cyan
$process = Start-Process cmd -ArgumentList "/c $runCmd" -NoNewWindow -PassThru -RedirectStandardOutput $outputFile

Write-Host "   Process ID: $($process.Id)" -ForegroundColor Gray
Write-Host "   Output file: $outputFile" -ForegroundColor Gray

# Wait and monitor
Write-Host "`n   Waiting 30 seconds for initial results..." -ForegroundColor Gray
Start-Sleep -Seconds 30

# Check initial output
if (Test-Path $outputFile) {
    Write-Host "`n   Initial output:" -ForegroundColor Yellow
    Get-Content $outputFile -Tail 5 | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
}

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "EXPERIMENT 2 RUNNING" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan

Write-Host "`nCritical question:" -ForegroundColor Yellow
Write-Host "   Does 896x896 maintain coherence like 1024x1024?" -ForegroundColor White
Write-Host "   Or does it trend toward noise like 768x768?" -ForegroundColor White
Write-Host "`nWill report full results in ~2 minutes." -ForegroundColor Cyan