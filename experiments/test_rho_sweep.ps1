# Test RHO_THRESH variations to find optimum

Write-Host "=== RHO_THRESH OPTIMIZATION SWEEP ===" -ForegroundColor Cyan
Write-Host "Testing which threshold triggers guardian formation" -ForegroundColor Gray

$rho_values = @(1.005, 1.006, 1.007, 1.008, 1.009, 1.01, 1.011, 1.012, 1.013, 1.014, 1.015)
$results = @()

foreach ($rho in $rho_values) {
    Write-Host "`nTesting RHO_THRESH = $rho" -ForegroundColor Yellow
    
    # Create modified probe file
    $probe_content = Get-Content "probe_256.cu" -Raw
    
    # Update RHO_THRESH
    $new_content = $probe_content -replace "#define RHO_THRESH\s+[\d\.]+f", "#define RHO_THRESH      ${rho}f"
    
    # Write temporary file
    $temp_file = "probe_rho_$($rho.ToString().Replace('.','_')).cu"
    Set-Content -Path $temp_file -Value $new_content -Encoding ASCII
    
    # Compile
    Write-Host "  Compiling..." -ForegroundColor Gray
    $compile_output = cmd /c '"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64 && nvcc -O3 -arch=sm_61 -o probe_rho_test.exe ' + $temp_file + ' -lnvml 2>&1'
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Compiled" -ForegroundColor Green
        
        # Run for 100 cycles
        Write-Host "  Running 100 cycles..." -ForegroundColor Gray
        
        # Start process
        $process = Start-Process -FilePath ".\probe_rho_test.exe" -ArgumentList "" -NoNewWindow -PassThru -RedirectStandardOutput "output_rho_$($rho.ToString().Replace('.','_')).txt"
        
        # Wait a bit, then kill
        Start-Sleep -Seconds 10
        Stop-Process -Id $process.Id -Force
        
        # Analyze output
        $output = Get-Content "output_rho_$($rho.ToString().Replace('.','_')).txt" -ErrorAction SilentlyContinue
        
        if ($output) {
            # Find max guardians
            $max_guardians = 0
            $power = 0
            $density_range = ""
            
            foreach ($line in $output) {
                if ($line -match "part\s*\|\s*(\d+)") {
                    $guardians = [int]$matches[1]
                    if ($guardians -gt $max_guardians) {
                        $max_guardians = $guardians
                    }
                }
                
                if ($line -match "rho range\s*\|.*\[([\d\.]+),([\d\.]+)\]") {
                    $density_range = "$($matches[1])-$($matches[2])"
                }
                
                if ($line -match "(\d+\.\d+)W") {
                    $power = [double]$matches[1]
                }
            }
            
            $result = [PSCustomObject]@{
                RHO_THRESH = $rho
                MaxGuardians = $max_guardians
                PowerW = $power
                DensityRange = $density_range
                Success = ($max_guardians -gt 0)
            }
            
            $results += $result
            
            Write-Host "  Result: $max_guardians guardians, $power W" -ForegroundColor $(if ($max_guardians -gt 0) { "Green" } else { "Red" })
        }
        
        # Cleanup
        Remove-Item $temp_file -ErrorAction SilentlyContinue
        Remove-Item "probe_rho_test.exe" -ErrorAction SilentlyContinue
        Remove-Item "output_rho_$($rho.ToString().Replace('.','_')).txt" -ErrorAction SilentlyContinue
    } else {
        Write-Host "  ✗ Compilation failed" -ForegroundColor Red
    }
}

# Display results
Write-Host "`n=== SWEEP RESULTS ===" -ForegroundColor Cyan
$results | Sort-Object RHO_THRESH | Format-Table -AutoSize

# Find optimum
$optimum = $results | Where-Object { $_.Success -eq $true } | Sort-Object RHO_THRESH | Select-Object -First 1

if ($optimum) {
    Write-Host "`n✅ OPTIMUM FOUND: RHO_THRESH = $($optimum.RHO_THRESH)" -ForegroundColor Green
    Write-Host "   Guardians formed at this threshold" -ForegroundColor Gray
} else {
    Write-Host "`n❌ NO GUARDIANS FORMED AT ANY THRESHOLD" -ForegroundColor Red
    Write-Host "   Need to try lower thresholds or adjust other parameters" -ForegroundColor Yellow
}

Write-Host "`n=== NEXT STEPS ===" -ForegroundColor Cyan
if ($optimum) {
    Write-Host "1. Use RHO_THRESH = $($optimum.RHO_THRESH) for production" -ForegroundColor Green
    Write-Host "2. Run longer test (1000 cycles)" -ForegroundColor Gray
    Write-Host "3. Test on actual GTX 1050 hardware" -ForegroundColor Gray
} else {
    Write-Host "1. Try lower RHO_THRESH values (1.002, 1.003, 1.004)" -ForegroundColor Yellow
    Write-Host "2. Adjust SINK_RATE or other parameters" -ForegroundColor Yellow
    Write-Host "3. Check if brain state has enough density variation" -ForegroundColor Yellow
}