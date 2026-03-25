# Build 1024x1024 short-run for harmonic scan
Write-Host "Building 1024x1024 short-run..." -ForegroundColor Yellow

$batchContent = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d "D:\openclaw-local\workspace-main\harmonic_scan_short"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 "1024x1024\fractal_habit_1024x1024_short.cu" -o "1024x1024\fractal_habit_1024x1024_short.exe" -lnvml -lcufft
echo Exit code: %errorlevel%
'@

$batchFile = "D:\openclaw-local\workspace-main\harmonic_scan_short\build_1024x1024_short.bat"
$batchContent | Out-File -FilePath $batchFile -Encoding ASCII

$result = cmd /c ""$batchFile" 2>&1"
Remove-Item $batchFile -Force

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful: 1024x1024 short-run" -ForegroundColor Green
} else {
    Write-Host "Build failed for 1024x1024" -ForegroundColor Red
    $result
}
