# ============================================================================
# PATTERN ANALYZER - Analyze 1-hour test results
# Looks for: Entropy evolution, spectral changes, pattern complexity
# ============================================================================

param(
    [string]$AnalyticsDir = "C:\fractal_nvme_test\analytics_1hour_*"
)

Write-Host "======================================================================="
Write-Host "  PATTERN ANALYZER - Fractal Habit System Potential"
Write-Host "======================================================================="
Write-Host ""

# Find the latest analytics directory
$latestDir = Get-ChildItem -Path $AnalyticsDir -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $latestDir) {
    Write-Host "ERROR: No analytics directory found"
    exit 1
}

Write-Host "Analyzing: $($latestDir.FullName)"
Write-Host ""

$summaryFile = Join-Path $latestDir.FullName "metrics\runs_summary.csv"
if (-not (Test-Path $summaryFile)) {
    Write-Host "ERROR: Summary file not found: $summaryFile"
    exit 1
}

# Read and analyze the data
$data = Import-Csv $summaryFile
$runCount = $data.Count

Write-Host "=== BASIC STATISTICS ==="
Write-Host "Total runs: $runCount"
Write-Host ""

# Convert string metrics to numbers
$entropyValues = @()
$slopeValues = @()
$peakKValues = @()
$energyValues = @()
$stepsPerSecValues = @()

foreach ($row in $data) {
    $entropyValues += [double]$row.entropy
    $slopeValues += [double]$row.slope
    $peakKValues += [int]$row.peak_k
    $energyValues += [double]$row.energy
    $stepsPerSecValues += [double]$row.steps_per_sec
}

Write-Host "=== ENTROPY ANALYSIS ==="
$entropyAvg = ($entropyValues | Measure-Object -Average).Average
$entropyMin = ($entropyValues | Measure-Object -Minimum).Minimum
$entropyMax = ($entropyValues | Measure-Object -Maximum).Maximum
$entropyStd = [math]::Sqrt(($entropyValues | ForEach-Object { ($_ - $entropyAvg) * ($_ - $entropyAvg) } | Measure-Object -Average).Average)

Write-Host "Average entropy: $([math]::Round($entropyAvg,4)) bits"
Write-Host "Range: $([math]::Round($entropyMin,4)) - $([math]::Round($entropyMax,4)) bits"
Write-Host "Standard deviation: $([math]::Round($entropyStd,4)) bits"
Write-Host "Stability: $(if ($entropyStd -lt 0.01) {'Excellent'} elseif ($entropyStd -lt 0.05) {'Good'} else {'Variable'})"
Write-Host ""

Write-Host "=== SPECTRAL ANALYSIS ==="
$slopeAvg = ($slopeValues | Measure-Object -Average).Average
$slopeMin = ($slopeValues | Measure-Object -Minimum).Minimum
$slopeMax = ($slopeValues | Measure-Object -Maximum).Maximum

Write-Host "Average slope: $([math]::Round($slopeAvg,3))"
Write-Host "Target slope (Kolmogorov -5/3): -1.667"
Write-Host "Deviation from target: $([math]::Round($slopeAvg - (-1.667),3))"
Write-Host "Slope stability: $(if (($slopeMax - $slopeMin) -lt 0.1) {'Excellent'} elseif (($slopeMax - $slopeMin) -lt 0.3) {'Good'} else {'Variable'})"
Write-Host ""

