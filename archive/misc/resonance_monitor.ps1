# Resonance Metrics Monitor v0.13 - Clean rewrite
# Run from: D:\fractal-brain\beast-build

param([int]$RefreshMs = 500)

$Host.UI.RawUI.WindowTitle = 'KAELARA RESONANCE MONITOR'

$KpiFile = Join-Path $PSScriptRoot 'KAELARA_LIVE_KPI.log'
$ConsoleLog = Join-Path $PSScriptRoot 'KAELARA_LIVE_BRIDGE.log'

$KpiLastLine = 0
$LogLastLine = 0

$script:A = $null
$script:C = $null
$script:Att = $null
$script:T = $null
$script:Gate = $null
$script:CycleNum = $null
$script:Source = 'NONE'

$script:History = [System.Collections.ArrayList]::new()
$script:ResonantCount = 0
$script:TotalCount = 0
$script:StartTime = Get-Date

function Show-Dashboard {
    Clear-Host
    $elapsed = ((Get-Date) - $script:StartTime).ToString('hh\:mm\:ss')

    Write-Host ''
    Write-Host '  +----------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host '  |     KAELARA RESONANCE SPECTROGRAPH v0.13     |' -ForegroundColor Cyan
    Write-Host '  +----------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host ''

    if ($null -eq $script:A) {
        Write-Host '  Waiting for data...' -ForegroundColor DarkGray
        Write-Host ('  KPI:      ' + $script:KpiFile) -ForegroundColor DarkGray
        Write-Host ('  Fallback: ' + $script:ConsoleLog) -ForegroundColor DarkGray
        return
    }

    # Gate color
    $gc = 'Yellow'
    if ($script:Gate -eq 'RESONANT') { $gc = 'Green' }
    if ($script:Gate -eq 'FORCED') { $gc = 'Red' }
    if ($script:Gate -eq 'INPUT_ECHO') { $gc = 'Red' }

    # Physics section
    Write-Host '  PHYSICS' -ForegroundColor DarkGray
    if ($script:CycleNum) {
        Write-Host ('    Daemon Cycle:  ' + $script:CycleNum) -ForegroundColor DarkGray
    }
    Write-Host ('    Asymmetry:     ' + $script:A) -ForegroundColor White
    Write-Host ('    Coherence:     ' + $script:C) -ForegroundColor White

    # Coherence bar
    $cf = 0.0
    try { $cf = [float]$script:C } catch { $cf = 0.0 }
    $blen = [Math]::Min(30, [Math]::Max(0, [int]($cf * 30)))
    $bar = ('#' * $blen) + ('.' * (30 - $blen))
    $bc = 'Red'
    if ($cf -gt 0.8) { $bc = 'Green' }
    elseif ($cf -gt 0.6) { $bc = 'Yellow' }
    Write-Host '    Stability:     [' -NoNewline
    Write-Host $bar -NoNewline -ForegroundColor $bc
    Write-Host ('] ' + $script:C)

    # Engine section
    Write-Host ''
    Write-Host '  ENGINE' -ForegroundColor DarkGray
    Write-Host ('    Temperature:   ' + $script:T) -ForegroundColor White
    Write-Host ('    Attempts:      ' + $script:Att) -ForegroundColor White
    Write-Host '    Gate:          ' -NoNewline
    Write-Host $script:Gate -ForegroundColor $gc

    # Stats section
    Write-Host ''
    Write-Host '  SESSION STATS' -ForegroundColor DarkGray
    $rate = 0
    if ($script:TotalCount -gt 0) {
        $rate = [Math]::Round(100 * $script:ResonantCount / $script:TotalCount, 1)
    }
    $rc2 = 'Red'
    if ($rate -gt 70) { $rc2 = 'Green' }
    elseif ($rate -gt 40) { $rc2 = 'Yellow' }
    Write-Host ('    Cycles:        ' + $script:TotalCount) -ForegroundColor White
    Write-Host '    Resonant:      ' -NoNewline
    Write-Host ($script:ResonantCount.ToString() + ' (' + $rate.ToString() + '%)') -ForegroundColor $rc2
    Write-Host ('    Elapsed:       ' + $elapsed) -ForegroundColor DarkGray
    Write-Host ('    Source:        ' + $script:Source) -ForegroundColor DarkGray

    # Recent history
    if ($script:History.Count -gt 0) {
        Write-Host ''
        Write-Host '  RECENT' -ForegroundColor DarkGray
        $recent = $script:History | Select-Object -Last 5
        foreach ($r in $recent) {
            $clr = 'Yellow'
            if ($r.Gate -eq 'RESONANT') { $clr = 'Green' }
            $line = '    A=' + $r.A + ' C=' + $r.C + ' T=' + $r.T + ' att=' + $r.Att + ' '
            Write-Host $line -NoNewline -ForegroundColor DarkGray
            Write-Host $r.Gate -ForegroundColor $clr
        }
    }
}

