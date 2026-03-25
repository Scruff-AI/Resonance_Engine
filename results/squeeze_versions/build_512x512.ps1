# Build 512x512 version
Write-Host "Building 512x512 fractal_habit..." -ForegroundColor Yellow

# Create batch file
$batchContent = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d "D:\openclaw-local\workspace-main\squeeze_versions"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 "512x512\fractal_habit_512x512.cu" -o "512x512\fractal_habit_512x512.exe" -lnvml -lcufft
echo Exit code: %errorlevel%
'@

$batchFile = "D:\openclaw-local\workspace-main\build_512x512.bat"
$batchContent | Out-File -FilePath $batchFile -Encoding ASCII

$result = cmd /c ""$batchFile" 2>&1"
Remove-Item $batchFile -Force

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful: 512x512" -ForegroundColor Green
} else {
    Write-Host "Build failed for 512x512" -ForegroundColor Red
    $result
}
