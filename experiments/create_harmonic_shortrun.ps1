# Create short-run versions for harmonic scan (50k steps = 1 sample)
Write-Host "Creating Short-Run Harmonic Scan Versions" -ForegroundColor Yellow
Write-Host "=========================================" -ForegroundColor Yellow

$sourceFile = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src\fractal_habit.cu"
$sourceContent = Get-Content $sourceFile -Raw

# Harmonic grid sizes
$harmonicGrids = @(
    @{Name="1024x1024"; NX=1024; NY=1024},
    @{Name="896x896";   NX=896;  NY=896},
    @{Name="768x768";   NX=768;  NY=768},
    @{Name="640x640";   NX=640;  NY=640},
    @{Name="512x512";   NX=512;  NY=512}
)

$outputDir = "D:\openclaw-local\workspace-main\harmonic_scan_short"
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

foreach ($grid in $harmonicGrids) {
    Write-Host "Creating $($grid.Name) short-run..." -ForegroundColor Cyan
    
    # Modify grid definitions
    $modifiedContent = $sourceContent -replace '#define NX\s+1024', "#define NX    $($grid.NX)"
    $modifiedContent = $modifiedContent -replace '#define NY\s+1024', "#define NY    $($grid.NY)"
    
    # Modify for short run: 50k steps = 1 sample
    $modifiedContent = $modifiedContent -replace '#define TOTAL_STEPS\s+10000000', "#define TOTAL_STEPS      50000"
    $modifiedContent = $modifiedContent -replace '10M steps', "50k steps"
    $modifiedContent = $modifiedContent -replace 'Steps:     10000000', "Steps:        50000"
    
    $outputFile = "$outputDir\fractal_habit_$($grid.Name)_short.cu"
    $modifiedContent | Out-File -FilePath $outputFile -Encoding ASCII
    
    Write-Host "  Created: $outputFile (50k steps)" -ForegroundColor Green
    
    # Create build script
    $buildScript = @"
# Build $($grid.Name) short-run for harmonic scan
Write-Host "Building $($grid.Name) short-run..." -ForegroundColor Yellow

`$batchContent = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d "$outputDir"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 "$($grid.Name)\fractal_habit_$($grid.Name)_short.cu" -o "$($grid.Name)\fractal_habit_$($grid.Name)_short.exe" -lnvml -lcufft
echo Exit code: %errorlevel%
'@

`$batchFile = "$outputDir\build_$($grid.Name)_short.bat"
`$batchContent | Out-File -FilePath `$batchFile -Encoding ASCII

`$result = cmd /c "`"`$batchFile`" 2>&1"
Remove-Item `$batchFile -Force

if (`$LASTEXITCODE -eq 0) {
    Write-Host "Build successful: $($grid.Name) short-run" -ForegroundColor Green
} else {
    Write-Host "Build failed for $($grid.Name)" -ForegroundColor Red
    `$result
}
"@
    
    $buildScriptFile = "$outputDir\build_$($grid.Name)_short.ps1"
    $buildScript | Out-File -FilePath $buildScriptFile -Encoding ASCII
}

Write-Host "`nShort-run harmonic scan versions created in: $outputDir" -ForegroundColor Green
Write-Host "`nEach run will execute 50k steps (1 sample)" -ForegroundColor Yellow
Write-Host "We'll monitor spectral slope (sl) at step 50k" -ForegroundColor Yellow
Write-Host "This is the 'harmonic resonance test'" -ForegroundColor Yellow