Write-Host 'Starting monitor - press Ctrl+C to exit' -ForegroundColor DarkGray

while ($true) {
    $Updated = $false

    # SOURCE 1: KPI file (pipe-delimited, one line per cycle)
    if (Test-Path $KpiFile) {
        $Lines = @(Get-Content $KpiFile)
        if ($Lines.Count -gt $KpiLastLine) {
            foreach ($Line in $Lines[$KpiLastLine..($Lines.Count - 1)]) {
                if ($Line -match 'Asymmetry:(?<A>[\d\.]+)\|Coherence:(?<C>[\d\.]+)\|Attempt:(?<Att>\d+)\|Temp:(?<T>[\d\.]+)\|Gate:(?<Gate>\w+)') {
                    $script:A = $Matches['A']
                    $script:C = $Matches['C']
                    $script:Att = $Matches['Att']
                    $script:T = $Matches['T']
                    $script:Gate = $Matches['Gate']
                    $script:Source = 'KPI'
                    $script:TotalCount++
                    if ($script:Gate -eq 'RESONANT') { $script:ResonantCount++ }
                    [void]$script:History.Add(@{
                        A = $script:A; C = $script:C
                        T = $script:T; Att = $script:Att
                        Gate = $script:Gate
                    })
                    $Updated = $true
                }
            }
            $KpiLastLine = $Lines.Count
        }
    }

    # SOURCE 2: Console log fallback (multi-line format)
    if ((-not $Updated) -and (Test-Path $ConsoleLog)) {
        $Lines = @(Get-Content $ConsoleLog)
        if ($Lines.Count -gt $LogLastLine) {
            foreach ($Line in $Lines[$LogLastLine..($Lines.Count - 1)]) {
                if ($Line -match 'Telemetry:\s*Cycle=(?<Cyc>\d+),\s*Asym=(?<A>[\d\.]+),\s*Coh=(?<C>[\d\.]+)') {
                    $script:A = $Matches['A']
                    $script:C = $Matches['C']
                    $script:CycleNum = $Matches['Cyc']
                    $script:Source = 'LOG'
                    $Updated = $true
                }
                if ($Line -match '\[Attempt\s+(?<Att>\d+)\s*\|\s*T=(?<T>[\d\.]+)\]\s*Gate:\s*(?<Gate>\w+)') {
                    $script:Att = $Matches['Att']
                    $script:T = $Matches['T']
                    $script:Gate = $Matches['Gate']
                    $script:TotalCount++
                    if ($script:Gate -eq 'RESONANT') { $script:ResonantCount++ }
                    [void]$script:History.Add(@{
                        A = $script:A; C = $script:C
                        T = $script:T; Att = $script:Att
                        Gate = $script:Gate
                    })
                    $Updated = $true
                }
            }
            $LogLastLine = $Lines.Count
        }
    }

    if ($Updated -or ($null -eq $script:A)) {
        Show-Dashboard
    }

    Start-Sleep -Milliseconds $RefreshMs
}
