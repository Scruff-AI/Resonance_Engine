# Test 512x512
Write-Host "=== Testing 512x512 ===" -ForegroundColor Cyan

# Create directory
New-Item -ItemType Directory -Force -Path "test_512x512\build" | Out-Null

# Copy brain state
Copy-Item "harmonic_brain_states\build_512x512\f_state_post_relax.bin" "test_512x512\build\" -Force
Write-Host "Brain state copied" -ForegroundColor Green

# Run test
Set-Location "test_512x512"
Write-Host "Running 50k steps..." -ForegroundColor Yellow
& "..\build\fractal_habit.exe" 50000 1
Set-Location ".."

Write-Host "`n=== Testing 384x384 ===" -ForegroundColor Cyan

# Create directory
New-Item -ItemType Directory -Force -Path "test_384x384\build" | Out-Null

# Copy brain state
Copy-Item "harmonic_brain_states\build_384x384\f_state_post_relax.bin" "test_384x384\build\" -Force
Write-Host "Brain state copied" -ForegroundColor Green

# Run test
Set-Location "test_384x384"
Write-Host "Running 50k steps..." -ForegroundColor Yellow
& "..\build\fractal_habit.exe" 50000 1
Set-Location ".."

Write-Host "`n=== Testing 256x256 ===" -ForegroundColor Cyan

# Create directory
New-Item -ItemType Directory -Force -Path "test_256x256\build" | Out-Null

# Copy brain state
Copy-Item "harmonic_brain_states\build_256x256\f_state_post_relax.bin" "test_256x256\build\" -Force
Write-Host "Brain state copied" -ForegroundColor Green

# Run test
Set-Location "test_256x256"
Write-Host "Running 50k steps..." -ForegroundColor Yellow
& "..\build\fractal_habit.exe" 50000 1
Set-Location ".."

Write-Host "`nAll tests completed!" -ForegroundColor Green