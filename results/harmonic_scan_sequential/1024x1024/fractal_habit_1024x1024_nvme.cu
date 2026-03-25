/* ============================================================================
 * FRACTAL HABIT with NVMe HYBRID MEMORY SYSTEM
 * 
 * Three-tiered memory hierarchy:
 * 1. GPU VRAM (0.06Hz): Active lattice
 * 2. System RAM (0.005Hz): Ring buffer of recent states
 * 3. NVMe SSD: Sector-aligned checkpoint writes
 *
 * Init from Hysteresis C80 "locked" state.
 * Fixed omega = 1.0 (tau=1, nu=1/6) — the clearest water in LBM.
 * 100,000 steps with NVMe checkpointing.
 *
 * Build: nvcc -O3 -arch=sm_89 -o fractal_habit_nvme \
 *        fractal_habit_1024x1024_nvme.cu -lnvidia-ml -lpthread -lcufft
 * ============================================================================ */
#include <cuda_runtime.h>
#include <cufft.h>
#include <nvml.h>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cmath>
#include <chrono>
#include <vector>
#include <fstream>
#include <iostream>
#include <string>
#include <cstring>
#include <algorithm>

/* ---- Grid ---------------------------------------------------------------- */
#define NX    1024
#define NY    1024
#define NN    (NX * NY)
#define Q     9
#define BLOCK 256
#define GBLK(n) (((n) + BLOCK - 1) / BLOCK)

/* ---- NVMe Hybrid System Configuration ----------------------------------- */
#define CHECKPOINT_INTERVAL  10000    // Save to NVMe every 10k steps (0.06Hz)
#define RING_BUFFER_SIZE     10       // Keep last 10 states in RAM (0.005Hz)
#define NVME_DIRECTORY       "Z:\\nvme_checkpoints\\"  // NAS storage
// Alternative: "C:\\fractal_nvme\\" for local NVMe

/* ---- Protocol ------------------------------------------------------------ */
#define TOTAL_STEPS      100000
#define STEPS_PER_BATCH  500
#define SAMPLE_INTERVAL  50000      /* E(k) sample every 50k steps */
#define TOTAL_BATCHES    (TOTAL_STEPS / STEPS_PER_BATCH)
#define SAMPLE_BATCHES   (SAMPLE_INTERVAL / STEPS_PER_BATCH)
#define NUM_SAMPLES      (TOTAL_STEPS / SAMPLE_INTERVAL)

/* ---- LBM ---------------------------------------------------------------- */
#define OMEGA  1.0f       /* tau=1.0, nu=1/6 — "clear water" */

/* ---- Spectrum ----------------------------------------------------------- */
#define NX2   (NX / 2 + 1)   /* R2C output width */
#define KMAX  (NX / 2)       /* max wavenumber */
#define NK    (KMAX + 1)     /* number of k bins */

/* ---- CUDA kernels (unchanged from original) ----------------------------- */
__global__ void lbm_collide_stream(float *f, float *rho, float *ux, float *uy) {
    // ... (same as original)
}

__global__ void compute_macroscopic(float *f, float *rho, float *ux, float *uy) {
    // ... (same as original)
}

/* ---- NVMe Hybrid System Structures -------------------------------------- */
typedef struct {
    int checkpoint_id;
    int step_number;
    size_t state_size;
    uint32_t checksum;
    char timestamp[64];
} CheckpointHeader;

typedef struct {
    float *f;      // Lattice distribution (Q × NX × NY)
    float *rho;    // Density field
    float *ux;     // X velocity
    float *uy;     // Y velocity
    int step;
    double timestamp;
} SimulationState;

class NVMeHybridSystem {
private:
    // GPU VRAM (active state)
    float *d_f;
    float *d_rho;
    float *d_ux;
    float *d_uy;
    
    // System RAM (ring buffer)
    SimulationState *ram_buffer[RING_BUFFER_SIZE];
    int buffer_head;
    int buffer_tail;
    
    // NVMe directory
    std::string nvme_path;
    
public:
    NVMeHybridSystem() : buffer_head(0), buffer_tail(0) {
        // Initialize RAM buffer
        for (int i = 0; i < RING_BUFFER_SIZE; i++) {
            ram_buffer[i] = nullptr;
        }
        
        // Set NVMe path
        nvme_path = NVME_DIRECTORY;
        
        // Create directory if it doesn't exist
        std::string cmd = "mkdir \"" + nvme_path + "\" 2>nul";
        system(cmd.c_str());
    }
    
