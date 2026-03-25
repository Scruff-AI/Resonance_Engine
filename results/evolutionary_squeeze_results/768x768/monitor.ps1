# Monitor 768x768 evolutionary squeeze test
$processId = 
$outputFile = "D:\openclaw-local\workspace-main\evolutionary_squeeze_results\768x768\output_20260311_105643.log"
$logFile = "D:\openclaw-local\workspace-main\evolutionary_squeeze_results\768x768\experiment_log.txt"

"Started monitoring at 03/11/2026 10:56:43" | Out-File -FilePath $logFile -Encoding UTF8
"Process ID: $processId" | Out-File -FilePath $logFile -Encoding UTF8 -Append
"Output file: $outputFile" | Out-File -FilePath $logFile -Encoding UTF8 -Append

# Check if process is running
if (Get-Process -Id $processId -ErrorAction SilentlyContinue) {
    "Process is running" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    
    # Get initial output
    if (Test-Path $outputFile) {
        $lines = Get-Content $outputFile -Tail 10
        "Initial output (last 10 lines):" | Out-File -FilePath $logFile -Encoding UTF8 -Append
        $lines | Out-File -FilePath $logFile -Encoding UTF8 -Append
    }
} else {
    "Process not found or already exited" | Out-File -FilePath $logFile -Encoding UTF8 -Append
}
