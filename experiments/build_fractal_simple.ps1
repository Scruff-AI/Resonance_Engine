# Simple build script for fractal_habit
Write-Host "Building fractal_habit for Windows..." -ForegroundColor Yellow

# Set up environment
$vcvarsPath = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"

if (-not (Test-Path $vcvarsPath)) {
    Write-Host "Error: vcvars64.bat not found" -ForegroundColor Red
    exit 1
}

# Create a batch file to set environment and compile
$batchContent = @"
@echo off
call "$vcvarsPath"
cd /d "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 fractal_habit.cu -o "D:\openclaw-local\workspace-main\build\fractal_habit.exe" -lnvml -lcufft
echo Exit code: %errorlevel%
"@

$batchFile = "D:\openclaw-local\workspace-main\build_temp.bat"
$batchContent | Out-File -FilePath $batchFile -Encoding ASCII

Write-Host "Running build..." -ForegroundColor Cyan
$result = cmd /c "`"$batchFile`" 2>&1"

Remove-Item $batchFile -Force

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful!" -ForegroundColor Green
    $exePath = "D:\openclaw-local\workspace-main\build\fractal_habit.exe"
    if (Test-Path $exePath) {
        Write-Host "Output: $exePath" -ForegroundColor Green
        Write-Host "Size: $((Get-Item $exePath).Length) bytes" -ForegroundColor Green
    }
} else {
    Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
    Write-Host "Output:" -ForegroundColor Red
    $result
}