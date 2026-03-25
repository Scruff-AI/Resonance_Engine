# Compile probe_256.cu for GTX 1050 (sm_61)
Write-Host "Compiling PROBE 256×256 for GTX 1050..." -ForegroundColor Cyan
Write-Host "Grid: 256×256 | Guardians: 12 | Target: 40-60W" -ForegroundColor Yellow

# Find CUDA
$cudaPath = $null
$possiblePaths = @(
    "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.0\bin\nvcc.exe",
    "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v11.8\bin\nvcc.exe",
    "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v11.0\bin\nvcc.exe"
)

foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $cudaPath = $path
        break
    }
}

if (-not $cudaPath) {
    Write-Host "CUDA not found!" -ForegroundColor Red
    exit 1
}

Write-Host "Found CUDA at: $cudaPath" -ForegroundColor Green

# Compile for GTX 1050 (sm_61)
$compileCmd = "`"$cudaPath`" -O3 -arch=sm_61 -o probe_256.exe probe_256.cu -lnvidia-ml -lpthread"
Write-Host "`nCompilation command:" -ForegroundColor Gray
Write-Host $compileCmd

Write-Host "`nCompiling..." -ForegroundColor Cyan
Invoke-Expression $compileCmd

# Check result
if (Test-Path "probe_256.exe") {
    Write-Host "`n✅ SUCCESS: probe_256.exe compiled!" -ForegroundColor Green
    $size = (Get-Item 'probe_256.exe').Length / 1MB
    Write-Host "File size: $([math]::Round($size, 2)) MB" -ForegroundColor Gray
    
    # Create test directory
    New-Item -ItemType Directory -Force -Path "test_probe_256\build" | Out-Null
    
    # Copy brain state
    if (Test-Path "harmonic_brain_states\build_256x256\f_state_post_relax.bin") {
        Copy-Item "harmonic_brain_states\build_256x256\f_state_post_relax.bin" "test_probe_256\build\" -Force
        Write-Host "Brain state copied" -ForegroundColor Green
    }
    
    Write-Host "`nReady to test:" -ForegroundColor Green
    Write-Host "  cd test_probe_256" -ForegroundColor Gray
    Write-Host "  ..\probe_256.exe" -ForegroundColor Gray
} else {
    Write-Host "`n❌ COMPILATION FAILED" -ForegroundColor Red
}