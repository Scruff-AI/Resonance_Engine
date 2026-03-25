# DO IT PROPERLY - No more bullshit

Write-Host "=== DOING IT PROPERLY ===" -ForegroundColor Red -BackgroundColor White
Write-Host "Scaling 1024×1024 → 256×256 for GTX 1050" -ForegroundColor Cyan
Write-Host "No artificial shit. No Python fakes." -ForegroundColor Yellow

# Scaling factors
$scale = 256/1024  # 0.25 linear
$areaScale = $scale * $scale  # 0.0625 area

Write-Host "`nScaling factors:" -ForegroundColor Green
Write-Host "  Linear: $scale (1/4)" -ForegroundColor Gray
Write-Host "  Area: $areaScale (1/16)" -ForegroundColor Gray

# Original 1024×1024 values
$original = @{
    NX = 1024
    NY = 1024
    MAX_PARTICLES = 256  # Actually 194 guardians, but array size 256
    DRAIN_RADIUS = 16
    SINK_RADIUS = 24
    RHO_THRESH = 1.01
    SINK_RATE = 0.005
}

# Scaled 256×256 values
$scaled = @{
    NX = 256
    NY = 256
    MAX_PARTICLES = [math]::Ceiling(194 * $areaScale)  # 194 × 1/16 = 12.125 → 13
    DRAIN_RADIUS = [math]::Ceiling(16 * $scale)  # 16 × 1/4 = 4
    SINK_RADIUS = [math]::Ceiling(24 * $scale)   # 24 × 1/4 = 6
    RHO_THRESH = 1.01  # Same? Or scale?
    SINK_RATE = 0.005 * $areaScale  # Scale with area
}

Write-Host "`nOriginal (1024×1024):" -ForegroundColor Yellow
$original.GetEnumerator() | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,-15} = {1}" -f $_.Name, $_.Value) -ForegroundColor Gray
}

Write-Host "`nScaled (256×256):" -ForegroundColor Green
$scaled.GetEnumerator() | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,-15} = {1}" -f $_.Name, $_.Value) -ForegroundColor Gray
}

# Check the probe_256.cu file
Write-Host "`nChecking probe_256.cu..." -ForegroundColor Cyan

$probeContent = Get-Content "probe_256.cu" -Raw
$lines = $probeContent -split "`n"

Write-Host "Current values in probe_256.cu:" -ForegroundColor Yellow
$lines | Select-String "define.*(NX|NY|MAX_PARTICLES|DRAIN_RADIUS|SINK_RADIUS|RHO_THRESH|SINK_RATE)" | ForEach-Object {
    Write-Host ("  " + $_.Line.Trim()) -ForegroundColor Gray
}

Write-Host "`n=== ACTION PLAN ===" -ForegroundColor Red -BackgroundColor White
Write-Host "1. Update probe_256.cu with CORRECT scaled values" -ForegroundColor Cyan
Write-Host "2. Compile with Visual Studio + CUDA" -ForegroundColor Cyan
Write-Host "3. Create PROPERLY scaled brain state from 1024×1024" -ForegroundColor Cyan
Write-Host "4. Test on Beast (RTX 4090)" -ForegroundColor Cyan
Write-Host "5. Deploy to the-craw (GTX 1050)" -ForegroundColor Cyan

Write-Host "`nNo more artificial bullshit. No more Python fakes." -ForegroundColor Red
Write-Host "Doing it PROPERLY this time." -ForegroundColor Green