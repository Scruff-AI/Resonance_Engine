# Detailed Probe Data Analysis
# Extract and analyze patterns from probe output

$probeFile = "probe_output_20260311_220349.txt"
$analysisFile = "detailed_probe_analysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

if (-not (Test-Path $probeFile)) {
    Write-Host "Probe file not found: $probeFile" -ForegroundColor Red
    exit 1
}

# Read the probe file
$content = Get-Content $probeFile -Raw

# Extract cycle data using regex
$cyclePattern = '\s*(\d+)\s*\|\s*(\d+:\d+:\d+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.e\+\-]+)\s*\|\s*\[([\d\.]+),([\d\.]+)\]\s*\|\s*([\d\.e\+\-]+)\s*\|\s*(\d+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.]+)\s*\|\s*(\w+)'

$matches = [regex]::Matches($content, $cyclePattern)

Write-Host "Found $($matches.Count) cycle records in probe output" -ForegroundColor Green

# Parse matches into objects
$cycles = @()
foreach ($match in $matches) {
    $cycle = [PSCustomObject]@{
        Cycle = [int]$match.Groups[1].Value
        Time = $match.Groups[2].Value
        Omega = [float]$match.Groups[3].Value
        SpeedRange = $match.Groups[4].Value
        RhoMin = [float]$match.Groups[5].Value
        RhoMax = [float]$match.Groups[6].Value
        Enstrophy = $match.Groups[7].Value
        Guardians = [int]$match.Groups[8].Value
        Mass = [float]$match.Groups[9].Value
        MTotal = [float]$match.Groups[10].Value
        Probe = $match.Groups[11].Value
    }
    $cycles += $cycle
}

# Extract guardian creation events
$guardianPattern = '\*\* NEW GUARDIAN.*?cy0 b(\d+).*?\((\d+),(\d+)\).*?rho=([\d\.]+).*?accreted=([\d\.]+).*?total=(\d+)'
$guardianMatches = [regex]::Matches($content, $guardianPattern)

Write-Host "Found $($guardianMatches.Count) guardian creation events" -ForegroundColor Green

$guardians = @()
foreach ($match in $guardianMatches) {
    $guardian = [PSCustomObject]@{
        Batch = [int]$match.Groups[1].Value
        X = [int]$match.Groups[2].Value
        Y = [int]$match.Groups[3].Value
        Rho = [float]$match.Groups[4].Value
        Accreted = [float]$match.Groups[5].Value
        Total = [int]$match.Groups[6].Value
    }
    $guardians += $guardian
}

# Extract ghost particle data
$ghostPattern = '#(\d+)\s+pos\(\s*([\d\.]+),\s*([\d\.]+)\)\s+mass=([\d\.]+)\s+latent=([\d\.e\+\-]+)\s+delta=([\+\-][\d\.e\+\-]+)\s+(\w+)'
$ghostMatches = [regex]::Matches($content, $ghostPattern)

Write-Host "Found $($ghostMatches.Count) ghost particle records" -ForegroundColor Green

$ghosts = @()
foreach ($match in $ghostMatches) {
    $ghost = [PSCustomObject]@{
        Index = [int]$match.Groups[1].Value
        X = [float]$match.Groups[2].Value
        Y = [float]$match.Groups[3].Value
        Mass = [float]$match.Groups[4].Value
        Latent = $match.Groups[5].Value
        Delta = $match.Groups[6].Value
        State = $match.Groups[7].Value
    }
    $ghosts += $ghost
}

# Analyze patterns
Write-Host "`n=== CYCLE DATA ANALYSIS ===" -ForegroundColor Cyan

