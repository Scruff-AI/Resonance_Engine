# A/B Test: Fractal Habit vs Probe
# Side-by-side execution with comprehensive metrics collection
# Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

$TestId = "AB_TEST_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$BaseDir = "D:\openclaw-local\workspace-main\ab_test_$TestId"
New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null

# Test Configuration
$Config = @{
    TestId = $TestId
    StartTime = Get-Date
    VersionA = @{
        Name = "Fractal Habit (Spectral Analysis)"
        Executable = "D:\openclaw-local\workspace-main\harmonic_scan_sequential\1024x1024\fractal_habit_1024x1024.exe"
        WorkingDir = "$BaseDir\fractal_habit"
        LogFile = "$BaseDir\fractal_habit_log.txt"
        MetricsFile = "$BaseDir\fractal_habit_metrics.csv"
        ExpectedDuration = "4-6 hours"
        GridSize = "1024x1024"
    }
    VersionB = @{
        Name = "Probe (Guardian Forensics)"
        Executable = "D:\openclaw-local\workspace-main\probe_1024.exe"
        WorkingDir = "$BaseDir\probe"
        LogFile = "$BaseDir\probe_log.txt"
        MetricsFile = "$BaseDir\probe_metrics.csv"
        ExpectedDuration = "30-45 minutes"
        GridSize = "1024x1024"
    }
}

# Create working directories
New-Item -ItemType Directory -Path $Config.VersionA.WorkingDir -Force | Out-Null
New-Item -ItemType Directory -Path $Config.VersionB.WorkingDir -Force | Out-Null

# Copy brain state if available
$BrainState = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src\build\f_state_post_relax.bin"
if (Test-Path $BrainState) {
    Copy-Item $BrainState $Config.VersionA.WorkingDir
    Copy-Item $BrainState $Config.VersionB.WorkingDir
    Write-Host "Brain state copied to both test directories" -ForegroundColor Green
}

# Initialize metrics files
"timestamp,test_id,version,elapsed_seconds,gpu_power_w,gpu_temp_c,gpu_util_percent,process_cpu_percent,process_memory_mb" | Out-File $Config.VersionA.MetricsFile
"timestamp,test_id,version,elapsed_seconds,gpu_power_w,gpu_temp_c,gpu_util_percent,process_cpu_percent,process_memory_mb,cycles,guardians,total_mass" | Out-File $Config.VersionB.MetricsFile

Write-Host "`n=== A/B TEST INITIATED ===" -ForegroundColor Cyan
Write-Host "Test ID: $TestId" -ForegroundColor Yellow
Write-Host "Base Directory: $BaseDir" -ForegroundColor Yellow
Write-Host "`nVersion A: $($Config.VersionA.Name)" -ForegroundColor Green
Write-Host "  Executable: $($Config.VersionA.Executable)"
Write-Host "  Expected: $($Config.VersionA.ExpectedDuration)"
Write-Host "`nVersion B: $($Config.VersionB.Name)" -ForegroundColor Green
Write-Host "  Executable: $($Config.VersionB.Executable)"
Write-Host "  Expected: $($Config.VersionB.ExpectedDuration)"
Write-Host "`n===========================" -ForegroundColor Cyan

# Export config for monitoring scripts
$Config | ConvertTo-Json -Depth 10 | Out-File "$BaseDir\config.json"
Write-Host "`nConfiguration saved to: $BaseDir\config.json" -ForegroundColor Gray

return $Config
