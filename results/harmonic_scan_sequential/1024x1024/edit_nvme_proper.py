#!/usr/bin/env python3
"""
PROPER NVMe hybridization edit
No shortcuts, no fake simulations
"""

import re

# Read original file
with open('fractal_habit_1024x1024_nvme_proper.cu', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add NVMe checkpoint function after includes
nvme_function = '''
/* ---- NVMe Checkpoint Function ------------------------------------------- */
void save_nvme_checkpoint(int step, float* d_f, float* d_rho, float* d_ux, float* d_uy) {
    char filename[256];
    sprintf(filename, "C:\\\\fractal_nvme_test\\\\checkpoint_%08d.bin", step);
    
    printf("[NVMe] Saving checkpoint at step %d to %s\\n", step, filename);
    
    // Create directory if it doesn't exist
    system("mkdir C:\\\\fractal_nvme_test 2>nul");
    
    FILE* fp = fopen(filename, "wb");
    if (!fp) {
        printf("[NVMe] ERROR: Cannot open file for writing\\n");
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
        printf("[NVMe] ERROR: Memory allocation failed\\n");
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
    
    printf("[NVMe] Checkpoint saved: %.2f MB\\n", 
           (f_size + 3 * field_size) / (1024.0 * 1024.0));
}
'''

# Find where to insert the function (after last include)
includes_end = 0
lines = content.split('\n')
for i, line in enumerate(lines):
    if line.strip().startswith('#include'):
        includes_end = i

# Insert after includes
lines.insert(includes_end + 1, nvme_function)

# Rejoin content
content = '\n'.join(lines)

# 2. Add checkpoint call in main loop
# Find the batch loop
batch_loop_pattern = r'for \(int batch = 0; batch < TOTAL_BATCHES; batch\+\+\) \{'
match = re.search(batch_loop_pattern, content)
if not match:
    print("ERROR: Could not find batch loop")
    exit(1)

loop_start = match.start()
# Find the opening brace after the loop
brace_pos = content.find('{', loop_start)
if brace_pos == -1:
    print("ERROR: Could not find opening brace")
    exit(1)

# Insert checkpoint call after opening brace
checkpoint_call = '''
        int current_step = batch * STEPS_PER_BATCH;
        
        // NVMe checkpoint every 10,000 steps
        if (current_step % 10000 == 0 && current_step > 0) {
            save_nvme_checkpoint(current_step, f0, d_rho, d_ux, d_uy);
        }'''

content = content[:brace_pos + 1] + checkpoint_call + content[brace_pos + 1:]

# 3. Add final checkpoint before cleanup
cleanup_pattern = r'cufftDestroy\(plan\);'
match = re.search(cleanup_pattern, content)
if match:
    final_checkpoint = '''
    // Final NVMe checkpoint
    save_nvme_checkpoint(100000, f0, d_rho, d_ux, d_uy);
    '''
    content = content[:match.start()] + final_checkpoint + content[match.start():]

# Write modified file
with open('fractal_habit_1024x1024_nvme_proper.cu', 'w', encoding='utf-8') as f:
    f.write(content)

print("✓ PROPER NVMe version created")
print("  File: fractal_habit_1024x1024_nvme_proper.cu")
print("\nCompilation command:")
print("  nvcc -arch=sm_89 -O3 -D_USE_MATH_DEFINES -DWIN32 \\")
print("       fractal_habit_1024x1024_nvme_proper.cu \\")
print("       -o fractal_habit_nvme_proper.exe \\")
print("       -lnvml -lcufft")
print("\nReady for PROPER testing.")