if ($cycles.Count -gt 0) {
    # Calculate statistics
    $firstCycle = $cycles[0].Cycle
    $lastCycle = $cycles[-1].Cycle
    $cycleRange = $lastCycle - $firstCycle + 1
    
    $avgOmega = ($cycles | Measure-Object -Property Omega -Average).Average
    $minOmega = ($cycles | Measure-Object -Property Omega -Minimum).Minimum
    $maxOmega = ($cycles | Measure-Object -Property Omega -Maximum).Maximum
    
    $avgMass = ($cycles | Measure-Object -Property Mass -Average).Average
    $minMass = ($cycles | Measure-Object -Property Mass -Minimum).Minimum
    $maxMass = ($cycles | Measure-Object -Property Mass -Maximum).Maximum
    
    $avgMTotal = ($cycles | Measure-Object -Property MTotal -Average).Average
    
    $uniqueProbes = $cycles.Probe | Sort-Object -Unique
    
    Write-Host "Cycle Range: $firstCycle to $lastCycle ($cycleRange cycles)" -ForegroundColor Yellow
    Write-Host "Omega: Avg=$($avgOmega.ToString('F4')), Min=$($minOmega.ToString('F4')), Max=$($maxOmega.ToString('F4'))" -ForegroundColor Yellow
    Write-Host "Mass: Avg=$($avgMass.ToString('F2')), Min=$($minMass.ToString('F2')), Max=$($maxMass.ToString('F2'))" -ForegroundColor Yellow
    Write-Host "MTotal: Avg=$($avgMTotal.ToString('F2'))" -ForegroundColor Yellow
    Write-Host "Unique Probe States: $($uniqueProbes -join ', ')" -ForegroundColor Yellow
    
    # Check for probe events
    $probeA = $cycles | Where-Object { $_.Cycle -ge 600 -and $_.Cycle -le 649 }
    $probeB = $cycles | Where-Object { $_.Cycle -eq 800 }
    $probeC = $cycles | Where-Object { $_.Cycle -ge 1100 -and $_.Cycle -le 1199 }
    $probeD = $cycles | Where-Object { $_.Cycle -ge 1400 -and $_.Cycle -le 1499 }
    
    Write-Host "`nProbe Events in Data:" -ForegroundColor Cyan
    Write-Host "  Probe A (600-649): $($probeA.Count) cycles found" -ForegroundColor Yellow
    Write-Host "  Probe B (800): $($probeB.Count) cycles found" -ForegroundColor Yellow
    Write-Host "  Probe C (1100-1199): $($probeC.Count) cycles found" -ForegroundColor Yellow
    Write-Host "  Probe D (1400-1499): $($probeD.Count) cycles found" -ForegroundColor Yellow
    
    # Check for stability
    $omegaStable = $cycles | Where-Object { $_.Omega -ge 0.6 -and $_.Omega -le 1.95 }
    $omegaUnstable = $cycles | Where-Object { $_.Omega -lt 0.6 -or $_.Omega -gt 1.95 }
    
    Write-Host "`nStability Analysis:" -ForegroundColor Cyan
    Write-Host "  Stable Omega: $($omegaStable.Count) cycles" -ForegroundColor Green
    if ($omegaUnstable.Count -gt 0) {
        Write-Host "  Unstable Omega: $($omegaUnstable.Count) cycles" -ForegroundColor Red
        foreach ($unstable in $omegaUnstable | Select-Object -First 3) {
            Write-Host "    Cycle $($unstable.Cycle): Omega=$($unstable.Omega)" -ForegroundColor Red
        }
    }
}

Write-Host "`n=== GUARDIAN ANALYSIS ===" -ForegroundColor Cyan

if ($guardians.Count -gt 0) {
    $firstGuardian = $guardians[0]
    $lastGuardian = $guardians[-1]
    
    $avgRho = ($guardians | Measure-Object -Property Rho -Average).Average
    $minRho = ($guardians | Measure-Object -Property Rho -Minimum).Minimum
    $maxRho = ($guardians | Measure-Object -Property Rho -Maximum).Maximum
    
    $avgAccreted = ($guardians | Measure-Object -Property Accreted -Average).Average
    
    Write-Host "Total Guardians Created: $($guardians.Count)" -ForegroundColor Yellow
    Write-Host "Guardian Creation Range: Batch $($firstGuardian.Batch) to $($lastGuardian.Batch)" -ForegroundColor Yellow
    Write-Host "Rho at Creation: Avg=$($avgRho.ToString('F5')), Min=$($minRho.ToString('F5')), Max=$($maxRho.ToString('F5'))" -ForegroundColor Yellow
    Write-Host "Average Accreted Mass: $($avgAccreted.ToString('F4'))" -ForegroundColor Yellow
    
    # Spatial distribution
    $avgX = ($guardians | Measure-Object -Property X -Average).Average
    $avgY = ($guardians | Measure-Object -Property Y -Average).Average
    $stdX = [Math]::Sqrt(($guardians | ForEach-Object { ($_.X - $avgX) * ($_.X - $avgX) } | Measure-Object -Sum).Sum / $guardians.Count)
    $stdY = [Math]::Sqrt(($guardians | ForEach-Object { ($_.Y - $avgY) * ($_.Y - $avgY) } | Measure-Object -Sum).Sum / $guardians.Count)
    
    Write-Host "`nSpatial Distribution:" -ForegroundColor Cyan
    Write-Host "  Average Position: ($($avgX.ToString('F1')), $($avgY.ToString('F1')))" -ForegroundColor Yellow
    Write-Host "  Standard Deviation: X=$($stdX.ToString('F1')), Y=$($stdY.ToString('F1'))" -ForegroundColor Yellow
    Write-Host "  Grid Coverage: $([Math]::Round($stdX/256*100,1))% X, $([Math]::Round($stdY/256*100,1))% Y" -ForegroundColor Yellow
}

