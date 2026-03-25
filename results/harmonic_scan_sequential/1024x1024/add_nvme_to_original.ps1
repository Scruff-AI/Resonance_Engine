# Properly add NVMe checkpointing to working 1024x1024 code
# No shortcuts, no fake simulations

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PROPER NVMe HYBRIDIZATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Adding three-tiered memory to working 1024x1024" -ForegroundColor Yellow
Write-Host ""

# Step 1: Backup original code
Write-Host "Step 1: Backing up original code..." -ForegroundColor Yellow
$original = "fractal_habit_1024x1024.cu"
$backup = "fractal_habit_1024x1024_original_backup.cu"
Copy-Item $original $backup -Force
Write-Host "  Backup created: $backup" -ForegroundColor Green

# Step 2: Read original code
Write-Host "`nStep 2: Reading original code..." -ForegroundColor Yellow
$content = Get-Content $original -Raw

# Step 3: Add NVMe checkpoint function after includes
Write-Host "`nStep 3: Adding NVMe checkpoint function..." -ForegroundColor Yellow

$nvmeFunction = @'

/* ---- NVMe Checkpoint Function ------------------------------------------- */
void save_nvme_checkpoint(int step, float* d_f, float* d_rho, float* d_ux, float* d_uy) {
    char filename[256];
    sprintf(filename, "C:\\\\fractal_nvme_test\\\\checkpoint_%08d.bin", step);
    
    printf("[NVMe] Saving checkpoint at step %d to %s\n", step, filename);
    
    // Create directory if it doesn'\''t exist
    system("mkdir C:\\\\fractal_nvme_test 2>nul");
    
    FILE* fp = fopen(filename, "wb");
    if (!fp) {
        printf("[NVMe] ERROR: Cannot open file for writing\n");
        return;
    }
    
    // Write header: step, NX, NY, magic
    int header[4] = {step, 1024, 1024, 0xCAFEBABE};
    fwrite(header, sizeof(int), 4, fp);
    
    // Calculate sizes
    size_t f_size = 9 * 1024 * 1024 * sizeof(float);  // Q * NX * NY
    size_t field_size = 1024 * 1024 * sizeof(float);  // NX * NY
    
    // Allocate host memory
    float* h_f = (float*)malloc(f_size);
    float* h_rho = (float*)malloc(field_size);
    float* h_ux = (float*)malloc(field_size);
    float* h_uy = (float*)malloc(field_size);
    
    if (!h_f || !h_rho || !h_ux || !h_uy) {
        printf("[NVMe] ERROR: Memory allocation failed\n");
        fclose(fp);
        if (h_f) free(h_f);
        if (h_rho) free(h_rho);
        if (h_ux) free(h_ux);
        if (h_uy) free(h_uy);
        return;
    }
    
    // Copy from device to host
    cudaMemcpy(h_f, d_f, f_size, cudaMemcpyDeviceToHost);
    cudaMemcpy(h_rho, d_rho, field_size, cudaMemcpyDeviceToHost);
    cudaMemcpy(h_ux, d_ux, field_size, cudaMemcpyDeviceToHost);
    cudaMemcpy(h_uy, d_uy, field_size, cudaMemcpyDeviceToHost);
    
    // Write data
    fwrite(h_f, f_size, 1, fp);
    fwrite(h_rho, field_size, 1, fp);
    fwrite(h_ux, field_size, 1, fp);
    fwrite(h_uy, field_size, 1, fp);
    
    fclose(fp);
    
    // Free host memory
    free(h_f);
    free(h_rho);
    free(h_ux);
    free(h_uy);
    
    printf("[NVMe] Checkpoint saved: %.2f MB\n", 
           (f_size + 3 * field_size) / (1024.0 * 1024.0));
}
'@

# Find where to insert the function (after includes and before main)
$insertPoint = $content.IndexOf('/* ---- Grid ---------------------------------------------------------------- */')
if ($insertPoint -eq -1) {
    Write-Host "ERROR: Could not find insertion point" -ForegroundColor Red
    exit 1
}

$newContent = $content.Insert($insertPoint, $nvmeFunction)
Write-Host "  NVMe function added" -ForegroundColor Green

# Step 4: Add checkpoint calls in main loop
Write-Host "`nStep 4: Adding checkpoint calls in main loop..." -ForegroundColor Yellow

# Find the batch loop
$batchLoopPattern = 'for \(int batch = 0; batch < TOTAL_BATCHES; batch\+\+\) {'
$batchLoopIndex = $newContent.IndexOf($batchLoopPattern)
if ($batchLoopIndex -eq -1) {
    Write-Host "ERROR: Could not find batch loop" -ForegroundColor Red
    exit 1
}

# Find the opening brace of the loop
$loopStart = $newContent.IndexOf('{', $batchLoopIndex)
if ($loopStart -eq -1) {
    Write-Host "ERROR: Could not find loop start" -ForegroundColor Red
    exit 1
}

# Insert checkpoint call after loop start
$checkpointCall = @'
        int current_step = batch * STEPS_PER_BATCH;
        
        // NVMe checkpoint every 10,000 steps
        if (current_step % 10000 == 0 && current_step > 0) {
            save_nvme_checkpoint(current_step, f0, d_rho, d_ux, d_uy);
        }
'@

$newContent = $newContent.Insert($loopStart + 1, $checkpointCall)
Write-Host "  Checkpoint calls added to loop" -ForegroundColor Green

# Step 5: Add final checkpoint at the end
Write-Host "`nStep 5: Adding final checkpoint..." -ForegroundColor Yellow

$finalCheckpointPattern = 'printf\("  Output:.*?======================================================================="\);'
if ($newContent -match $finalCheckpointPattern) {
    $match = $matches[0]
    $insertPoint = $newContent.IndexOf($match) + $match.Length
    
    $finalCheckpoint = @'

    // Final NVMe checkpoint
    save_nvme_checkpoint(100000, f0, d_rho, d_ux, d_uy);
'@
    
    $newContent = $newContent.Insert($insertPoint, $finalCheckpoint)
    Write-Host "  Final checkpoint added" -ForegroundColor Green
} else {
    Write-Host "WARNING: Could not find final output section" -ForegroundColor Yellow
}

# Step 6: Save modified code
Write-Host "`nStep 6: Saving modified code..." -ForegroundColor Yellow
$nvmeVersion = "fractal_habit_1024x1024_nvme_proper.cu"
Set-Content -Path $nvmeVersion -Value $newContent -Encoding UTF8
Write-Host "  Saved: $nvmeVersion" -ForegroundColor Green
Write-Host "  Size: $((Get-Item $nvmeVersion).Length) bytes" -ForegroundColor Gray

# Step 7: Compilation command
Write-Host "`nStep 7: Compilation command:" -ForegroundColor Cyan
Write-Host "  nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 ^" -ForegroundColor Gray
Write-Host "       $nvmeVersion ^" -ForegroundColor Gray
Write-Host "       -o fractal_habit_nvme_proper.exe ^" -ForegroundColor Gray
Write-Host "       -lnvml -lcufft" -ForegroundColor Gray

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "READY FOR PROPER NVMe HYBRIDIZATION" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Next: Compile and test the proper NVMe version" -ForegroundColor Yellow
Write-Host "No shortcuts, no fake simulations" -ForegroundColor Yellow