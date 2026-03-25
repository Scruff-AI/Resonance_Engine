# Build 640x640 short-run for harmonic scan
Write-Host "Building 640x640 short-run..." -ForegroundColor Yellow

$batchContent = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d "D:\openclaw-local\workspace-main\harmonic_scan_short"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 "640x640\fractal_habit_640x640_short.cu" -o "640x640\fractal_habit_640x640_short.exe" -lnvml -lcufft
echo Exit code: %errorlevel%
'@

$batchFile = "D:\openclaw-local\workspace-main\harmonic_scan_short\build_640x640_short.bat"
$batchContent | Out-File -FilePath $batchFile -Encoding ASCII

$result = cmd /c ""$batchFile" 2>&1"
Remove-Item $batchFile -Force

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful: 640x640 short-run" -ForegroundColor Green
} else {
    Write-Host "Build failed for 640x640" -ForegroundColor Red
    $result
}
