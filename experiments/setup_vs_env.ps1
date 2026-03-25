# Set up Visual Studio environment using vcvarsall.bat
Write-Host "Setting up Visual Studio 2022 environment..." -ForegroundColor Cyan

$vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
$cudaPath = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin"

Write-Host "Using: $vcvars" -ForegroundColor Green
Write-Host "CUDA: $cudaPath" -ForegroundColor Green

# Create a batch file to set up environment
$batchContent = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64
set PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin;%PATH%
echo Environment set up!
echo Testing cl.exe...
cl --version
echo.
echo Testing nvcc...
nvcc --version
echo.
echo Ready to compile.
'@

Set-Content -Path "setup_env.bat" -Value $batchContent -Encoding ASCII

Write-Host "`nRunning environment setup..." -ForegroundColor Yellow
cmd /c "setup_env.bat"

# Clean up
Remove-Item setup_env.bat -ErrorAction SilentlyContinue

Write-Host "`nEnvironment should be set up now." -ForegroundColor Green
Write-Host "Try compiling with: nvcc -o fractal_habit_256.exe fractal_habit_256.cu -lnvidia-ml -lpthread -lcufft" -ForegroundColor Cyan