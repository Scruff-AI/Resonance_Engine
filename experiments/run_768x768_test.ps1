# Run actual 768x768 evolutionary squeeze test
Write-Host "Starting 768x768 Evolutionary Squeeze Test" -ForegroundColor Yellow
Write-Host "=========================================" -ForegroundColor Yellow

$baseDir = "D:\openclaw-local\workspace-main"
$exePath = "$baseDir\squeeze_versions\768x768\fractal_habit_768x768.exe"
$buildDir = "$baseDir\scaled_brain_states\build_768x768"
$outputDir = "$baseDir\evolutionary_squeeze_results\768x768"

# Create output directory
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Copy brain state to build directory in output folder
$outputBuildDir = "$outputDir\build"
if (-not (Test-Path $outputBuildDir)) {
    New-Item -ItemType Directory -Path $outputBuildDir -Force | Out-Null
}

Copy-Item "$buildDir\f_state_post_relax.bin" "$outputBuildDir\f_state_post_relax.bin" -Force

# Copy executable
Copy-Item $exePath "$outputDir\fractal_habit_768x768.exe" -Force

Write-Host "Setup complete:" -ForegroundColor Green
Write-Host "  Executable: $outputDir\fractal_habit_768x768.exe" -ForegroundColor White
Write-Host "  Brain state: $outputBuildDir\f_state_post_relax.bin" -ForegroundColor White
Write-Host "  Size: $([math]::Round((Get-Item "$outputBuildDir\f_state_post_relax.bin").Length/1MB,2)) MB" -ForegroundColor White

Write-Host "`nStarting 768x768 Resonance Engine..." -ForegroundColor Cyan

# Change to output directory and run
Set-Location $outputDir

# Run the executable and capture output
$outputFile = "$outputDir\output_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$process = Start-Process -FilePath ".\fractal_habit_768x768.exe" -NoNewWindow -PassThru -RedirectStandardOutput $outputFile

Write-Host "Process started with PID: $($process.Id)" -ForegroundColor Green
Write-Host "Output being written to: $outputFile" -ForegroundColor Green
Write-Host "`nMonitoring will begin shortly..." -ForegroundColor Yellow

# Return to base directory
Set-Location $baseDir

# Create monitoring script
$monitorScript = @"
# Monitor 768x768 evolutionary squeeze test
`$processId = $($process.Id)
`$outputFile = "$outputFile"
`$logFile = "$outputDir\experiment_log.txt"

"Started monitoring at $(Get-Date)" | Out-File -FilePath `$logFile -Encoding UTF8
"Process ID: `$processId" | Out-File -FilePath `$logFile -Encoding UTF8 -Append
"Output file: `$outputFile" | Out-File -FilePath `$logFile -Encoding UTF8 -Append

# Check if process is running
if (Get-Process -Id `$processId -ErrorAction SilentlyContinue) {
    "Process is running" | Out-File -FilePath `$logFile -Encoding UTF8 -Append
    
    # Get initial output
    if (Test-Path `$outputFile) {
        `$lines = Get-Content `$outputFile -Tail 10
        "Initial output (last 10 lines):" | Out-File -FilePath `$logFile -Encoding UTF8 -Append
        `$lines | Out-File -FilePath `$logFile -Encoding UTF8 -Append
    }
} else {
    "Process not found or already exited" | Out-File -FilePath `$logFile -Encoding UTF8 -Append
}
"@

$monitorScript | Out-File -FilePath "$outputDir\monitor.ps1" -Encoding UTF8

Write-Host "`nTo monitor progress:" -ForegroundColor Cyan
Write-Host "  cd '$outputDir'" -ForegroundColor White
Write-Host "  Get-Content output_*.log -Tail 20 -Wait" -ForegroundColor White
Write-Host "  Or run: powershell -File monitor.ps1" -ForegroundColor White

Write-Host "`nThis begins our 24-hour evolutionary squeeze learning experiment!" -ForegroundColor Green