# Create properly scaled versions with guardian parameter adjustments
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "CREATING PROPERLY SCALED VERSIONS" -ForegroundColor Cyan
Write-Host "Grid + Guardians + Thresholds scaled together" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$sourceDir = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src"
$outputDir = "D:\openclaw-local\workspace-main\properly_scaled"
$scaledStatesDir = "D:\openclaw-local\workspace-main\harmonic_brain_states"

# Grid sizes and scaling factors
$scalingData = @(
    @{Name="1024x1024"; NX=1024; NY=1024; Scale=1.000; GuardianScale=1.000; ThresholdScale=1.000},
    @{Name="896x896";   NX=896;  NY=896;  Scale=0.875; GuardianScale=0.766; ThresholdScale=1.143},  # 0.875² = 0.766
    @{Name="768x768";   NX=768;  NY=768;  Scale=0.750; GuardianScale=0.563; ThresholdScale=1.333},  # 0.750² = 0.563
    @{Name="640x640";   NX=640;  NY=640;  Scale=0.625; GuardianScale=0.391; ThresholdScale=1.600},  # 0.625² = 0.391
    @{Name="512x512";   NX=512;  NY=512;  Scale=0.500; GuardianScale=0.250; ThresholdScale=2.000}   # 0.500² = 0.250
)

# Create output directory
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

foreach ($data in $scalingData) {
    Write-Host "`n=== Creating $($data.Name) ===" -ForegroundColor Yellow
    Write-Host "  Scale factor: $($data.Scale)" -ForegroundColor Gray
    Write-Host "  Guardian scale: $($data.GuardianScale) (expected ~$([math]::Round(194 * $data.GuardianScale)) guardians)" -ForegroundColor Gray
    Write-Host "  Threshold scale: $($data.ThresholdScale)" -ForegroundColor Gray
    
    $gridDir = "$outputDir\$($data.Name)"
    if (-not (Test-Path $gridDir)) {
        New-Item -ItemType Directory -Path $gridDir -Force | Out-Null
    }
    
    # We need to modify multiple source files:
    # 1. fractal_habit.cu - grid size
    # 2. precipitation.cu - guardian parameters
    # 3. probe.cu - guardian monitoring
    
    # Start with fractal_habit.cu
    $sourceFile = "$sourceDir\fractal_habit.cu"
    $sourceContent = Get-Content $sourceFile -Raw
    
    # Modify grid size
    $modifiedContent = $sourceContent
    $modifiedContent = $modifiedContent -replace '#define NX\s+1024', "#define NX    $($data.NX)"
    $modifiedContent = $modifiedContent -replace '#define NY\s+1024', "#define NY    $($data.NY)"
    
    # Modify for short run
    $modifiedContent = $modifiedContent -replace '#define TOTAL_STEPS\s+10000000', '#define TOTAL_STEPS      200000'
    $modifiedContent = $modifiedContent -replace '10M steps', '200k steps'
    $modifiedContent = $modifiedContent -replace 'Steps:     10000000', 'Steps:       200000'
    
    $outputFile = "$gridDir\fractal_habit_$($data.Name).cu"
    $modifiedContent | Out-File -FilePath $outputFile -Encoding ASCII
    
    Write-Host "  Created: fractal_habit_$($data.Name).cu" -ForegroundColor Green
    
    # Now we need to handle guardian parameter scaling
    # This requires modifying precipitation.cu or creating a wrapper
    
    Write-Host "  ⚠️  Guardian parameter scaling needed" -ForegroundColor Yellow
    Write-Host "  Current approach uses hardcoded RHO_THRESH = 1.01" -ForegroundColor Gray
    Write-Host "  Should be: ~$([math]::Round(1.01 / $data.ThresholdScale, 4)) for proper density" -ForegroundColor Gray
}

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "SCALING ANALYSIS COMPLETE" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan

Write-Host "`nKey Findings:" -ForegroundColor Yellow
Write-Host "1. Current tests use WRONG guardian density" -ForegroundColor White
Write-Host "2. 768×768 has 78% higher guardian density than 1024×1024" -ForegroundColor White
Write-Host "3. Guardian birth threshold doesn't scale" -ForegroundColor White
Write-Host "4. We're testing 'cramped brains', not scaled brains" -ForegroundColor White

Write-Host "`nRequired Fixes:" -ForegroundColor Yellow
Write-Host "1. Modify RHO_THRESH in precipitation.cu for each grid size" -ForegroundColor White
Write-Host "2. Or create parameterized version that scales automatically" -ForegroundColor White
Write-Host "3. Re-run experiments with proper scaling" -ForegroundColor White

Write-Host "`nNext step: Examine precipitation.cu to implement scaling" -ForegroundColor Cyan