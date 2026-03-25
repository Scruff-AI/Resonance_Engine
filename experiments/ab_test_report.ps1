# A/B Test GitHub Integration - Push results and create tracking issue
param(
    [Parameter(Mandatory=$true)]
    [string]$TestId,
    
    [string]$Repo = "openclaw/experiments",  # Adjust to your repo
    [switch]$CreateIssue,
    [switch]$UploadArtifacts
)

$BaseDir = "D:\openclaw-local\workspace-main\ab_test_$TestId"
$ConfigFile = "$BaseDir\config.json"

if (-not (Test-Path $ConfigFile)) {
    Write-Error "Test not found: $TestId"
    exit 1
}

$Config = Get-Content $ConfigFile | ConvertFrom-Json

# Collect summary statistics
Write-Host "Collecting test results..." -ForegroundColor Cyan

$fractalMetrics = @()
$probeMetrics = @()

if (Test-Path $Config.VersionA.MetricsFile) {
    $fractalMetrics = Import-Csv $Config.VersionA.MetricsFile
}

if (Test-Path $Config.VersionB.MetricsFile) {
    $probeMetrics = Import-Csv $Config.VersionB.MetricsFile
}

# Calculate statistics
$stats = @{
    TestId = $TestId
    Duration = if ($fractalMetrics.Count -gt 0) { 
        [math]::Round(($fractalMetrics | Select-Object -Last 1).elapsed_seconds / 60, 1)
    } else { 0 }
    Fractal = @{
        Samples = $fractalMetrics.Count
        AvgPower = if ($fractalMetrics.Count -gt 0) {
            [math]::Round(($fractalMetrics | Measure-Object -Property gpu_power_w -Average).Average, 2)
        } else { 0 }
        MaxTemp = if ($fractalMetrics.Count -gt 0) {
            [math]::Round(($fractalMetrics | Measure-Object -Property gpu_temp_c -Maximum).Maximum, 1)
        } else { 0 }
        AvgMemory = if ($fractalMetrics.Count -gt 0) {
            [math]::Round(($fractalMetrics | Measure-Object -Property process_memory_mb -Average).Average, 1)
        } else { 0 }
    }
    Probe = @{
        Samples = $probeMetrics.Count
        AvgPower = if ($probeMetrics.Count -gt 0) {
            [math]::Round(($probeMetrics | Measure-Object -Property gpu_power_w -Average).Average, 2)
        } else { 0 }
        MaxTemp = if ($probeMetrics.Count -gt 0) {
            [math]::Round(($probeMetrics | Measure-Object -Property gpu_temp_c -Maximum).Maximum, 1)
        } else { 0 }
        FinalCycles = if ($probeMetrics.Count -gt 0) {
            ($probeMetrics | Select-Object -Last 1).cycles
        } else { 0 }
        FinalGuardians = if ($probeMetrics.Count -gt 0) {
            ($probeMetrics | Select-Object -Last 1).guardians
        } else { 0 }
    }
}

# Generate report
$report = @"
# A/B Test Report: $TestId

## Test Configuration
- **Started**: $($Config.StartTime)
- **Duration**: $($stats.Duration) minutes
- **Grid Size**: $($Config.VersionA.GridSize)

## Version A: Fractal Habit (Spectral Analysis)
- **Executable**: $($Config.VersionA.Executable)
- **Samples Collected**: $($stats.Fractal.Samples)
- **Average GPU Power**: $($stats.Fractal.AvgPower)W
- **Max GPU Temperature**: $($stats.Fractal.MaxTemp)°C
- **Average Memory**: $($stats.Fractal.AvgMemory)MB

## Version B: Probe (Guardian Forensics)
- **Executable**: $($Config.VersionB.Executable)
- **Samples Collected**: $($stats.Probe.Samples)
- **Average GPU Power**: $($stats.Probe.AvgPower)W
- **Max GPU Temperature**: $($stats.Probe.MaxTemp)°C
- **Final Cycles**: $($stats.Probe.FinalCycles)
- **Final Guardians**: $($stats.Probe.FinalGuardians)

## Key Findings
$(if ($stats.Probe.FinalGuardians -gt 0) { "- **Guardian Formation**: Version B successfully formed $($stats.Probe.FinalGuardians) guardians" } else { "- **Guardian Formation**: No guardians detected in Version B" })
- **Power Consumption**: Version A averaged $($stats.Fractal.AvgPower)W vs Version B $($stats.Probe.AvgPower)W
- **Thermal Profile**: Max temp $($stats.Fractal.MaxTemp)°C (A) vs $($stats.Probe.MaxTemp)°C (B)

## Artifacts
- Fractal Habit Log: \`$($Config.VersionA.LogFile)\`
- Probe Log: \`$($Config.VersionB.LogFile)\`
- Fractal Metrics: \`$($Config.VersionA.MetricsFile)\`
- Probe Metrics: \`$($Config.VersionB.MetricsFile)\`

## Next Steps
1. Analyze spectral data from Fractal Habit
2. Review guardian adaptation patterns in Probe
3. Compare stress-response metrics
4. Determine optimal configuration for migration

---
*Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")*
"@

$reportFile = "$BaseDir\AB_TEST_REPORT.md"
$report | Out-File $reportFile

Write-Host "`nReport generated: $reportFile" -ForegroundColor Green
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Test ID: $TestId" -ForegroundColor Yellow
Write-Host "Duration: $($stats.Duration) minutes" -ForegroundColor Yellow
Write-Host "Fractal Samples: $($stats.Fractal.Samples)" -ForegroundColor Yellow
Write-Host "Probe Samples: $($stats.Probe.Samples)" -ForegroundColor Yellow
Write-Host "Final Guardians: $($stats.Probe.FinalGuardians)" -ForegroundColor Yellow

# GitHub Integration
if ($CreateIssue) {
    Write-Host "`nCreating GitHub issue..." -ForegroundColor Cyan
    
    $issueTitle = "A/B Test Results: $TestId"
    $issueBody = $report
    
    # Use gh CLI to create issue
    $tempBodyFile = "$BaseDir\issue_body.txt"
    $issueBody | Out-File $tempBodyFile
    
    try {
        $result = gh issue create --repo $Repo --title $issueTitle --body-file $tempBodyFile --label "experiment,ab-test"
        Write-Host "Issue created: $result" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to create GitHub issue: $_"
    }
    
    Remove-Item $tempBodyFile -ErrorAction SilentlyContinue
}

if ($UploadArtifacts) {
    Write-Host "`nUploading artifacts to GitHub..." -ForegroundColor Cyan
    
    # Create a gist with metrics
    $gistContent = @{
        "fractal_metrics.csv" = (Get-Content $Config.VersionA.MetricsFile -Raw)
        "probe_metrics.csv" = (Get-Content $Config.VersionB.MetricsFile -Raw)
        "report.md" = $report
    } | ConvertTo-Json
    
    $gistFile = "$BaseDir\gist_content.json"
    $gistContent | Out-File $gistFile
    
    try {
        $result = gh gist create $Config.VersionA.MetricsFile $Config.VersionB.MetricsFile $reportFile --public --desc "A/B Test $TestId Metrics"
        Write-Host "Gist created: $result" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to create gist: $_"
    }
}

Write-Host "`nDone!" -ForegroundColor Green
