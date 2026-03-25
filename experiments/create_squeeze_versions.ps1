# Create evolutionary squeeze versions with different grid sizes

$sourceFile = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src\fractal_habit.cu"
$sourceContent = Get-Content $sourceFile -Raw

# Grid sizes for evolutionary squeeze
$gridSizes = @(
    @{Name="768x768"; NX=768; NY=768},
    @{Name="512x512"; NX=512; NY=512},
    @{Name="384x384"; NX=384; NY=384},
    @{Name="256x256"; NX=256; NY=256},
    @{Name="192x192"; NX=192; NY=192}
)

$outputDir = "D:\openclaw-local\workspace-main\squeeze_versions"
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

foreach ($grid in $gridSizes) {
    Write-Host "Creating $($grid.Name) version..." -ForegroundColor Yellow
    
    # Modify grid definitions
    $modifiedContent = $sourceContent -replace '#define NX\s+1024', "#define NX    $($grid.NX)"
    $modifiedContent = $modifiedContent -replace '#define NY\s+1024', "#define NY    $($grid.NY)"
    
    # Also update any hardcoded 1024 references in comments
    $modifiedContent = $modifiedContent -replace '1024×1024', "$($grid.NX)×$($grid.NY)"
    
    $outputFile = "$outputDir\fractal_habit_$($grid.Name).cu"
    $modifiedContent | Out-File -FilePath $outputFile -Encoding ASCII
    
    Write-Host "  Created: $outputFile" -ForegroundColor Green
    
    # Create build script for this version
    $buildScript = @"
# Build $($grid.Name) version
Write-Host "Building $($grid.Name) fractal_habit..." -ForegroundColor Yellow

# Create batch file
`$batchContent = @'
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d "D:\openclaw-local\workspace-main\squeeze_versions"
nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 "$($grid.Name)\fractal_habit_$($grid.Name).cu" -o "$($grid.Name)\fractal_habit_$($grid.Name).exe" -lnvml -lcufft
echo Exit code: %errorlevel%
'@

`$batchFile = "D:\openclaw-local\workspace-main\build_$($grid.Name).bat"
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
    
    Write-Host "  Build script: $buildScriptFile" -ForegroundColor Cyan
}

Write-Host "`nAll squeeze versions created in: $outputDir" -ForegroundColor Green
Write-Host "Next: Run each build script to compile the versions" -ForegroundColor Yellow