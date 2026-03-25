# Test compilation of 256x256
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "TEST: Can we compile 256x256?" -ForegroundColor Cyan
Write-Host "Two octaves down from 1024" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$baseDir = "D:\openclaw-local\workspace-main"
$testDir = "$baseDir\test_256x256"
$sourceDir = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src"

if (-not (Test-Path $testDir)) {
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
}

Write-Host "`n1. Creating 256x256 source..." -ForegroundColor Yellow

# Read source
$sourceFile = "$sourceDir\fractal_habit.cu"
$sourceContent = Get-Content $sourceFile -Raw

# Modify for 256x256, 50k steps
$modifiedContent = $sourceContent
$modifiedContent = $modifiedContent -replace '#define NX\s+1024', '#define NX    256'
$modifiedContent = $modifiedContent -replace '#define NY\s+1024', '#define NY    256'
$modifiedContent = $modifiedContent -replace '#define TOTAL_STEPS\s+10000000', '#define TOTAL_STEPS      50000'
$modifiedContent = $modifiedContent -replace '10M steps', '50k steps'
$modifiedContent = $modifiedContent -replace 'Steps:     10000000', 'Steps:        50000'

$modifiedFile = "$testDir\fractal_habit_256x256.cu"
$modifiedContent | Out-File -FilePath $modifiedFile -Encoding ASCII

Write-Host "   Created: fractal_habit_256x256.cu" -ForegroundColor Green
Write-Host "   Grid: 256x256 (65,536 cells)" -ForegroundColor Gray
Write-Host "   Steps: 50k" -ForegroundColor Gray

# Compile
Write-Host "`n2. Compiling..." -ForegroundColor Yellow

$compileCmd = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" > nul 2>&1
cd /d "{0}"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 fractal_habit_256x256.cu -o fractal_habit_256x256.exe -lnvml -lcufft
echo Exit code: %errorlevel%
'@ -f $testDir

$batchFile = "$testDir\compile.bat"
$compileCmd | Out-File -FilePath $batchFile -Encoding ASCII

Write-Host "   Running compilation..." -ForegroundColor Gray
$result = cmd /c "`"$batchFile`" 2>&1"
Remove-Item $batchFile -Force

if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ Compiled successfully!" -ForegroundColor Green
    $exeSize = (Get-Item "$testDir\fractal_habit_256x256.exe").Length
    Write-Host "   Executable: $($exeSize.ToString('N0')) bytes" -ForegroundColor Gray
    
    # Quick brain state test
    Write-Host "`n3. Testing brain state scaling..." -ForegroundColor Yellow
    
    $buildDir = "$testDir\build"
    if (-not (Test-Path $buildDir)) {
        New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
    }
    
    # We need to scale the brain state from 1024x1024 to 256x256
    # That's 4x reduction in each dimension (1024/256 = 4)
    Write-Host "   Scaling factor: 4x reduction (1024→256)" -ForegroundColor Gray
    Write-Host "   Expected brain state size: ~36MB / 16 ≈ 2.25MB" -ForegroundColor Gray
    
    # Check if we have scaling script
    $scaleScript = "$baseDir\scale_harmonic_states.py"
    if (Test-Path $scaleScript) {
        Write-Host "   Found scaling script" -ForegroundColor Green
        Write-Host "   Can create properly scaled brain state" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️  Need to create scaling for 256x256" -ForegroundColor Yellow
    }
    
} else {
    Write-Host "   ❌ Compilation failed" -ForegroundColor Red
    Write-Host "   Error output:" -ForegroundColor Red
    $result
}

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "NEXT STEPS FOR 256x256 @ 80W:" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan

Write-Host "`n1. Create scaled brain state (256x256)" -ForegroundColor White
Write-Host "2. Modify precipitation.cu for guardian scaling" -ForegroundColor White
Write-Host "3. Set up parameter sweep:" -ForegroundColor White
Write-Host "   - Guardian count: 8, 12, 16" -ForegroundColor Gray
Write-Host "   - RHO_THRESH: 0.8, 0.9, 1.0, 1.1" -ForegroundColor Gray
Write-Host "   - Power: 60W, 80W, 100W" -ForegroundColor Gray
Write-Host "4. Run experiments looking for 'inexplicable energy rises'" -ForegroundColor White
Write-Host "5. Analyze for harmonic synergy" -ForegroundColor White

Write-Host "`nTime estimate: 45-60 minutes" -ForegroundColor Yellow