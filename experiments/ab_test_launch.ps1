# A/B Test Launcher - Starts both versions and monitoring
param(
    [switch]$SkipFractalHabit,
    [switch]$SkipProbe,
    [int]$MonitorInterval = 5
)

$ErrorActionPreference = "Stop"

# Step 1: Setup
Write-Host "`n=== A/B TEST SETUP ===" -ForegroundColor Cyan
$setupResult = & "D:\openclaw-local\workspace-main\ab_test_setup.ps1"
$TestId = $setupResult.TestId
$BaseDir = "D:\openclaw-local\workspace-main\ab_test_$TestId"

Write-Host "`nTest ID: $TestId" -ForegroundColor Yellow
Write-Host "Results will be saved to: $BaseDir" -ForegroundColor Yellow

# Step 2: Start Version A (Fractal Habit) if not skipped
if (-not $SkipFractalHabit) {
    Write-Host "`n[1/3] Starting Version A: Fractal Habit..." -ForegroundColor Green
    
    $fractalExe = $setupResult.VersionA.Executable
    $fractalDir = $setupResult.VersionA.WorkingDir
    $fractalLog = $setupResult.VersionA.LogFile
    
    $fractalJob = Start-Job -ScriptBlock {
        param($exe, $dir, $log)
        Set-Location $dir
        & $exe 2>&1 | Tee-Object -FilePath $log
    } -ArgumentList $fractalExe, $fractalDir, $fractalLog
    
    Write-Host "  Process started (Job ID: $($fractalJob.Id))" -ForegroundColor Gray
    Write-Host "  Log: $fractalLog" -ForegroundColor Gray
    Start-Sleep -Seconds 3  # Let it initialize
}

# Step 3: Start Version B (Probe) if not skipped
if (-not $SkipProbe) {
    Write-Host "`n[2/3] Starting Version B: Probe..." -ForegroundColor Green
    
    $probeExe = $setupResult.VersionB.Executable
    $probeDir = $setupResult.VersionB.WorkingDir
    $probeLog = $setupResult.VersionB.LogFile
    
    $probeJob = Start-Job -ScriptBlock {
        param($exe, $dir, $log)
        Set-Location $dir
        & $exe 2>&1 | Tee-Object -FilePath $log
    } -ArgumentList $probeExe, $probeDir, $probeLog
    
    Write-Host "  Process started (Job ID: $($probeJob.Id))" -ForegroundColor Gray
    Write-Host "  Log: $probeLog" -ForegroundColor Gray
    Start-Sleep -Seconds 3  # Let it initialize
}

# Step 4: Start Monitor
Write-Host "`n[3/3] Starting Monitor..." -ForegroundColor Green
$monitorJob = Start-Job -ScriptBlock {
    param($configFile, $interval)
    & "D:\openclaw-local\workspace-main\ab_test_monitor.ps1" -ConfigFile $configFile -SampleIntervalSeconds $interval
} -ArgumentList "$BaseDir\config.json", $MonitorInterval

Write-Host "  Monitor started (Job ID: $($monitorJob.Id))" -ForegroundColor Gray

# Step 5: Display status
Write-Host "`n=== A/B TEST RUNNING ===" -ForegroundColor Cyan
Write-Host "All processes started. Monitoring active.`n" -ForegroundColor Green

# Create status checker
$statusScript = @"
`$jobs = Get-Job | Where-Object { `$_.State -eq 'Running' }
Write-Host "Active Jobs: `$(`$jobs.Count)" -ForegroundColor Cyan
foreach (`$job in `$jobs) {
    Write-Host "  Job `$(`$job.Id): `$(`$job.Name) - `$(`$job.State)" -ForegroundColor Gray
}

`$fractalLog = "$BaseDir\fractal_habit_log.txt"
`$probeLog = "$BaseDir\probe_log.txt"

if (Test-Path `$fractalLog) {
    `$lastLine = Get-Content `$fractalLog -Tail 1
    Write-Host "`nFractal Habit (last line):" -ForegroundColor Yellow
    Write-Host "  `$lastLine" -ForegroundColor Gray
}

if (Test-Path `$probeLog) {
    `$lastLine = Get-Content `$probeLog -Tail 1
    Write-Host "`nProbe (last line):" -ForegroundColor Yellow
    Write-Host "  `$lastLine" -ForegroundColor Gray
}
"@

$statusScript | Out-File "$BaseDir\check_status.ps1"

Write-Host "Commands:" -ForegroundColor Yellow
Write-Host "  Check status:  & '$BaseDir\check_status.ps1'" -ForegroundColor White
Write-Host "  View jobs:     Get-Job" -ForegroundColor White
Write-Host "  Stop test:     Get-Job | Stop-Job" -ForegroundColor White
Write-Host "  View metrics:  Import-Csv '$($setupResult.VersionA.MetricsFile)' | Format-Table" -ForegroundColor White
Write-Host "`nTest directory: $BaseDir" -ForegroundColor Gray

# Return test info
return @{
    TestId = $TestId
    BaseDir = $BaseDir
    FractalJobId = if ($fractalJob) { $fractalJob.Id } else { $null }
    ProbeJobId = if ($probeJob) { $probeJob.Id } else { $null }
    MonitorJobId = $monitorJob.Id
}
