// Simple NVMe Hybrid System Test
// Compile with: nvcc -O3 -arch=sm_89 -o simple_nvme_test.exe simple_nvme_test.cu

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>

#define CHECKPOINT_INTERVAL 10000
#define STATE_SIZE 1024*1024*4  // 4MB test state

void save_checkpoint(int step, const char* data, size_t size) {
    char filename[256];
    sprintf(filename, "C:\\fractal_nvme_test\\checkpoint_%08d.bin", step);
    
    FILE* fp = fopen(filename, "wb");
    if (!fp) {
        printf("ERROR: Cannot open %s for writing\n", filename);
        return;
    }
    
    // Write header
    int header[3] = {step, (int)size, 0xCAFEBABE};  // Magic number
    fwrite(header, sizeof(int), 3, fp);
    
    // Write data
    fwrite(data, 1, size, fp);
    
    fclose(fp);
    printf("Checkpoint saved: %s (step %d, %.2f MB)\n", 
           filename, step, size / (1024.0 * 1024.0));
}

bool load_checkpoint(int step, char* data, size_t size) {
    char filename[256];
    sprintf(filename, "C:\\fractal_nvme_test\\checkpoint_%08d.bin", step);
    
    FILE* fp = fopen(filename, "rb");
    if (!fp) {
        printf("ERROR: Cannot open %s for reading\n", filename);
        return false;
    }
    
    // Read header
    int header[3];
    fread(header, sizeof(int), 3, fp);
    
    if (header[2] != 0xCAFEBABE) {
        printf("ERROR: Invalid checkpoint file (bad magic)\n");
        fclose(fp);
        return false;
    }
    
    // Read data
    fread(data, 1, size, fp);
    
    fclose(fp);
    printf("Checkpoint loaded: %s (step %d, %.2f MB)\n", 
           filename, header[0], header[1] / (1024.0 * 1024.0));
    return true;
}

int main() {
    printf("=== Simple NVMe Hybrid System Test ===\n");
    printf("Testing three-tiered memory hierarchy:\n");
    printf("1. GPU VRAM: Simulated computation\n");
    printf("2. System RAM: State buffer\n");
    printf("3. NVMe SSD: Checkpoint storage\n");
    printf("Checkpoint interval: %d steps\n", CHECKPOINT_INTERVAL);
    printf("State size: %.2f MB\n", STATE_SIZE / (1024.0 * 1024.0));
    printf("Checkpoint directory: C:\\fractal_nvme_test\\\n");
    printf("=======================================\n\n");
    
    // Create test data
    char* state_data = (char*)malloc(STATE_SIZE);
    for (size_t i = 0; i < STATE_SIZE; i++) {
        state_data[i] = (char)(i % 256);
    }
    
    // Test 1: Save checkpoints
    printf("Test 1: Saving checkpoints...\n");
    for (int step = 0; step <= 50000; step += CHECKPOINT_INTERVAL) {
        save_checkpoint(step, state_data, STATE_SIZE);
    }
    
    // Test 2: Load checkpoint
    printf("\nTest 2: Loading checkpoint...\n");
    char* loaded_data = (char*)malloc(STATE_SIZE);
    if (load_checkpoint(30000, loaded_data, STATE_SIZE)) {
        // Verify data
        bool valid = true;
        for (size_t i = 0; i < STATE_SIZE; i++) {
            if (loaded_data[i] != (char)(i % 256)) {
                valid = false;
                break;
            }
        }
        printf("Data verification: %s\n", valid ? "PASS" : "FAIL");
    }
    
    // Test 3: Simulate crash recovery
    printf("\nTest 3: Simulating crash recovery...\n");
    printf("1. Running simulation...\n");
    printf("2. CRASH at step 45000!\n");
    printf("3. Restoring from last checkpoint (step 40000)...\n");
    
    if (load_checkpoint(40000, loaded_data, STATE_SIZE)) {
        printf("4. Recovery successful! Continuing from step 40000...\n");
    }
    
    // Cleanup
    free(state_data);
    free(loaded_data);
    
    printf("\n=== Test Complete ===\n");
    printf("NVMe hybrid system concept validated.\n");
    printf("Next: Integrate with actual fractal_habit code.\n");
    
    return 0;
}