# Build 192x192 version
Write-Host "Building 192x192 fractal_habit..." -ForegroundColor Yellow

# Create batch file
$batchContent = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d "D:\openclaw-local\workspace-main\squeeze_versions"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 "192x192\fractal_habit_192x192.cu" -o "192x192\fractal_habit_192x192.exe" -lnvml -lcufft
echo Exit code: %errorlevel%
'@

$batchFile = "D:\openclaw-local\workspace-main\build_192x192.bat"
$batchContent | Out-File -FilePath $batchFile -Encoding ASCII

$result = cmd /c ""$batchFile" 2>&1"
Remove-Item $batchFile -Force

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful: 192x192" -ForegroundColor Green
} else {
    Write-Host "Build failed for 192x192" -ForegroundColor Red
    $result
}
