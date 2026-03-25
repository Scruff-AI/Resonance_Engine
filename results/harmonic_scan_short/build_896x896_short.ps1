# Build 896x896 short-run for harmonic scan
Write-Host "Building 896x896 short-run..." -ForegroundColor Yellow

$batchContent = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d "D:\openclaw-local\workspace-main\harmonic_scan_short"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 "896x896\fractal_habit_896x896_short.cu" -o "896x896\fractal_habit_896x896_short.exe" -lnvml -lcufft
echo Exit code: %errorlevel%
'@

$batchFile = "D:\openclaw-local\workspace-main\harmonic_scan_short\build_896x896_short.bat"
$batchContent | Out-File -FilePath $batchFile -Encoding ASCII

$result = cmd /c ""$batchFile" 2>&1"
Remove-Item $batchFile -Force

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful: 896x896 short-run" -ForegroundColor Green
} else {
    Write-Host "Build failed for 896x896" -ForegroundColor Red
    $result
}
