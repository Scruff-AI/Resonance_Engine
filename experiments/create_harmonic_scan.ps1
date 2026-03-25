# Create harmonic scan grid sizes
Write-Host "Creating Harmonic Scan Grid Sizes" -ForegroundColor Yellow
Write-Host "=================================" -ForegroundColor Yellow

$sourceFile = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src\fractal_habit.cu"
$sourceContent = Get-Content $sourceFile -Raw

# Harmonic grid sizes (powers of 2 and intermediate steps)
$harmonicGrids = @(
    @{Name="1024x1024"; NX=1024; NY=1024},  # Baseline
    @{Name="896x896";   NX=896;  NY=896},   # 12.5% reduction
    @{Name="768x768";   NX=768;  NY=768},   # 25% reduction (problematic)
    @{Name="640x640";   NX=640;  NY=640},   # 37.5% reduction
    @{Name="512x512";   NX=512;  NY=512}    # 50% reduction
)

$outputDir = "D:\openclaw-local\workspace-main\harmonic_scan"
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

foreach ($grid in $harmonicGrids) {
    Write-Host "Creating $($grid.Name)..." -ForegroundColor Cyan
    
    # Modify grid definitions
    $modifiedContent = $sourceContent -replace '#define NX\s+1024', "#define NX    $($grid.NX)"
    $modifiedContent = $modifiedContent -replace '#define NY\s+1024', "#define NY    $($grid.NY)"
    
    $outputFile = "$outputDir\fractal_habit_$($grid.Name).cu"
    $modifiedContent | Out-File -FilePath $outputFile -Encoding ASCII
    
    Write-Host "  Created: $outputFile" -ForegroundColor Green
    
    # Create build script
    $buildScript = @"
# Build $($grid.Name) for harmonic scan
Write-Host "Building $($grid.Name)..." -ForegroundColor Yellow

`$batchContent = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d "$outputDir"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 "$($grid.Name)\fractal_habit_$($grid.Name).cu" -o "$($grid.Name)\fractal_habit_$($grid.Name).exe" -lnvml -lcufft
echo Exit code: %errorlevel%
'@

`$batchFile = "$outputDir\build_$($grid.Name).bat"
`$batchContent | Out-File -FilePath `$batchFile -Encoding ASCII

`$result = cmd /c "`"`$batchFile`" 2>&1"
Remove-Item `$batchFile -Force

if (`$LASTEXITCODE -eq 0) {
    Write-Host "Build successful: $($grid.Name)" -ForegroundColor Green
} else {
    Write-Host "Build failed for $($grid.Name)" -ForegroundColor Red
    `$result
}
"@
    
    $buildScriptFile = "$outputDir\build_$($grid.Name).ps1"
    $buildScript | Out-File -FilePath $buildScriptFile -Encoding ASCII
}

Write-Host "`nHarmonic scan grid sizes created in: $outputDir" -ForegroundColor Green
Write-Host "`nNext: Build and run 50k-step tests for each grid size" -ForegroundColor Yellow
Write-Host "Monitor: Spectral slope (sl) evolution" -ForegroundColor Yellow
Write-Host "Target: -2.0 to -2.5 (coherent) vs -0.5 (noise)" -ForegroundColor Yellow