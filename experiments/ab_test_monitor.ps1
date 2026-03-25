# A/B Test Monitor - Collects metrics from both running systems
param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigFile,
    
    [int]$SampleIntervalSeconds = 5,
    [int]$MaxRuntimeMinutes = 360  # 6 hours max
)

$Config = Get-Content $ConfigFile | ConvertFrom-Json
$TestId = $Config.TestId
$BaseDir = "D:\openclaw-local\workspace-main\ab_test_$TestId"

# Load NVML for GPU metrics
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class NVML {
    [DllImport("nvml.dll")] public static extern int nvmlInit();
    [DllImport("nvml.dll")] public static extern int nvmlShutdown();
    [DllImport("nvml.dll")] public static extern int nvmlDeviceGetHandleByIndex(uint idx, out IntPtr dev);
    [DllImport("nvml.dll")] public static extern int nvmlDeviceGetPowerUsage(IntPtr dev, out uint power);
    [DllImport("nvml.dll")] public static extern int nvmlDeviceGetTemperature(IntPtr dev, uint sensor, out uint temp);
    [DllImport("nvml.dll")] public static extern int nvmlDeviceGetUtilizationRates(IntPtr dev, out IntPtr util);
}
"@

# Initialize NVML
try {
    [NVML]::nvmlInit() | Out-Null
    $GpuHandle = [IntPtr]::Zero
    [NVML]::nvmlDeviceGetHandleByIndex(0, [ref]$GpuHandle) | Out-Null
    Write-Host "NVML initialized successfully" -ForegroundColor Green
} catch {
    Write-Warning "NVML initialization failed - GPU metrics will be unavailable"
    $GpuHandle = [IntPtr]::Zero
}

function Get-GpuMetrics {
    param([IntPtr]$Handle)
    
    if ($Handle -eq [IntPtr]::Zero) {
        return @{ PowerW = 0; TempC = 0; UtilPercent = 0 }
    }
    
    $power = 0u
    $temp = 0u
    
    [NVML]::nvmlDeviceGetPowerUsage($Handle, [ref]$power) | Out-Null
    [NVML]::nvmlDeviceGetTemperature($Handle, 0, [ref]$temp) | Out-Null
    
    return @{
        PowerW = [math]::Round($power / 1000.0, 2)
        TempC = $temp
        UtilPercent = 0  # Would need additional call for utilization
    }
}

function Get-ProcessMetrics {
    param([string]$ProcessName)
    
    $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) {
        return @{
            CPU = [math]::Round($proc.CPU, 2)
            MemoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
            Id = $proc.Id
        }
    }
    return @{ CPU = 0; MemoryMB = 0; Id = 0 }
}

function Parse-ProbeOutput {
    param([string]$LogFile)
    
    if (-not (Test-Path $LogFile)) { return @{ Cycles = 0; Guardians = 0; Mass = 0 } }
    
    $lastLine = Get-Content $LogFile -Tail 1
    
    # Try to extract cycle count
    $cycleMatch = $lastLine | Select-String -Pattern "cycle\s+(\d+)" -AllMatches
    $cycles = if ($cycleMatch) { [int]$cycleMatch.Matches[0].Groups[1].Value } else { 0 }
    
    # Try to extract guardian count
    $guardianMatch = $lastLine | Select-String -Pattern "part\s*=\s*(\d+)" -AllMatches
    $guardians = if ($guardianMatch) { [int]$guardianMatch.Matches[0].Groups[1].Value } else { 0 }
    
    # Try to extract total mass
    $massMatch = $lastLine | Select-String -Pattern "M_total\s*=\s*([\d.]+)" -AllMatches
    $mass = if ($massMatch) { [float]$massMatch.Matches[0].Groups[1].Value } else { 0 }
    
    return @{ Cycles = $cycles; Guardians = $guardians; Mass = $mass }
}

Write-Host "`n=== MONITORING STARTED ===" -ForegroundColor Cyan
Write-Host "Test ID: $TestId" -ForegroundColor Yellow
Write-Host "Sample Interval: ${SampleIntervalSeconds}s" -ForegroundColor Yellow
Write-Host "Max Runtime: ${MaxRuntimeMinutes} minutes" -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop monitoring`n" -ForegroundColor Gray

$StartTime = Get-Date
$SampleCount = 0

while ($true) {
    $elapsed = (Get-Date) - $StartTime
    $elapsedMinutes = $elapsed.TotalMinutes
    
    if ($elapsedMinutes -gt $MaxRuntimeMinutes) {
        Write-Host "`nMax runtime reached - stopping monitor" -ForegroundColor Yellow
        break
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $gpu = Get-GpuMetrics -Handle $GpuHandle
    
    # Monitor Version A (Fractal Habit)
    $procA = Get-ProcessMetrics -ProcessName "fractal_habit_1024x1024"
    if ($procA.Id -gt 0) {
        "$timestamp,$TestId,FractalHabit,$($elapsed.TotalSeconds),$($gpu.PowerW),$($gpu.TempC),$($gpu.UtilPercent),$($procA.CPU),$($procA.MemoryMB)" | 
            Out-File $Config.VersionA.MetricsFile -Append
    }
    
    # Monitor Version B (Probe)
    $procB = Get-ProcessMetrics -ProcessName "probe_1024"
    $probeData = Parse-ProbeOutput -LogFile $Config.VersionB.LogFile
    if ($procB.Id -gt 0) {
        "$timestamp,$TestId,Probe,$($elapsed.TotalSeconds),$($gpu.PowerW),$($gpu.TempC),$($gpu.UtilPercent),$($procB.CPU),$($procB.MemoryMB),$($probeData.Cycles),$($probeData.Guardians),$($probeData.Mass)" | 
            Out-File $Config.VersionB.MetricsFile -Append
    }
    
    $SampleCount++
    
    # Status display every 60 seconds (12 samples at 5s interval)
    if ($SampleCount % 12 -eq 0) {
        Write-Host "[$timestamp] Elapsed: $($elapsed.ToString('hh\:mm\:ss')) | " -NoNewline
        Write-Host "GPU: $($gpu.PowerW)W $($gpu.TempC)°C | " -NoNewline
        if ($procA.Id -gt 0) { Write-Host "A:RUNNING " -ForegroundColor Green -NoNewline }
        else { Write-Host "A:STOPPED " -ForegroundColor Red -NoNewline }
        if ($procB.Id -gt 0) { Write-Host "B:RUNNING(c$($probeData.Cycles),g$($probeData.Guardians))" -ForegroundColor Green }
        else { Write-Host "B:STOPPED" -ForegroundColor Red }
    }
    
    Start-Sleep -Seconds $SampleIntervalSeconds
}

# Cleanup
if ($GpuHandle -ne [IntPtr]::Zero) {
    [NVML]::nvmlShutdown() | Out-Null
}

Write-Host "`n=== MONITORING COMPLETE ===" -ForegroundColor Cyan
Write-Host "Metrics saved to:" -ForegroundColor Yellow
Write-Host "  $($Config.VersionA.MetricsFile)"
Write-Host "  $($Config.VersionB.MetricsFile)"
