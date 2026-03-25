# Simple NVMe Hybrid System Test
Write-Host "=== NVMe Hybrid System Test ===" -ForegroundColor Cyan

# Step 1: Check working grid
Write-Host "`n1. Checking working 1024x1024 grid..." -ForegroundColor Yellow
cd harmonic_scan_sequential\1024x1024

if (Test-Path "fractal_habit_1024x1024.exe") {
    Write-Host "  Found: fractal_habit_1024x1024.exe" -ForegroundColor Green
    Write-Host "  Size: $((Get-Item .\fractal_habit_1024x1024.exe).Length / 1KB) KB" -ForegroundColor Gray
    
    # Check if it runs
    Write-Host "  Testing (5 seconds)..." -ForegroundColor Yellow
    $process = Start-Process -FilePath ".\fractal_habit_1024x1024.exe" -NoNewWindow -PassThru
    Start-Sleep -Seconds 5
    Stop-Process -Id $process.Id -Force
    Write-Host "  Test completed" -ForegroundColor Green
} else {
    Write-Host "  ERROR: Executable not found" -ForegroundColor Red
}

# Step 2: Check NVMe directories
Write-Host "`n2. Checking NVMe directories..." -ForegroundColor Yellow

# NAS directory
$nasDir = "Z:\nvme_checkpoints"
if (Test-Path $nasDir) {
    Write-Host "  NAS: $nasDir (exists)" -ForegroundColor Green
} else {
    Write-Host "  NAS: $nasDir (creating...)" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $nasDir -Force
}

# Local directory
$localDir = "C:\fractal_nvme_test"
if (Test-Path $localDir) {
    Write-Host "  Local: $localDir (exists)" -ForegroundColor Green
} else {
    Write-Host "  Local: $localDir (creating...)" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $localDir -Force
}

# Step 3: Check NVMe source file
Write-Host "`n3. Checking NVMe source code..." -ForegroundColor Yellow
$nvmeSource = ".\fractal_habit_1024x1024_nvme.cu"
if (Test-Path $nvmeSource) {
    Write-Host "  Found: $nvmeSource" -ForegroundColor Green
    Write-Host "  Size: $((Get-Item $nvmeSource).Length / 1KB) KB" -ForegroundColor Gray
    
    # Check for NVMe features
    $content = Get-Content $nvmeSource -Raw
    if ($content -match "NVMeHybridSystem") {
        Write-Host "  Contains NVMe hybrid system class" -ForegroundColor Green
    }
    if ($content -match "CHECKPOINT_INTERVAL") {
        Write-Host "  Has checkpoint interval: $($matches[0])" -ForegroundColor Green
    }
} else {
    Write-Host "  ERROR: NVMe source not found" -ForegroundColor Red
}

# Step 4: Test plan
Write-Host "`n4. Test Plan:" -ForegroundColor Cyan
Write-Host "  a) Compile NVMe version" -ForegroundColor Yellow
Write-Host "     nvcc -O3 -arch=sm_89 -o fractal_habit_nvme.exe ^" -ForegroundColor Gray
Write-Host "          fractal_habit_1024x1024_nvme.cu ^" -ForegroundColor Gray
Write-Host "          -lnvidia-ml -lpthread -lcufft" -ForegroundColor Gray

Write-Host "`n  b) Run with checkpointing" -ForegroundColor Yellow
Write-Host "     .\fractal_habit_nvme.exe" -ForegroundColor Gray

Write-Host "`n  c) Test crash recovery" -ForegroundColor Yellow
Write-Host "     1. Run to step 50k" -ForegroundColor Gray
Write-Host "     2. Kill process" -ForegroundColor Gray
Write-Host "     3. Restore from checkpoint" -ForegroundColor Gray
Write-Host "     4. Verify state" -ForegroundColor Gray

Write-Host "`n  d) Measure performance" -ForegroundColor Yellow
Write-Host "     - Baseline (no checkpoint)" -ForegroundColor Gray
Write-Host "     - With checkpointing" -ForegroundColor Gray
Write-Host "     - Calculate overhead" -ForegroundColor Gray

# Step 5: Compilation check
Write-Host "`n5. Compilation requirements:" -ForegroundColor Cyan
Write-Host "  CUDA:" -ForegroundColor Yellow
$cudaPath = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\"
if (Test-Path $cudaPath) {
    $versions = Get-ChildItem $cudaPath | Where-Object {$_.Name -match "v\d"}
    Write-Host "    Found: $($versions.Name -join ', ')" -ForegroundColor Green
} else {
    Write-Host "    NOT FOUND" -ForegroundColor Red
}

Write-Host "  Visual Studio (cl.exe):" -ForegroundColor Yellow
$clPath = Get-Command cl.exe -ErrorAction SilentlyContinue
if ($clPath) {
    Write-Host "    Found: $($clPath.Source)" -ForegroundColor Green
} else {
    Write-Host "    NOT FOUND - Need for Windows compilation" -ForegroundColor Red
    Write-Host "    Alternative: WSL or remote compilation" -ForegroundColor Yellow
}

Write-Host "`n=== Ready for NVMe testing ===" -ForegroundColor Green
Write-Host "`nOn Beast: Implement/test NVMe hybrid system" -ForegroundColor Yellow
Write-Host "On the-craw: Run separate testing" -ForegroundColor Yellow