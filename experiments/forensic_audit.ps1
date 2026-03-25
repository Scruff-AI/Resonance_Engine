# Forensic Audit of Data - Find Differences from Original Grid
# Analyzing probe data to understand deviations from expected behavior

$auditLog = "forensic_audit_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$analysisFile = "grid_comparison_analysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

# ANSI colors
$Red = "`e[31m"
$Green = "`e[32m"
$Yellow = "`e[33m"
$Blue = "`e[34m"
$Magenta = "`e[35m"
$Cyan = "`e[36m"
$Reset = "`e[0m"

function Log-Audit {
    param($Message, $Severity = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $color = $Reset
    
    switch ($Severity) {
        "CRITICAL" { $color = $Red }
        "WARNING"  { $color = $Yellow }
        "INFO"     { $color = $Green }
        "DEBUG"    { $color = $Blue }
    }
    
    $logEntry = "[$timestamp] [$Severity] $Message"
    Write-Host "$color$logEntry$Reset"
    Add-Content -Path $auditLog -Value $logEntry
}

# Load probe data
$probeData = @()
if (Test-Path "probe_final_results.csv") {
    $csv = Import-Csv "probe_final_results.csv"
    $probeData = $csv
    Log-Audit "Loaded $($csv.Count) records from probe_final_results.csv" "INFO"
} else {
    Log-Audit "probe_final_results.csv not found" "WARNING"
}

# Load harmonic analysis for reference
$harmonicData = $null
if (Test-Path "harmonic_analysis_results.json") {
    $harmonicData = Get-Content "harmonic_analysis_results.json" | ConvertFrom-Json
    Log-Audit "Loaded harmonic analysis data" "INFO"
}

# Define expected values for original 1024×1024 grid
$originalGrid = @{
    Size = 1024
    Area = 1048576
    ExpectedGuardians = 194
    GuardianDensity = 0.0001850128173828125  # 194 / 1048576
    PowerBaseline = 150  # Watts
    GridRatio = 1.0
}

# Define actual 256×256 grid
$currentGrid = @{
    Size = 256
    Area = 65536
    ExpectedGuardians = 12.125  # 194 × (256/1024)² = 194 × 0.0625
    ActualGuardians = 13  # From probe data
    GuardianDensity = 0.0001983642578125  # 13 / 65536
    PowerBaseline = 37  # Watts (observed)
    GridRatio = 0.25  # 256/1024
}

Log-Audit "================================================================" "INFO"
Log-Audit "FORENSIC AUDIT OF DATA - GRID COMPARISON" "INFO"
Log-Audit "================================================================" "INFO"
Log-Audit "" "INFO"
Log-Audit "ORIGINAL GRID (1024×1024):" "INFO"
Log-Audit "  Size: $($originalGrid.Size)×$($originalGrid.Size)" "INFO"
Log-Audit "  Area: $($originalGrid.Area) cells" "INFO"
Log-Audit "  Expected Guardians: $($originalGrid.ExpectedGuardians)" "INFO"
Log-Audit "  Guardian Density: $($originalGrid.GuardianDensity)" "INFO"
Log-Audit "  Power Baseline: $($originalGrid.PowerBaseline)W" "INFO"
Log-Audit "" "INFO"
Log-Audit "CURRENT GRID (256×256):" "INFO"
Log-Audit "  Size: $($currentGrid.Size)×$($currentGrid.Size)" "INFO"
Log-Audit "  Area: $($currentGrid.Area) cells" "INFO"
Log-Audit "  Expected Guardians: $($currentGrid.ExpectedGuardians) (scaled)" "INFO"
Log-Audit "  Actual Guardians: $($currentGrid.ActualGuardians)" "INFO"
Log-Audit "  Guardian Density: $($currentGrid.GuardianDensity)" "INFO"
Log-Audit "  Power Baseline: $($currentGrid.PowerBaseline)W (observed)" "INFO"
Log-Audit "  Grid Ratio: $($currentGrid.GridRatio) (1/4 linear, 1/16 area)" "INFO"
Log-Audit "" "INFO"

# Calculate differences
$guardianDifference = $currentGrid.ActualGuardians - $currentGrid.ExpectedGuardians
$densityDifference = $currentGrid.GuardianDensity - $originalGrid.GuardianDensity
$densityRatio = $currentGrid.GuardianDensity / $originalGrid.GuardianDensity
$powerRatio = $currentGrid.PowerBaseline / $originalGrid.PowerBaseline
$areaRatio = $currentGrid.Area / $originalGrid.Area

Log-Audit "ANALYSIS OF DIFFERENCES:" "INFO"
Log-Audit "================================================================" "INFO"
Log-Audit "1. Guardian Count:" "INFO"
Log-Audit "   Expected (scaled): $($currentGrid.ExpectedGuardians)" "INFO"
Log-Audit "   Actual: $($currentGrid.ActualGuardians)" "INFO"
Log-Audit "   Difference: $guardianDifference guardians" "INFO"
Log-Audit "   Percentage: $(($guardianDifference/$currentGrid.ExpectedGuardians*100).ToString('F2'))%" "INFO"

Log-Audit "" "INFO"
Log-Audit "2. Guardian Density:" "INFO"
Log-Audit "   Original: $($originalGrid.GuardianDensity.ToString('E6'))" "INFO"
Log-Audit "   Current: $($currentGrid.GuardianDensity.ToString('E6'))" "INFO"
Log-Audit "   Difference: $($densityDifference.ToString('E6'))" "INFO"
Log-Audit "   Ratio (Current/Original): $($densityRatio.ToString('F4'))" "INFO"

Log-Audit "" "INFO"
Log-Audit "3. Power Scaling:" "INFO"
Log-Audit "   Original: $($originalGrid.PowerBaseline)W" "INFO"
Log-Audit "   Current: $($currentGrid.PowerBaseline)W" "INFO"
Log-Audit "   Ratio: $($powerRatio.ToString('F4')) (expected: $areaRatio)" "INFO"
Log-Audit "   Efficiency: $(($areaRatio/$powerRatio*100).ToString('F1'))% of expected" "INFO"

Log-Audit "" "INFO"
Log-Audit "4. Area Scaling:" "INFO"
Log-Audit "   Linear scaling: $($currentGrid.GridRatio) (1/4)" "INFO"
Log-Audit "   Area scaling: $areaRatio (1/16)" "INFO"

# Analyze probe data patterns
if ($probeData.Count -gt 0) {
    Log-Audit "" "INFO"
    Log-Audit "PROBE DATA ANALYSIS:" "INFO"
    Log-Audit "================================================================" "INFO"
    
    # Convert to proper types
    $typedData = @()
    foreach ($row in $probeData) {
        $typedData += [PSCustomObject]@{
            Cycle = [int]$row.Cycle
            Time = $row.Time
            Omega = [float]$row.Omega
            Enstrophy = $row.Enstrophy
            RhoMin = [float]$row.RhoMin
            RhoMax = [float]$row.RhoMax
            Power = $row.Power
            Guardians = [int]$row.Guardians
            Mass = [float]$row.Mass
            MTotal = [float]$row.MTotal
            Probe = $row.Probe
        }
    }
    
    # Find anomalies
    $omegaAnomalies = $typedData | Where-Object { $_.Omega -lt 0.6 -or $_.Omega -gt 1.95 }
    $guardianChanges = $typedData | Where-Object { $_.Guardians -ne $currentGrid.ActualGuardians }
    $massSpikes = $typedData | Where-Object { $_.Mass -gt 100 }
    
    Log-Audit "Data Range: Cycles $($typedData[0].Cycle) to $($typedData[-1].Cycle)" "INFO"
    Log-Audit "Total Records: $($typedData.Count)" "INFO"
    
    if ($omegaAnomalies.Count -gt 0) {
        Log-Audit "Omega Anomalies Found: $($omegaAnomalies.Count) records outside [0.6, 1.95]" "WARNING"
        foreach ($anom in $omegaAnomalies | Select-Object -First 3) {
            Log-Audit "  Cycle $($anom.Cycle): Omega = $($anom.Omega)" "WARNING"
        }
    } else {
        Log-Audit "Omega Values: All within normal range [0.6, 1.95]" "INFO"
    }
    
    if ($guardianChanges.Count -gt 0) {
        Log-Audit "Guardian Count Changes: $($guardianChanges.Count) records" "WARNING"
        $uniqueCounts = $guardianChanges.Guardians | Sort-Object -Unique
        Log-Audit "  Unique guardian counts: $($uniqueCounts -join ', ')" "WARNING"
    } else {
        Log-Audit "Guardian Count: Stable at $($currentGrid.ActualGuardians)" "INFO"
    }
    
    if ($massSpikes.Count -gt 0) {
        Log-Audit "Mass Spikes Found: $($massSpikes.Count) records with mass > 100" "CRITICAL"
    } else {
        $maxMass = ($typedData | Measure-Object -Property Mass -Maximum).Maximum
        Log-Audit "Mass Range: 0 to $($maxMass.ToString('F2')) (no spikes)" "INFO"
    }
    
    # Calculate statistics
    $avgOmega = ($typedData | Measure-Object -Property Omega -Average).Average
    $avgPower = ($typedData | ForEach-Object { [double]$_.Power } | Measure-Object -Average).Average
    $avgMass = ($typedData | Measure-Object -Property Mass -Average).Average
    
    Log-Audit "" "INFO"
    Log-Audit "STATISTICAL SUMMARY:" "INFO"
    Log-Audit "  Average Omega: $($avgOmega.ToString('F4'))" "INFO"
    Log-Audit "  Average Power: $($avgPower.ToString('E3'))" "INFO"
    Log-Audit "  Average Mass: $($avgMass.ToString('F2'))" "INFO"
    Log-Audit "  Average MTotal: $(($typedData | Measure-Object -Property MTotal -Average).Average.ToString('F2'))" "INFO"
}

# Check harmonic analysis for grid size relationships
if ($harmonicData) {
    Log-Audit "" "INFO"
    Log-Audit "HARMONIC ANALYSIS INTEGRATION:" "INFO"
    Log-Audit "================================================================" "INFO"
    
    $currentSizeIndex = $harmonicData.grid_sizes.IndexOf($currentGrid.Size)
    if ($currentSizeIndex -ge 0) {
        $harmonicFraction = $harmonicData.harmonic_fractions[$currentSizeIndex]
        $musicalInterval = $harmonicData.musical_intervals[$currentSizeIndex]
        
        Log-Audit "Grid Size $($currentGrid.Size) corresponds to:" "INFO"
        Log-Audit "  Harmonic Fraction: $harmonicFraction" "INFO"
        Log-Audit "  Musical Interval: $musicalInterval" "INFO"
        
        # Check if we're near stability boundary
        $stabilityBoundary = $harmonicData.critical_thresholds.stability_boundary
        if ($currentGrid.Size -le $stabilityBoundary) {
            Log-Audit "  WARNING: Grid size is at or below stability boundary ($stabilityBoundary)" "WARNING"
        }
    }
}

Log-Audit "" "INFO"
Log-Audit "FORENSIC AUDIT COMPLETE" "INFO"
Log-Audit "================================================================" "INFO"

# Export analysis to CSV
$analysisResults = [PSCustomObject]@{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    OriginalGridSize = $originalGrid.Size
    CurrentGridSize = $currentGrid.Size
    ExpectedGuardians = $currentGrid.ExpectedGuardians
    ActualGuardians = $currentGrid.ActualGuardians
    GuardianDifference = $guardianDifference
    OriginalDensity = $originalGrid.GuardianDensity
    CurrentDensity = $currentGrid.GuardianDensity
    DensityRatio = $densityRatio
    OriginalPower = $originalGrid.PowerBaseline
    CurrentPower = $currentGrid.PowerBaseline
    PowerRatio = $powerRatio
    AreaRatio = $areaRatio
    EfficiencyPercentage = ($areaRatio/$powerRatio*100)
    AuditFindings = "See log for details"
}

$analysisResults | Export-Csv -Path $analysisFile -NoTypeInformation
Log-Audit "Analysis exported to: $analysisFile" "INFO"
Log-Audit "Audit log saved to: $auditLog" "INFO"