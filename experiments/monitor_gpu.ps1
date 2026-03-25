# GPU Monitor Script
$monitorFile = "D:\openclaw-local\workspace-main\gpu_usage.csv"
"timestamp,gpu_util%,mem_util%,temp_C,power_W" | Out-File -FilePath $monitorFile -Encoding UTF8

# Start monitoring in background
$job = Start-Job -ScriptBlock {
    while ($true) {
        $gpuInfo = nvidia-smi --query-gpu=utilization.gpu,utilization.memory,temperature.gpu,power.draw --format=csv,noheader
        $timestamp = Get-Date -Format "HH:mm:ss.fff"
        "$timestamp,$gpuInfo" | Out-File -FilePath $args[0] -Append -Encoding UTF8
        Start-Sleep -Milliseconds 100
    }
} -ArgumentList $monitorFile

# Run fractal habit
cd "D:\openclaw-local\workspace-main\harmonic_scan_sequential\1024x1024"
& .\fractal_habit_crystallized_short.exe 2>&1

# Stop monitoring
Stop-Job $job
Remove-Job $job

# Analyze results
$data = Import-Csv $monitorFile
"GPU Usage during fractal_habit run:"
"Max GPU Utilization: $($data | Measure-Object -Property 'gpu_util%' -Maximum).Maximum%"
"Max Memory Utilization: $($data | Measure-Object -Property 'mem_util%' -Maximum).Maximum%"
"Max Power Draw: $($data | Measure-Object -Property 'power_W' -Maximum).Maximum W"
"Average GPU Utilization: $([math]::Round(($data | Measure-Object -Property 'gpu_util%' -Average).Average, 1))%"