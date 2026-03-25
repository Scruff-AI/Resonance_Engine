# Compile fractal_habit_256.cu for GTX 1050 (sm_61)
Write-Host "Compiling 256×256 MVP for GTX 1050..." -ForegroundColor Cyan

# Check if CUDA is available
$cudaPath = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.0\bin\nvcc.exe"
if (-not (Test-Path $cudaPath)) {
    Write-Host "CUDA not found at: $cudaPath" -ForegroundColor Red
    Write-Host "Trying to find CUDA..." -ForegroundColor Yellow
    
    # Search for nvcc
    $possiblePaths = @(
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.0\bin\nvcc.exe",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v11.8\bin\nvcc.exe",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v11.0\bin\nvcc.exe",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v10.2\bin\nvcc.exe"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $cudaPath = $path
            Write-Host "Found CUDA at: $cudaPath" -ForegroundColor Green
            break
        }
    }
    
    if (-not (Test-Path $cudaPath)) {
        Write-Host "CUDA not found. Please install CUDA Toolkit." -ForegroundColor Red
        exit 1
    }
}

# Compilation command for GTX 1050 (sm_61)
$compileCmd = "`"$cudaPath`" -O3 -arch=sm_61 -o fractal_habit_256.exe fractal_habit_256.cu -lnvidia-ml -lpthread -lcufft"

Write-Host "Compilation command:" -ForegroundColor Yellow
Write-Host $compileCmd -ForegroundColor Gray

# Run compilation
Write-Host "`nCompiling..." -ForegroundColor Cyan
Invoke-Expression $compileCmd

# Check if compilation succeeded
if (Test-Path "fractal_habit_256.exe") {
    Write-Host "`n✅ SUCCESS: fractal_habit_256.exe compiled!" -ForegroundColor Green
    Write-Host "File size: $((Get-Item 'fractal_habit_256.exe').Length / 1MB) MB" -ForegroundColor Gray
    
    # Test with a simple brain state
    Write-Host "`nCreating test directory..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path "test_256_mvp\build" | Out-Null
    
    # Copy 256×256 brain state
    if (Test-Path "harmonic_brain_states\build_256x256\f_state_post_relax.bin") {
        Copy-Item "harmonic_brain_states\build_256x256\f_state_post_relax.bin" "test_256_mvp\build\" -Force
        Write-Host "Brain state copied to test_256_mvp\build\" -ForegroundColor Green
    } else {
        Write-Host "Warning: 256×256 brain state not found" -ForegroundColor Yellow
    }
    
    Write-Host "`nReady to test with: .\fractal_habit_256.exe 100000 1" -ForegroundColor Green
} else {
    Write-Host "`n❌ COMPILATION FAILED" -ForegroundColor Red
    Write-Host "Check CUDA installation and dependencies." -ForegroundColor Yellow
}