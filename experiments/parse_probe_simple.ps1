# Simple probe parser
$inputFile = "probe_output_20260311_220349.txt"
$outputCSV = "probe_final_data.csv"

Write-Host "Parsing: $inputFile"
Write-Host "Output: $outputCSV"

# Read and clean ANSI codes
$content = Get-Content $inputFile -Raw
$cleanContent = $content -replace '\x1b\[[0-9;]*[a-zA-Z]', ''
$lines = $cleanContent -split "`n"

# Write CSV header
"Cycle,Time,Omega,Enstrophy,RhoMin,RhoMax,Power,Guardians,Mass,MTotal,Probe" | Out-File $outputCSV -Encoding UTF8

$cycles = @()
foreach ($line in $lines) {
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
        
        "$($cycle.Cycle),$($cycle.Time),$($cycle.Omega),$($cycle.Enstrophy),$($cycle.RhoMin),$($cycle.RhoMax),$($cycle.Power),$($cycle.Guardians),$($cycle.Mass),$($cycle.MTotal),$($cycle.Probe)" | Out-File $outputCSV -Append -Encoding UTF8
    }
}

Write-Host "`n=== PROBE ANALYTICS RESULTS ==="
Write-Host "Total cycles captured: $($cycles.Count)"

if ($cycles.Count -gt 0) {
    $first = $cycles[0]
    $last = $cycles[-1]
    
    Write-Host "First cycle: $($first.Cycle)"
    Write-Host "Last cycle: $($last.Cycle)"
    Write-Host "Omega: $($first.Omega) to $($last.Omega)"
    Write-Host "Mass: $($first.Mass) to $($last.Mass)"
    Write-Host "Guardians: $($first.Guardians) to $($last.Guardians)"
    Write-Host "Probe phases: $($first.Probe) to $($last.Probe)"
    
    # Check completion
    if ($last.Cycle -ge 1700) {
        Write-Host "`n✅ SUCCESS: Reached 1700 cycles!" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️  INCOMPLETE: Stopped at cycle $($last.Cycle) of 1700" -ForegroundColor Yellow
        
        # Check for crash in SILENT probe
        if ($last.Cycle -ge 1100 -and $last.Cycle -le 1199 -and $last.Probe -eq "SILENT") {
            Write-Host "🔴 SILENT PROBE CRASH: Expected crash at cycle ~1112" -ForegroundColor Red
        }
    }
    
    # Save summary
    $summary = @"
PROBE RUN SUMMARY
=================
Run completed: $(Get-Date)
Data file: $outputCSV

CYCLES: $($cycles.Count) total
Range: $($first.Cycle) to $($last.Cycle)
Target: 1700 cycles
Status: $(if ($last.Cycle -ge 1700) { "COMPLETE" } else { "INCOMPLETE (stopped at $($last.Cycle))" })

KEY METRICS:
- Omega: $($first.Omega) → $($last.Omega)
- Mass: $($first.Mass) → $($last.Mass)
- Guardians: $($first.Guardians) → $($last.Guardians)
- Final probe: $($last.Probe)

PROBE PHASES:
- Probe A (600-649 INJ): $(($cycles | Where-Object { $_.Cycle -ge 600 -and $_.Cycle -le 649 -and $_.Probe -eq "INJ" }).Count) cycles
- Probe B (800): $(($cycles | Where-Object { $_.Cycle -eq 800 }).Count) cycles
- Probe C (1100-1199 SILENT): $(($cycles | Where-Object { $_.Cycle -ge 1100 -and $_.Cycle -le 1199 -and $_.Probe -eq "SILENT" }).Count) cycles
- Probe D (1400-1499): $(($cycles | Where-Object { $_.Cycle -ge 1400 -and $_.Cycle -le 1499 }).Count) cycles

NOTES:
$(if ($last.Cycle -ge 1100 -and $last.Cycle -le 1199 -and $last.Probe -eq "SILENT") {
    "• CRASH DETECTED in SILENT probe (cycles 1100-1199)"
    "• Expected crash at cycle ~1112 when omega locked at 1.25"
} else {
    "• No crash detected in captured data"
    "• Program stopped before reaching crash zone (1100-1199)"
})
"@
    
    $summary | Out-File "probe_summary.txt" -Encoding UTF8
    Write-Host "`nSummary saved to: probe_summary.txt"
}

Write-Host "`nCSV data saved to: $outputCSV"