# Build 1024x1024 for harmonic scan
Write-Host "Building 1024x1024..." -ForegroundColor Yellow

$batchContent = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d "D:\openclaw-local\workspace-main\harmonic_scan"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 "1024x1024\fractal_habit_1024x1024.cu" -o "1024x1024\fractal_habit_1024x1024.exe" -lnvml -lcufft
echo Exit code: %errorlevel%
'@

$batchFile = "D:\openclaw-local\workspace-main\harmonic_scan\build_1024x1024.bat"
$batchContent | Out-File -FilePath $batchFile -Encoding ASCII

$result = cmd /c ""$batchFile" 2>&1"
Remove-Item $batchFile -Force

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful: 1024x1024" -ForegroundColor Green
} else {
    Write-Host "Build failed for 1024x1024" -ForegroundColor Red
    $result
}