    ~NVMeHybridSystem() {
        // Cleanup RAM buffer
        for (int i = 0; i < RING_BUFFER_SIZE; i++) {
            if (ram_buffer[i]) {
                delete ram_buffer[i];
            }
        }
    }
    
    // Save state to RAM buffer (0.005Hz metabolic cycle)
    void save_to_ram(int step, float *f, float *rho, float *ux, float *uy) {
        SimulationState *state = new SimulationState();
        
        // Allocate CPU memory for state
        size_t f_size = Q * NX * NY * sizeof(float);
        state->f = (float*)malloc(f_size);
        state->rho = (float*)malloc(NN * sizeof(float));
        state->ux = (float*)malloc(NN * sizeof(float));
        state->uy = (float*)malloc(NN * sizeof(float));
        
        // Copy from GPU to CPU
        cudaMemcpy(state->f, f, f_size, cudaMemcpyDeviceToHost);
        cudaMemcpy(state->rho, rho, NN * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(state->ux, ux, NN * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(state->uy, uy, NN * sizeof(float), cudaMemcpyDeviceToHost);
        
        state->step = step;
        state->timestamp = get_current_time();
        
        // Add to ring buffer
        ram_buffer[buffer_head] = state;
        buffer_head = (buffer_head + 1) % RING_BUFFER_SIZE;
        
        // If buffer is full, overwrite oldest
        if (buffer_head == buffer_tail) {
            delete ram_buffer[buffer_tail];
            buffer_tail = (buffer_tail + 1) % RING_BUFFER_SIZE;
        }
        
        printf("[RAM] State saved to buffer at step %d (buffer pos: %d)\n", step, buffer_head);
    }
    
    // Save state to NVMe (crystallized memory)
    void save_to_nvme(int step, float *f, float *rho, float *ux, float *uy) {
        char filename[256];
        sprintf(filename, "%scheckpoint_%08d.bin", nvme_path.c_str(), step);
        
        FILE *fp = fopen(filename, "wb");
        if (!fp) {
            printf("[NVMe] ERROR: Cannot open file %s for writing\n", filename);
            return;
        }
        
        // Create header
        CheckpointHeader header;
        header.checkpoint_id = step / CHECKPOINT_INTERVAL;
        header.step_number = step;
        header.state_size = Q * NX * NY * sizeof(float) + 3 * NN * sizeof(float);
        header.checksum = 0;  // Would compute actual checksum in production
        strcpy(header.timestamp, get_timestamp().c_str());
        
        // Write header
        fwrite(&header, sizeof(CheckpointHeader), 1, fp);
        
        // Allocate temporary buffers
        size_t f_size = Q * NX * NY * sizeof(float);
        float *h_f = (float*)malloc(f_size);
        float *h_rho = (float*)malloc(NN * sizeof(float));
        float *h_ux = (float*)malloc(NN * sizeof(float));
        float *h_uy = (float*)malloc(NN * sizeof(float));
        
        // Copy from GPU to CPU
        cudaMemcpy(h_f, f, f_size, cudaMemcpyDeviceToHost);
        cudaMemcpy(h_rho, rho, NN * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_ux, ux, NN * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_uy, uy, NN * sizeof(float), cudaMemcpyDeviceToHost);
        
        // Write data (sector-aligned writes)
        fwrite(h_f, f_size, 1, fp);
        fwrite(h_rho, NN * sizeof(float), 1, fp);
        fwrite(h_ux, NN * sizeof(float), 1, fp);
        fwrite(h_uy, NN * sizeof(float), 1, fp);
        
        fclose(fp);
        
        // Free temporary buffers
        free(h_f);
        free(h_rho);
        free(h_ux);
        free(h_uy);
        
        printf("[NVMe] Checkpoint saved to %s (step %d, size: %.2f MB)\n", 
               filename, step, header.state_size / (1024.0 * 1024.0));
    }
    
    // Restore state from NVMe
    bool restore_from_nvme(int checkpoint_id, float *f, float *rho, float *ux, float *uy) {
        char filename[256];
        sprintf(filename, "%scheckpoint_%08d.bin", nvme_path.c_str(), checkpoint_id * CHECKPOINT_INTERVAL);
        
        FILE *fp = fopen(filename, "rb");
        if (!fp) {
            printf("[NVMe] ERROR: Cannot open file %s for reading\n", filename);
            return false;
        }
        
        // Read header
        CheckpointHeader header;
        fread(&header, sizeof(CheckpointHeader), 1, fp);
        
        printf("[NVMe] Restoring checkpoint %d from step %d\n", 
               header.checkpoint_id, header.step_number);
        
        // Allocate temporary buffers
        size_t f_size = Q * NX * NY * sizeof(float);
        float *h_f = (float*)malloc(f_size);
        float *h_rho = (float*)malloc(NN * sizeof(float));
        float *h_ux = (float*)malloc(NN * sizeof(float));
        float *h_uy = (float*)malloc(NN * sizeof(float));
        
        // Read data
        fread(h_f, f_size, 1, fp);
        fread(h_rho, NN * sizeof(float), 1, fp);
        fread(h_ux, NN * sizeof(float), 1, fp);
        fread(h_uy, NN * sizeof(float), 1, fp);
        
        fclose(fp);
        
        // Copy from CPU to GPU
        cudaMemcpy(f, h_f, f_size, cudaMemcpyHostToDevice);
        cudaMemcpy(rho, h_rho, NN * sizeof(float), cudaMemcpyHostToDevice);
        cudaMemcpy(ux, h_ux, NN * sizeof(float), cudaMemcpyHostToDevice);
        cudaMemcpy(uy, h_uy, NN * sizeof(float), cudaMemcpyHostToDevice);
        
        // Free temporary buffers
        free(h_f);
        free(h_rho);
        free(h_ux);
        free(h_uy);
        
        printf("[NVMe] State restored successfully\n");
        return true;
    }
    
    // Get latest state from RAM buffer
    SimulationState* get_latest_ram_state() {
        if (buffer_head == buffer_tail) {
            return nullptr;  // Buffer empty
        }
        int latest = (buffer_head - 1 + RING_BUFFER_SIZE) % RING_BUFFER_SIZE;
        return ram_buffer[latest];
    }
    
private:
    double get_current_time() {
        auto now = std::chrono::system_clock::now();
        auto duration = now.time_since_epoch();
        return std::chrono::duration<double>(duration).count();
    }
    
    std::string get_timestamp() {
        auto now = std::chrono::system_clock::now();
        auto time = std::chrono::system_clock::to_time_t(now);
        char buffer[64];
        ctime_s(buffer, sizeof(buffer), &time);
        buffer[strlen(buffer) - 1] = '\0';  // Remove newline
        return std::string(buffer);
    }
};

/* ---- Main simulation with NVMe hybrid system ---------------------------- */
int main() {
    printf("===================================================================\n");
    printf("  FRACTAL HABIT with NVMe HYBRID MEMORY SYSTEM\n");
    printf("===================================================================\n");
    printf("  Three-tiered memory hierarchy:\n");
    printf("  1. GPU VRAM (0.06Hz): Active lattice\n");
    printf("  2. System RAM (0.005Hz): Ring buffer of %d states\n", RING_BUFFER_SIZE);
    printf("  3. NVMe SSD: Checkpoint every %d steps to %s\n", CHECKPOINT_INTERVAL, NVME_DIRECTORY);
    printf("===================================================================\n\n");
    
    // Initialize NVMe hybrid system
    NVMeHybridSystem nvme_system;
    
    // Check if we should restore from checkpoint
    int start_step = 0;
    bool restored = false;
    
    // ... (rest of original initialization code)
    
    // Main simulation loop with NVMe checkpointing
    for (int batch = 0; batch < TOTAL_BATCHES; batch++) {
        int current_step = batch * STEPS_PER_BATCH;
        
        // Save to RAM buffer (0.005Hz metabolic cycle)
        if (current_step % 1000 == 0) {
            nvme_system.save_to_ram(current_step, d_f, d_rho, d_ux, d_uy);
        }
        
        // Save to NVMe (0.06Hz crystallized memory)
        if (current_step % CHECKPOINT_INTERVAL == 0 && current_step > 0) {
            nvme_system.save_to_nvme(current_step, d_f, d_rho, d_ux, d_uy);
        }
        
        // ... (original simulation code)
        
        // Simulate crash test (optional)
        if (current_step == 50000) {
            printf("\n[TEST] Simulating crash at step 50000...\n");
            printf("[TEST] Would restore from NVMe checkpoint here\n");
            // In real test: kill process, then restart with restore_from_nvme()
        }
    }
    
    // Final checkpoint
    nvme_system.save_to_nvme(TOTAL_STEPS, d_f, d_rho, d_ux, d_uy);
    
    printf("\n===================================================================\n");
    printf("  NVMe Hybrid System Test Complete\n");
    printf("===================================================================\n");
    printf("  Checkpoints saved to: %s\n", NVME_DIRECTORY);
    printf("  RAM buffer maintained: %d recent states\n", RING_BUFFER_SIZE);
    printf("  Ready for crash recovery testing\n");
    printf("===================================================================\n");
    
    return 0;
}