Write-Host "`n=== GHOST PARTICLE ANALYSIS ===" -ForegroundColor Cyan

if ($ghosts.Count -gt 0) {
    $avgGhostX = ($ghosts | Measure-Object -Property X -Average).Average
    $avgGhostY = ($ghosts | Measure-Object -Property Y -Average).Average
    $avgGhostMass = ($ghosts | Measure-Object -Property Mass -Average).Average
    
    $uniqueStates = $ghosts.State | Sort-Object -Unique
    
    Write-Host "Total Ghost Particles: $($ghosts.Count)" -ForegroundColor Yellow
    Write-Host "Average Position: ($($avgGhostX.ToString('F1')), $($avgGhostY.ToString('F1')))" -ForegroundColor Yellow
    Write-Host "Average Mass: $($avgGhostMass.ToString('F2'))" -ForegroundColor Yellow
    Write-Host "Unique States: $($uniqueStates -join ', ')" -ForegroundColor Yellow
    
    # Check for PULSE states
    $pulseParticles = $ghosts | Where-Object { $_.State -eq "PULSE" }
    if ($pulseParticles.Count -gt 0) {
        Write-Host "PULSE Particles: $($pulseParticles.Count) (first 5 positions)" -ForegroundColor Magenta
        foreach ($pulse in $pulseParticles | Select-Object -First 5) {
            Write-Host "  #$($pulse.Index): ($($pulse.X.ToString('F1')), $($pulse.Y.ToString('F1'))) mass=$($pulse.Mass)" -ForegroundColor Magenta
        }
    }
}

# Export data to CSV
if ($cycles.Count -gt 0) {
    $cycles | Export-Csv -Path $analysisFile -NoTypeInformation
    Write-Host "`nData exported to: $analysisFile" -ForegroundColor Green
}

# Create summary report
$summaryFile = "probe_summary_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$summary = @"
=== PROBE DATA FORENSIC ANALYSIS SUMMARY ===
Analysis Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

CYCLE DATA:
  Total Cycles Found: $($cycles.Count)
  Cycle Range: $firstCycle to $lastCycle
  Average Omega: $($avgOmega.ToString('F4'))
  Average Mass: $($avgMass.ToString('F2'))
  Average MTotal: $($avgMTotal.ToString('F2'))
  Probe States: $($uniqueProbes -join ', ')

GUARDIAN DATA:
  Total Guardians Created: $($guardians.Count)
  Average Creation Rho: $($avgRho.ToString('F5'))
  Spatial Distribution: Avg($($avgX.ToString('F1')), $($avgY.ToString('F1'))) ±($($stdX.ToString('F1')), $($stdY.ToString('F1')))

GHOST PARTICLE DATA:
  Total Ghost Particles: $($ghosts.Count)
  Average Position: ($($avgGhostX.ToString('F1')), $($avgGhostY.ToString('F1')))
  Average Mass: $($avgGhostMass.ToString('F2'))

KEY FINDINGS:
1. Grid Size: 256×256 (scaled from 1024×1024)
2. Guardian Count: $($guardians.Count) (expected: 12.125, actual: $($guardians.Count))
3. Guardian Density: $(($guardians.Count/65536).ToString('E6')) (original: 1.850128E-004)
4. Power Efficiency: ~25% of expected (37W vs expected 9.375W for 1/16 area)
5. Stability: $(if ($omegaUnstable.Count -eq 0) {"All cycles stable"} else {"$($omegaUnstable.Count) unstable cycles"})

RECOMMENDATIONS:
1. Investigate power scaling discrepancy
2. Verify guardian parameter scaling
3. Check for non-linear effects at small grid sizes
4. Monitor for stability boundary effects (grid size 256 ≤ stability boundary 768)
"@

$summary | Out-File -FilePath $summaryFile
Write-Host "`nSummary report saved to: $summaryFile" -ForegroundColor Green