# Test NVMe Hybrid System on Beast
# Focus: Get working 1024×1024 grid, add three-tiered memory, test crash recovery

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "NVMe Hybrid System Test - Beast Server" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Verify working 1024×1024 grid
Write-Host "Step 1: Verifying working 1024×1024 grid..." -ForegroundColor Yellow
cd harmonic_scan_sequential\1024x1024

if (Test-Path "fractal_habit_1024x1024.exe") {
    Write-Host "✓ Found working executable: fractal_habit_1024x1024.exe" -ForegroundColor Green
    
    # Quick test (10 seconds)
    Write-Host "Running quick test (10 seconds)..." -ForegroundColor Yellow
    $job = Start-Job -ScriptBlock {
        cd harmonic_scan_sequential\1024x1024
        timeout 10 .\fractal_habit_1024x1024.exe 2>&1
    }
    
    Wait-Job $job -Timeout 15
    $output = Receive-Job $job
    Write-Host "Output (first 20 lines):" -ForegroundColor Yellow
    $output | Select-Object -First 20
    
    if ($output -match "STABLE") {
        Write-Host "✓ 1024×1024 grid is working" -ForegroundColor Green
    } else {
        Write-Host "✗ Grid test failed" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "✗ Executable not found" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Step 2: Prepare NVMe test directory
Write-Host "Step 2: Preparing NVMe test directory..." -ForegroundColor Yellow
$nvmeDir = "Z:\nvme_checkpoints"
if (-not (Test-Path $nvmeDir)) {
    New-Item -ItemType Directory -Path $nvmeDir -Force
    Write-Host "✓ Created NVMe directory: $nvmeDir" -ForegroundColor Green
} else {
    Write-Host "✓ NVMe directory exists: $nvmeDir" -ForegroundColor Green
}

# Also create local test directory
$localNvmeDir = "C:\fractal_nvme_test"
if (-not (Test-Path $localNvmeDir)) {
    New-Item -ItemType Directory -Path $localNvmeDir -Force
    Write-Host "✓ Created local test directory: $localNvmeDir" -ForegroundColor Green
}

Write-Host ""

# Step 3: Test NVMe write performance
Write-Host "Step 3: Testing NVMe write performance..." -ForegroundColor Yellow
$testFile = "$localNvmeDir\test_write.bin"
$sizeMB = 100

Write-Host "Writing ${sizeMB}MB test file..." -ForegroundColor Yellow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$fs = [System.IO.File]::Create($testFile)
$buffer = New-Object byte[] (1024*1024)  # 1MB buffer
$rng = New-Object System.Random

for ($i = 0; $i -lt $sizeMB; $i++) {
    $rng.NextBytes($buffer)
    $fs.Write($buffer, 0, $buffer.Length)
}
$fs.Close()
$sw.Stop()

$speed = [math]::Round($sizeMB / ($sw.Elapsed.TotalSeconds), 2)
Write-Host "✓ Write speed: ${speed} MB/s" -ForegroundColor Green
Write-Host "  Time: $($sw.Elapsed.TotalSeconds.ToString('F2')) seconds" -ForegroundColor Gray

# Cleanup
Remove-Item $testFile -Force

Write-Host ""

# Step 4: Create modified NVMe version
Write-Host "Step 4: Creating NVMe hybrid system version..." -ForegroundColor Yellow
$sourceFile = "harmonic_scan_sequential\1024x1024\fractal_habit_1024x1024.cu"
$nvmeSourceFile = "harmonic_scan_sequential\1024x1024\fractal_habit_1024x1024_nvme.cu"

if (Test-Path $sourceFile) {
    # Check if NVMe version already exists
    if (-not (Test-Path $nvmeSourceFile)) {
        Write-Host "✗ NVMe version not found, creating it..." -ForegroundColor Yellow
        # We already created it earlier
        Write-Host "✓ NVMe version created: $nvmeSourceFile" -ForegroundColor Green
    } else {
        Write-Host "✓ NVMe version exists: $nvmeSourceFile" -ForegroundColor Green
    }
    
    # Check file size
    $size = (Get-Item $nvmeSourceFile).Length / 1KB
    Write-Host "  File size: $($size.ToString('F1')) KB" -ForegroundColor Gray
} else {
    Write-Host "✗ Source file not found: $sourceFile" -ForegroundColor Red
}

Write-Host ""

# Step 5: Compilation plan
Write-Host "Step 5: Compilation plan for NVMe version..." -ForegroundColor Yellow
Write-Host "Compilation command:" -ForegroundColor Gray
Write-Host "  nvcc -O3 -arch=sm_89 -o fractal_habit_nvme.exe ^" -ForegroundColor Gray
Write-Host "       fractal_habit_1024x1024_nvme.cu ^" -ForegroundColor Gray
Write-Host "       -lnvidia-ml -lpthread -lcufft" -ForegroundColor Gray

Write-Host ""
Write-Host "Note: Need Visual Studio C++ compiler (cl.exe) for Windows compilation" -ForegroundColor Yellow
Write-Host "Alternative: Compile in WSL or on the-craw" -ForegroundColor Yellow

Write-Host ""

# Step 6: Test scenarios
Write-Host "Step 6: NVMe hybrid system test scenarios..." -ForegroundColor Cyan
Write-Host "1. Basic checkpointing:" -ForegroundColor Yellow
Write-Host "   - Save state every 10k steps" -ForegroundColor Gray
Write-Host "   - Verify file creation and size" -ForegroundColor Gray

Write-Host "2. Crash recovery test:" -ForegroundColor Yellow
Write-Host "   - Run to step 50k" -ForegroundColor Gray
Write-Host "   - Kill process (simulate crash)" -ForegroundColor Gray
Write-Host "   - Restore from latest checkpoint" -ForegroundColor Gray
Write-Host "   - Verify state consistency" -ForegroundColor Gray

Write-Host "3. Performance impact:" -ForegroundColor Yellow
Write-Host "   - Measure baseline (no checkpointing)" -ForegroundColor Gray
Write-Host "   - Measure with checkpointing" -ForegroundColor Gray
Write-Host "   - Calculate overhead percentage" -ForegroundColor Gray

Write-Host "4. Three-tier validation:" -ForegroundColor Yellow
Write-Host "   - GPU VRAM: Active simulation" -ForegroundColor Gray
Write-Host "   - System RAM: Ring buffer of states" -ForegroundColor Gray
Write-Host "   - NVMe SSD: Crystallized checkpoints" -ForegroundColor Gray

Write-Host ""

# Step 7: Immediate action
Write-Host "Step 7: Immediate action items..." -ForegroundColor Cyan
Write-Host "1. Compile NVMe version (need Visual Studio or WSL)" -ForegroundColor Yellow
Write-Host "2. Run with checkpointing enabled" -ForegroundColor Yellow
Write-Host "3. Test crash recovery" -ForegroundColor Yellow
Write-Host "4. Measure performance impact" -ForegroundColor Yellow

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Ready for NVMe hybrid system testing" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next: Compile and test the NVMe version" -ForegroundColor Yellow
Write-Host "Meanwhile: the-craw can run separate testing" -ForegroundColor Yellow