# Parse probe output and create CSV - Fixed version
param(
    [string]$InputFile = "probe_output_20260311_220349.txt",
    [string]$OutputCSV = "probe_analytics_complete_fixed.csv"
)

Write-Host "Parsing probe data from: $InputFile"
Write-Host "Output CSV: $OutputCSV"

if (-not (Test-Path $InputFile)) {
    Write-Host "Error: Input file not found: $InputFile" -ForegroundColor Red
    exit 1
}

$lines = Get-Content $InputFile
$cycles = @()

Write-Host "Found $($lines.Count) lines to process..."

# Write CSV header
"Cycle,Time,Omega,Enstrophy,RhoMin,RhoMax,Power,Guardians,Mass,MTotal,Probe" | Out-File -FilePath $OutputCSV -Encoding UTF8

$count = 0
foreach ($line in $lines) {
    # Parse cycle data lines - more flexible regex
    if ($line -match '^\s*(\d+)\s*\|\s*(\d+:\d+:\d+)\s*\|\s*([\d\.\-]+)\s*\|\s*([\d\.eE\+\-]+)\s*\|\s*\[([\d\.\-]+),([\d\.\-]+)\]\s*\|\s*([\d\.eE\+\-]+)\s*\|\s*(\d+)\s*\|\s*([\d\.\-]+)\s*\|\s*([\d\.\-]+)\s*\|\s*(\w+)') {
        $cycle = [PSCustomObject]@{
            Cycle = [int]$Matches[1]
            Time = $Matches[2]
            Omega = [float]$Matches[3]
            Enstrophy = $Matches[4]
            RhoMin = [float]$Matches[5]
            RhoMax = [float]$Matches[6]
            Power = $Matches[7]
            Guardians = [int]$Matches[8]
            Mass = [float]$Matches[9]
            MTotal = [float]$Matches[10]
            Probe = $Matches[11]
        }
        
        $cycles += $cycle
        
        # Write to CSV
        "$($cycle.Cycle),$($cycle.Time),$($cycle.Omega),$($cycle.Enstrophy),$($cycle.RhoMin),$($cycle.RhoMax),$($cycle.Power),$($cycle.Guardians),$($cycle.Mass),$($cycle.MTotal),$($cycle.Probe)" | Out-File -FilePath $OutputCSV -Append -Encoding UTF8
        
        $count++
        if ($count % 100 -eq 0) {
            Write-Host "Processed $count cycles... (last: $($cycle.Cycle))"
        }
    }
}

Write-Host "`nParsing complete!"
Write-Host "Total cycles found: $($cycles.Count)"

if ($cycles.Count -gt 0) {
    $first = $cycles[0]
    $last = $cycles[-1]
    
    Write-Host "`nFirst cycle: $($first.Cycle)"
    Write-Host "Last cycle: $($last.Cycle)"
    Write-Host "Time range: $($first.Time) to $($last.Time)"
    Write-Host "Omega range: $($first.Omega) to $($last.Omega)"
    Write-Host "Guardians: $($first.Guardians) to $($last.Guardians)"
    Write-Host "Mass: $($first.Mass) to $($last.Mass)"
    
    # Calculate statistics
    $omegaAvg = ($cycles | Measure-Object -Property Omega -Average).Average
    $massAvg = ($cycles | Measure-Object -Property Mass -Average).Average
    $guardiansAvg = ($cycles | Measure-Object -Property Guardians -Average).Average
    
    Write-Host "`nStatistics:"
    Write-Host "  Average Omega: $($omegaAvg.ToString('F4'))"
    Write-Host "  Average Mass: $($massAvg.ToString('F2'))"
    Write-Host "  Average Guardians: $($guardiansAvg.ToString('F1'))"
    
    # Check for probe phases
    $probeA = $cycles | Where-Object { $_.Cycle -ge 600 -and $_.Cycle -le 649 -and $_.Probe -eq "INJ" }
    $probeB = $cycles | Where-Object { $_.Cycle -eq 800 }
    $probeC = $cycles | Where-Object { $_.Cycle -ge 1100 -and $_.Cycle -le 1199 -and $_.Probe -eq "SILENT" }
    $probeD = $cycles | Where-Object { $_.Cycle -ge 1400 -and $_.Cycle -le 1499 }
    
    Write-Host "`nProbe phases found:"
    Write-Host "  Probe A (600-649 INJ): $($probeA.Count) cycles"
    Write-Host "  Probe B (800): $($probeB.Count) cycles"
    Write-Host "  Probe C (1100-1199 SILENT): $($probeC.Count) cycles"
    Write-Host "  Probe D (1400-1499): $($probeD.Count) cycles"
    
    # Check if reached target
    if ($last.Cycle -ge 1700) {
        Write-Host "`n✅ SUCCESS: Reached target 1700 cycles!" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️  WARNING: Only reached cycle $($last.Cycle), target was 1700" -ForegroundColor Yellow
    }
}

Write-Host "`nCSV saved to: $OutputCSV"