Write-Host "=== SCALE ANALYSIS ==="
$peakKAvg = ($peakKValues | Measure-Object -Average).Average
$peakKMode = ($peakKValues | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name

Write-Host "Average peak k: $([math]::Round($peakKAvg,1))"
Write-Host "Most common peak k: $peakKMode"
Write-Host "Scale preference: $(if ($peakKAvg -lt 3) {'Large scale'} elseif ($peakKAvg -lt 10) {'Medium scale'} else {'Small scale'})"
Write-Host ""

Write-Host "=== ENERGY ANALYSIS ==="
$energyAvg = ($energyValues | Measure-Object -Average).Average
$energyMin = ($energyValues | Measure-Object -Minimum).Minimum
$energyMax = ($energyValues | Measure-Object -Maximum).Maximum
$energyGrowth = ($energyMax - $energyMin) / $energyMin * 100

Write-Host "Average energy: $energyAvg"
Write-Host "Energy range: $energyMin - $energyMax"
Write-Host "Energy growth: $([math]::Round($energyGrowth,1))% over test"
Write-Host ""

Write-Host "=== PERFORMANCE ANALYSIS ==="
$perfAvg = ($stepsPerSecValues | Measure-Object -Average).Average
$perfMin = ($stepsPerSecValues | Measure-Object -Minimum).Minimum
$perfMax = ($stepsPerSecValues | Measure-Object -Maximum).Maximum
$perfStd = [math]::Sqrt(($stepsPerSecValues | ForEach-Object { ($_ - $perfAvg) * ($_ - $perfAvg) } | Measure-Object -Average).Average)

Write-Host "Average performance: $([math]::Round($perfAvg,0)) steps/sec"
Write-Host "Performance range: $([math]::Round($perfMin,0)) - $([math]::Round($perfMax,0)) steps/sec"
Write-Host "Performance stability: $(if ($perfStd -lt 50) {'Excellent'} elseif ($perfStd -lt 100) {'Good'} else {'Variable'})"
Write-Host ""

Write-Host "=== PATTERN COMPLEXITY ANALYSIS ==="
# Calculate pattern complexity (entropy variation over time)
$entropyComplexity = 0
for ($i = 1; $i -lt $entropyValues.Count; $i++) {
    $entropyComplexity += [math]::Abs($entropyValues[$i] - $entropyValues[$i-1])
}
$entropyComplexity = $entropyComplexity / ($entropyValues.Count - 1)

Write-Host "Entropy complexity score: $([math]::Round($entropyComplexity,4))"
Write-Host "Pattern type: $(if ($entropyComplexity -lt 0.01) {'Static'} elseif ($entropyComplexity -lt 0.05) {'Stable'} elseif ($entropyComplexity -lt 0.1) {'Dynamic'} else {'Chaotic'})"
Write-Host ""

Write-Host "=== SYSTEM POTENTIAL ASSESSMENT ==="
Write-Host ""

# Assess system potential based on metrics
$potentialScore = 0
if ($entropyStd -lt 0.01) { $potentialScore += 25 } # Stability
if ([math]::Abs($slopeAvg - (-1.667)) -lt 0.1) { $potentialScore += 25 } # Turbulence
if ($perfStd -lt 50) { $potentialScore += 25 } # Performance consistency
if ($entropyComplexity -gt 0.02 -and $entropyComplexity -lt 0.1) { $potentialScore += 25 } # Dynamic but not chaotic

Write-Host "System Potential Score: $potentialScore/100"
Write-Host "Assessment: $(if ($potentialScore -ge 90) {'Excellent - High potential'} elseif ($potentialScore -ge 70) {'Good - Solid foundation'} elseif ($potentialScore -ge 50) {'Moderate - Needs optimization'} else {'Low - Requires improvement'})"
Write-Host ""

Write-Host "=== RECOMMENDATIONS ==="
Write-Host ""

if ($entropyAvg -lt 6.0) {
    Write-Host "1. Increase noise amplitude to reach 6.75+ bits entropy (match the-craw)"
}
if ([math]::Abs($slopeAvg - (-1.667)) -gt 0.2) {
    Write-Host "2. Adjust parameters to approach Kolmogorov -5/3 slope"
}
if ($peakKAvg -lt 3) {
    Write-Host "3. Consider multi-scale injection to excite smaller scales"
}
if ($entropyComplexity -lt 0.01) {
    Write-Host "4. Introduce intermittent forcing to increase pattern complexity"
}

Write-Host ""
Write-Host "=== COMPARISON WITH THE-CRAW ==="
Write-Host "the-craw metrics: 6.753 bits entropy, 512×512 grid"
Write-Host "Beast metrics: $([math]::Round($entropyAvg,3)) bits entropy, 1024×1024 grid (4× larger)"
Write-Host "Entropy difference: $([math]::Round(6.753 - $entropyAvg,3)) bits"
Write-Host "Grid scaling factor: 4×"
Write-Host ""

Write-Host "======================================================================="
Write-Host "  ANALYSIS COMPLETE"
Write-Host "======================================================================="