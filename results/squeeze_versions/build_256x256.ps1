# Build 256x256 version
Write-Host "Building 256x256 fractal_habit..." -ForegroundColor Yellow

# Create batch file
$batchContent = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d "D:\openclaw-local\workspace-main\squeeze_versions"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 "256x256\fractal_habit_256x256.cu" -o "256x256\fractal_habit_256x256.exe" -lnvml -lcufft
echo Exit code: %errorlevel%
'@

$batchFile = "D:\openclaw-local\workspace-main\build_256x256.bat"
$batchContent | Out-File -FilePath $batchFile -Encoding ASCII

$result = cmd /c ""$batchFile" 2>&1"
Remove-Item $batchFile -Force

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful: 256x256" -ForegroundColor Green
} else {
    Write-Host "Build failed for 256x256" -ForegroundColor Red
    $result
}
