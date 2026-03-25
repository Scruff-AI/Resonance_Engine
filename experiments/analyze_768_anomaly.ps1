# Analyze the 768x768 anomaly
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "ANALYZING 768x768 ANOMALY" -ForegroundColor Cyan
Write-Host "Why does this specific size fail?" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$baseDir = "D:\openclaw-local\workspace-main"
$gridDir = "$baseDir\harmonic_scan_sequential\768x768"
$sourceDir = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src"

Write-Host "`n1. Checking existing data..." -ForegroundColor Yellow

# Check if we have the long run data
$longRunFile = "$gridDir\output_768x768_150W_long.log"
if (Test-Path $longRunFile) {
    Write-Host "   Found long run data (1.75M steps)" -ForegroundColor Green
    
    # Extract transition point
    $content = Get-Content $longRunFile -Raw
    
    # Find where slope goes from coherent to noise
    $lines = $content -split "`n"
    $transitionFound = $false
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'sl=([-\d.]+)') {
            $slope = [float]$matches[1]
            if ($slope -gt -1.0 -and -not $transitionFound) {
                # Found noise transition
                if ($i -gt 0 -and $lines[$i-1] -match '\|\s+(\d+)\s+\|') {
                    $step = $matches[1]
                    Write-Host "   Noise transition at step: $step" -ForegroundColor Yellow
                    
                    # Get previous slope
                    if ($lines[$i-1] -match 'sl=([-\d.]+)') {
                        $prevSlope = $matches[1]
                        Write-Host "   Slope: $prevSlope → $slope" -ForegroundColor Gray
                    }
                    $transitionFound = $true
                }
            }
        }
    }
    
    if (-not $transitionFound) {
        Write-Host "   Could not find clear transition point" -ForegroundColor Gray
    }
} else {
    Write-Host "   No long run data found" -ForegroundColor Yellow
}

Write-Host "`n2. Analyzing grid properties..." -ForegroundColor Yellow

# Calculate guardian statistics
$gridSizes = @(
    @{Name="1024x1024"; Cells=1048576; Guardians=194; Density=5404.0; Spacing=73.4},
    @{Name="896x896";   Cells=802816;  Guardians=194; Density=4138.2; Spacing=64.3},
    @{Name="768x768";   Cells=589824;  Guardians=194; Density=3040.3; Spacing=55.1},
    @{Name="640x640";   Cells=409600;  Guardians=194; Density=2111.3; Spacing=45.9},
    @{Name="512x512";   Cells=262144;  Guardians=194; Density=1351.3; Spacing=36.7}
)

Write-Host "   Guardian density analysis:" -ForegroundColor Gray
foreach ($grid in $gridSizes) {
    $status = if ($grid.Name -eq "768x768") { "❌" } else { "✅" }
    Write-Host "   $status $($grid.Name): $($grid.Density.ToString('N1')) cells/guardian ($($grid.Spacing.ToString('N1')) cells spacing)" -ForegroundColor $(if ($grid.Name -eq "768x768") { "Red" } else { "Gray" })
}

Write-Host "`n3. Harmonic analysis..." -ForegroundColor Yellow

# Check if 768 has problematic factors
$size = 768
Write-Host "   Prime factorization of 768:" -ForegroundColor Gray

$factors = @()
$n = $size
for ($i = 2; $i -le [math]::Sqrt($n); $i++) {
    while ($n % $i -eq 0) {
        $factors += $i
        $n = $n / $i
    }
}
if ($n -gt 1) { $factors += $n }

Write-Host "   768 = $($factors -join ' × ')" -ForegroundColor Gray
Write-Host "   = 3 × 256 = 3 × 2⁸" -ForegroundColor Gray

# Compare with other sizes
Write-Host "`n   Other sizes:" -ForegroundColor Gray
Write-Host "   1024 = 2¹⁰" -ForegroundColor Gray
Write-Host "   896 = 7 × 128 = 7 × 2⁷" -ForegroundColor Gray  
Write-Host "   640 = 5 × 128 = 5 × 2⁷" -ForegroundColor Gray
Write-Host "   512 = 2⁹" -ForegroundColor Gray

Write-Host "`n4. Hypothesis testing..." -ForegroundColor Yellow

Write-Host "   Hypothesis 1: 3×256 creates standing wave interference" -ForegroundColor White
Write-Host "     - 3 might interfere with natural 2ⁿ harmonics" -ForegroundColor Gray
Write-Host "     - Could create resonance mismatch" -ForegroundColor Gray

Write-Host "`n   Hypothesis 2: ~55-cell spacing is resonant" -ForegroundColor White
Write-Host "     - Guardian spacing hits natural wavelength" -ForegroundColor Gray
Write-Host "     - Causes constructive interference → turbulence" -ForegroundColor Gray

Write-Host "`n   Hypothesis 3: 3,040 cells/guardian is turbulence threshold" -ForegroundColor White
Write-Host "     - Below this: stable (896×896: 4,138)" -ForegroundColor Gray
Write-Host "     - Above this: turbulent (768×768: 3,040)" -ForegroundColor Gray
Write-Host "     - But 640×640 (2,112) is stable - contradicts!" -ForegroundColor Yellow

Write-Host "`n   Hypothesis 4: Timescale mismatch" -ForegroundColor White
Write-Host "     - Diffusion timescale doesn't match guardian dynamics" -ForegroundColor Gray
Write-Host "     - Creates phase cancellation" -ForegroundColor Gray

Write-Host "`n5. Recommended tests:" -ForegroundColor Yellow

Write-Host "   Test A: 704×704 (1024 - 320)" -ForegroundColor White
Write-Host "     - If also unstable, issue is with ~700-800 range" -ForegroundColor Gray

Write-Host "`n   Test B: 832×832 (1024 - 192)" -ForegroundColor White
Write-Host "     - If stable, confirms 768-specific issue" -ForegroundColor Gray

Write-Host "`n   Test C: Vary guardian count at 768×768" -ForegroundColor White
Write-Host "     - Test with 150 guardians (proper scaling)" -ForegroundColor Gray
Write-Host "     - See if stability returns" -ForegroundColor Gray

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "CONCLUSION" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan

Write-Host "`nMost likely: 768×768 hits a RESONANT INSTABILITY" -ForegroundColor Yellow
Write-Host "- 3 × 256 harmonic structure" -ForegroundColor White
Write-Host "- ~55-cell guardian spacing" -ForegroundColor White
Write-Host "- Creates standing wave interference" -ForegroundColor White
Write-Host "- Power constraint delays but doesn't prevent" -ForegroundColor White

Write-Host "`nFor migration: AVOID 768×768 and similar sizes" -ForegroundColor Cyan
Write-Host "Test neighboring sizes (704, 832) to map instability region" -ForegroundColor Cyan