# Create PROPER NVMe hybrid version
# Manual, careful editing - no shortcuts

Write-Host "Creating PROPER NVMe hybrid version..." -ForegroundColor Cyan
Write-Host ""

# Read the entire file
$lines = Get-Content "fractal_habit_1024x1024.cu"

# Create NVMe version array
$nvmeLines = @()

# Track state
$inMainLoop = $false
$loopDepth = 0
$addedCheckpointFunction = $false
$checkpointFunctionAdded = $false

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    
    # Add NVMe checkpoint function after includes
    if (-not $checkpointFunctionAdded -and $line -match '^#include') {
        $nvmeLines += $line
        
        # Check if this is the last include
        if ($i + 1 -lt $lines.Count -and $lines[$i + 1] -notmatch '^#include') {
            # Add NVMe checkpoint function
            $nvmeLines += ""
            $nvmeLines += "/* ---- NVMe Checkpoint Function ------------------------------------------- */"
            $nvmeLines += "void save_nvme_checkpoint(int step, float* d_f, float* d_rho, float* d_ux, float* d_uy) {"
            $nvmeLines += "    char filename[256];"
            $nvmeLines += "    sprintf(filename, ""C:\\\\fractal_nvme_test\\\\checkpoint_%08d.bin"", step);"
            $nvmeLines += "    "
            $nvmeLines += "    printf(""[NVMe] Saving checkpoint at step %d to %s\n"", step, filename);"
            $nvmeLines += "    "
            $nvmeLines += "    // Create directory if it doesn't exist"
            $nvmeLines += "    system(""mkdir C:\\\\fractal_nvme_test 2>nul"");"
            $nvmeLines += "    "
            $nvmeLines += "    FILE* fp = fopen(filename, ""wb"");"
            $nvmeLines += "    if (!fp) {"
            $nvmeLines += "        printf(""[NVMe] ERROR: Cannot open file for writing\n"");"
            $nvmeLines += "        return;"
            $nvmeLines += "    }"
            $nvmeLines += "    "
            $nvmeLines += "    // Write header: step, NX, NY, magic"
            $nvmeLines += "    int header[4] = {step, 1024, 1024, 0xCAFEBABE};"
            $nvmeLines += "    fwrite(header, sizeof(int), 4, fp);"
            $nvmeLines += "    "
            $nvmeLines += "    // Calculate sizes"
            $nvmeLines += "    size_t f_size = 9 * 1024 * 1024 * sizeof(float);  // Q * NX * NY"
            $nvmeLines += "    size_t field_size = 1024 * 1024 * sizeof(float);  // NX * NY"
            $nvmeLines += "    "
            $nvmeLines += "    // Allocate host memory"
            $nvmeLines += "    float* h_f = (float*)malloc(f_size);"
            $nvmeLines += "    float* h_rho = (float*)malloc(field_size);"
            $nvmeLines += "    float* h_ux = (float*)malloc(field_size);"
            $nvmeLines += "    float* h_uy = (float*)malloc(field_size);"
            $nvmeLines += "    "
            $nvmeLines += "    if (!h_f || !h_rho || !h_ux || !h_uy) {"
            $nvmeLines += "        printf(""[NVMe] ERROR: Memory allocation failed\n"");"
            $nvmeLines += "        fclose(fp);"
            $nvmeLines += "        if (h_f) free(h_f);"
            $nvmeLines += "        if (h_rho) free(h_rho);"
            $nvmeLines += "        if (h_ux) free(h_ux);"
            $nvmeLines += "        if (h_uy) free(h_uy);"
            $nvmeLines += "        return;"
            $nvmeLines += "    }"
            $nvmeLines += "    "
            $nvmeLines += "    // Copy from device to host"
            $nvmeLines += "    cudaMemcpy(h_f, d_f, f_size, cudaMemcpyDeviceToHost);"
            $nvmeLines += "    cudaMemcpy(h_rho, d_rho, field_size, cudaMemcpyDeviceToHost);"
            $nvmeLines += "    cudaMemcpy(h_ux, d_ux, field_size, cudaMemcpyDeviceToHost);"
            $nvmeLines += "    cudaMemcpy(h_uy, d_uy, field_size, cudaMemcpyDeviceToHost);"
            $nvmeLines += "    "
            $nvmeLines += "    // Write data"
            $nvmeLines += "    fwrite(h_f, f_size, 1, fp);"
            $nvmeLines += "    fwrite(h_rho, field_size, 1, fp);"
            $nvmeLines += "    fwrite(h_ux, field_size, 1, fp);"
            $nvmeLines += "    fwrite(h_uy, field_size, 1, fp);"
            $nvmeLines += "    "
            $nvmeLines += "    fclose(fp);"
            $nvmeLines += "    "
            $nvmeLines += "    // Free host memory"
            $nvmeLines += "    free(h_f);"
            $nvmeLines += "    free(h_rho);"
            $nvmeLines += "    free(h_ux);"
            $nvmeLines += "    free(h_uy);"
            $nvmeLines += "    "
            $nvmeLines += "    printf(""[NVMe] Checkpoint saved: %.2f MB\n"", "
            $nvmeLines += "           (f_size + 3 * field_size) / (1024.0 * 1024.0));"
            $nvmeLines += "}"
            $nvmeLines += ""
            $checkpointFunctionAdded = $true
        }
        continue
    }
    
    # Check for main loop start
    if ($line -match 'for \(int batch = 0; batch < TOTAL_BATCHES; batch\+\+\) \{') {
        $inMainLoop = $true
        $nvmeLines += $line
        continue
    }
    
    # Inside main loop - add checkpointing after the opening brace
    if ($inMainLoop -and $line -match '^\s*\{') {
        $loopDepth++
        $nvmeLines += $line
        
        # Add checkpoint call after opening brace
        if ($loopDepth -eq 1) {
            $nvmeLines += "        int current_step = batch * STEPS_PER_BATCH;"
            $nvmeLines += "        "
            $nvmeLines += "        // NVMe checkpoint every 10,000 steps"
            $nvmeLines += "        if (current_step % 10000 == 0 && current_step > 0) {"
            $nvmeLines += "            save_nvme_checkpoint(current_step, f0, d_rho, d_ux, d_uy);"
            $nvmeLines += "        }"
            $addedCheckpointFunction = $true
        }
        continue
    }
    
    # Check for loop end
    if ($inMainLoop -and $line -match '^\s*\}') {
        $loopDepth--
        if ($loopDepth -eq 0) {
            $inMainLoop = $false
        }
    }
    
    # Add final checkpoint before cleanup
    if ($line -match 'cufftDestroy\(plan\);') {
        $nvmeLines += "    "
        $nvmeLines += "    // Final NVMe checkpoint"
        $nvmeLines += "    save_nvme_checkpoint(100000, f0, d_rho, d_ux, d_uy);"
        $nvmeLines += "    "
    }
    
    $nvmeLines += $line
}

# Save NVMe version
$nvmePath = "fractal_habit_1024x1024_nvme_proper.cu"
$nvmeLines | Out-File -FilePath $nvmePath -Encoding UTF8

Write-Host "✓ NVMe version created: $nvmePath" -ForegroundColor Green
Write-Host "  Lines: $($nvmeLines.Count)" -ForegroundColor Gray
Write-Host "  Size: $((Get-Item $nvmePath).Length) bytes" -ForegroundColor Gray

Write-Host "`nCompilation command:" -ForegroundColor Cyan
Write-Host "  nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 ^" -ForegroundColor Gray
Write-Host "       $nvmePath ^" -ForegroundColor Gray
Write-Host "       -o fractal_habit_nvme_proper.exe ^" -ForegroundColor Gray
Write-Host "       -lnvml -lcufft" -ForegroundColor Gray

Write-Host "`nTest directory:" -ForegroundColor Cyan
Write-Host "  mkdir C:\fractal_nvme_test" -ForegroundColor Gray

Write-Host "`nReady for PROPER NVMe hybridization testing." -ForegroundColor Green