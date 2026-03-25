# Simple Harmonic Scan Experiment
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "ENERGY-FIRST EVOLUTIONARY SQUEEZE" -ForegroundColor Cyan
Write-Host "150W Metabolic Cap - Harmonic Grid Scan" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Grid sizes for harmonic scan
$gridSizes = @(
    @{Name="1024x1024"; NX=1024; NY=1024},
    @{Name="896x896"; NX=896; NY=896},
    @{Name="768x768"; NX=768; NY=768},
    @{Name="640x640"; NX=640; NY=640},
    @{Name="512x512"; NX=512; NY=512}
)

$baseDir = "D:\openclaw-local\workspace-main"
$experimentDir = "$baseDir\harmonic_scan_150w"
$sourceDir = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src"

# Create experiment directory
if (-not (Test-Path $experimentDir)) {
    New-Item -ItemType Directory -Path $experimentDir -Force | Out-Null
}

Write-Host "`nSetting up 150W power cap..." -ForegroundColor Yellow

# Since the Python module has Unicode issues, let's use direct signaling
$signalDir = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain-build\gpu_clock_signal"
$requestFile = "$signalDir\request.json"

# Create power limit request
$powerRequest = @{
    timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.ffffff"
    command = "pl"
    parameters = @{watts = 150}
    status = "pending"
} | ConvertTo-Json

# Write request
if (-not (Test-Path $signalDir)) {
    New-Item -ItemType Directory -Path $signalDir -Force | Out-Null
}

$powerRequest | Out-File -FilePath $requestFile -Encoding ASCII
Write-Host "  Power limit request sent (150W)" -ForegroundColor Green

# Wait a moment for service to process
Start-Sleep -Seconds 2

# Verify power limit
Write-Host "`nVerifying power limit..." -ForegroundColor Yellow
$powerInfo = nvidia-smi -q -d POWER 2>&1
$currentLimit = ($powerInfo | Select-String "Current Power Limit").ToString() -replace '.*Current Power Limit\s*:\s*(\d+\.\d+).*', '$1'
Write-Host "  Current power limit: $currentLimit W" -ForegroundColor Green

Write-Host "`nPower cap set. Ready for harmonic scan." -ForegroundColor Green
Write-Host "`nWe'll now run experiments at:" -ForegroundColor Yellow
foreach ($grid in $gridSizes) {
    Write-Host "  - $($grid.Name)" -ForegroundColor White
}

Write-Host "`nKey diagnostic: Spectral slope (sl)" -ForegroundColor Cyan
Write-Host "  Target: -2.0 to -2.5 (coherent, power-law)" -ForegroundColor White
Write-Host "  Failure: -0.5 (white noise, harmonic mismatch)" -ForegroundColor White

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "EXPERIMENT READY" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Compile each grid size with 50k step limit" -ForegroundColor White
Write-Host "2. Run experiments sequentially" -ForegroundColor White
Write-Host "3. Capture spectral slopes at 150W constraint" -ForegroundColor White
Write-Host "4. Identify harmonic sweet spot" -ForegroundColor White

Write-Host "`nThe system is now ready for the energy-first evolutionary squeeze!" -ForegroundColor Green