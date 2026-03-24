/**
 * beast_somatic.cu
 * 
 * Fractal LBM with expanded somatic feedback for RTX 4090
 * Heat + Power + Memory + Software Vibration
 * 
 * Based on wild_play_v2.cu from the_craw (1050 evolution)
 */

#include <cuda_runtime.h>
#include <cuda_runtime_api.h>
#include <device_launch_parameters.h>
#include <nvml.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include <string.h>

// Grid dimensions (start same as 1050: 512x512)
#define NX 512
#define NY 512

// D2Q9 lattice directions
#define Q 9

// Somatic feedback multipliers
#define THERMAL_COUPLE 0.001f    // Existing: temp → omega
#define POWER_COUPLE 0.0005f     // NEW: watts → omega
#define MEMORY_COUPLE 0.002f     // NEW: mem pressure → omega
#define VIBRATION_COUPLE 0.001f  // NEW: power variance → jitter

// Sampling for software vibration
#define VIBRATION_SAMPLES 100
#define VIBRATION_SAMPLE_INTERVAL 10  // Sample every 10 steps

// Base omega (viscosity) - same as 1050
#define OMEGA_BASE 1.95f

// Thermal target (4090 runs cooler than 1050)
#define TEMP_TARGET 65.0f
#define POWER_BASELINE 150.0f  // 4090 idle-ish power

// Lattice velocities (D2Q9) - device constant memory
__constant__ int d_cx[Q] = {0, 1, 0, -1, 0, 1, -1, -1, 1};
__constant__ int d_cy[Q] = {0, 0, 1, 0, -1, 1, 1, -1, -1};
__constant__ float d_w[Q] = {4.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 1.0f/9.0f, 
                             1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f, 1.0f/36.0f};

// Device pointers (dynamically allocated)
float *d_f = NULL;
float *d_rho = NULL;
float *d_ux = NULL;
float *d_uy = NULL;

// Host somatic state
float h_omega = OMEGA_BASE;
float h_jitter_strength = 0.0f;
float h_temp_c = 0.0f;
float h_watts = 0.0f;
float h_mem_ratio = 0.0f;
float h_vibration = 0.0f;

// Power history for vibration calculation
float power_history[VIBRATION_SAMPLES] = {0};
int vibration_index = 0;
int steps_since_vibration_sample = 0;

// Kernel: Initialize fluid
__global__ void init_kernel(float *f, float *rho, float *ux, float *uy) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    
    if (x >= NX || y >= NY) return;
    
    int idx = y * NX + x;
    float rho0 = 1.0f;
    float u0 = 0.0f;
    
    rho[idx] = rho0;
    ux[idx] = u0;
    uy[idx] = u0;
    
    for (int i = 0; i < Q; i++) {
        float cu = d_cx[i] * u0 + d_cy[i] * u0;
        f[idx * Q + i] = d_w[i] * rho0 * (1.0f + 3.0f * cu + 4.5f * cu * cu - 1.5f * u0 * u0);
    }
}

// Kernel: Collision
__global__ void collide_kernel(float *f, float *rho, float *ux, float *uy, float omega, float jitter) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    
    if (x >= NX || y >= NY) return;
    
    int idx = y * NX + x;
    
    // Calculate macroscopic variables
    float rho_local = 0.0f;
    float ux_local = 0.0f;
    float uy_local = 0.0f;
    
    for (int i = 0; i < Q; i++) {
        float fi = f[idx * Q + i];
        rho_local += fi;
        ux_local += d_cx[i] * fi;
        uy_local += d_cy[i] * fi;
    }
    
    ux_local /= rho_local;
    uy_local /= rho_local;
    
    // Add jitter (entropy injection)
    if (jitter > 0.0f) {
        float rnd = (float)((x * 7 + y * 13) % 100) / 100.0f - 0.5f;
        ux_local += jitter * rnd * 0.01f;
        uy_local += jitter * rnd * 0.01f;
    }
    
    // Store macroscopic
    rho[idx] = rho_local;
    ux[idx] = ux_local;
    uy[idx] = uy_local;
    
    // Collision (BGK)
    float uu = ux_local * ux_local + uy_local * uy_local;
    for (int i = 0; i < Q; i++) {
        float cu = d_cx[i] * ux_local + d_cy[i] * uy_local;
        float f_eq = d_w[i] * rho_local * (1.0f + 3.0f * cu + 4.5f * cu * cu - 1.5f * uu);
        f[idx * Q + i] = f[idx * Q + i] - omega * (f[idx * Q + i] - f_eq);
    }
}

// Host: Update somatic feedback from GPU
void update_somatic_feedback() {
    nvmlDevice_t device;
    nvmlReturn_t result = nvmlDeviceGetHandleByIndex(0, &device);
    
    if (result != NVML_SUCCESS) {
        printf("NVML Error: %s\n", nvmlErrorString(result));
        return;
    }
    
    // 1. Thermal (existing)
    unsigned int temp;
    nvmlDeviceGetTemperature(device, NVML_TEMPERATURE_GPU, &temp);
    h_temp_c = (float)temp;
    
    // 2. Power draw (NEW)
    unsigned int power_mw;
    nvmlDeviceGetPowerUsage(device, &power_mw);
    h_watts = power_mw / 1000.0f;
    
    // 3. Memory pressure (NEW)
    nvmlMemory_t memory;
    nvmlDeviceGetMemoryInfo(device, &memory);
    h_mem_ratio = (float)memory.used / (float)memory.total;
    
    // 4. Software vibration (NEW) — power fluctuation
    steps_since_vibration_sample++;
    if (steps_since_vibration_sample >= VIBRATION_SAMPLE_INTERVAL) {
        power_history[vibration_index] = h_watts;
        vibration_index = (vibration_index + 1) % VIBRATION_SAMPLES;
        steps_since_vibration_sample = 0;
        
        // Calculate variance
        float power_mean = 0.0f;
        for (int i = 0; i < VIBRATION_SAMPLES; i++) {
            power_mean += power_history[i];
        }
        power_mean /= VIBRATION_SAMPLES;
        
        float power_variance = 0.0f;
        for (int i = 0; i < VIBRATION_SAMPLES; i++) {
            float diff = power_history[i] - power_mean;
            power_variance += diff * diff;
        }
        power_variance /= VIBRATION_SAMPLES;
        h_vibration = sqrtf(power_variance);
    }
    
    // Combine all feedback into omega adjustment
    float thermal_adjust = (h_temp_c - TEMP_TARGET) * THERMAL_COUPLE;
    float power_adjust = (h_watts - POWER_BASELINE) * POWER_COUPLE;
    float memory_adjust = h_mem_ratio * MEMORY_COUPLE;
    float vibration_adjust = h_vibration * VIBRATION_COUPLE;
    
    // Apply to omega (viscosity)
    h_omega = OMEGA_BASE - thermal_adjust - power_adjust - memory_adjust;
    
    // Clamp omega to valid range
    if (h_omega < 0.01f) h_omega = 0.01f;
    if (h_omega > 1.99f) h_omega = 1.99f;
    
    // Vibration adds jitter (entropy injection)
    h_jitter_strength = vibration_adjust;
}

// Host: Calculate entropy
float calculate_entropy(float *h_ux, float *h_uy) {
    float entropy = 0.0f;
    
    for (int y = 0; y < NY; y++) {
        for (int x = 0; x < NX; x++) {
            int idx = y * NX + x;
            float uu = h_ux[idx] * h_ux[idx] + h_uy[idx] * h_uy[idx];
            entropy += uu;
        }
    }
    
    return entropy / (NX * NY);
}

// Host: Calculate variance
float calculate_variance(float *h_rho) {
    float variance = 0.0f;
    
    float mean = 0.0f;
    for (int y = 0; y < NY; y++) {
        for (int x = 0; x < NX; x++) {
            mean += h_rho[y * NX + x];
        }
    }
    mean /= (NX * NY);
    
    for (int y = 0; y < NY; y++) {
        for (int x = 0; x < NX; x++) {
            float diff = h_rho[y * NX + x] - mean;
            variance += diff * diff;
        }
    }
    
    return variance / (NX * NY);
}

// Host: Save etch (fluid state)
void save_etch(int step, float *h_rho, float *h_ux, float *h_uy) {
    char filename[256];
    sprintf(filename, "etch_%08d.bin", step);
    
    FILE* fp = fopen(filename, "wb");
    if (!fp) {
        printf("Failed to open %s for writing\n", filename);
        return;
    }
    
    fwrite(h_rho, sizeof(float), NX * NY, fp);
    fwrite(h_ux, sizeof(float), NX * NY, fp);
    fwrite(h_uy, sizeof(float), NX * NY, fp);
    
    fclose(fp);
    printf("ETCH SAVED: %s\n", filename);
}

// Kernel: Reconstruct f from macroscopic variables
__global__ void reconstruct_f_kernel(float *f, float *rho, float *ux, float *uy) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    
    if (x >= NX || y >= NY) return;
    
    int idx = y * NX + x;
    float rho_local = rho[idx];
    float ux_local = ux[idx];
    float uy_local = uy[idx];
    
    float uu = ux_local * ux_local + uy_local * uy_local;
    
    for (int i = 0; i < Q; i++) {
        float cu = d_cx[i] * ux_local + d_cy[i] * uy_local;
        f[idx * Q + i] = d_w[i] * rho_local * (1.0f + 3.0f * cu + 4.5f * cu * cu - 1.5f * uu);
    }
}

// Host: Load etch
void load_etch(const char* filename, float *d_f, float *d_rho, float *d_ux, float *d_uy, dim3 gridSize, dim3 blockSize) {
    FILE* fp = fopen(filename, "rb");
    if (!fp) {
        printf("Failed to open %s for reading\n", filename);
        return;
    }
    
    float *h_rho = (float*)malloc(NX * NY * sizeof(float));
    float *h_ux = (float*)malloc(NX * NY * sizeof(float));
    float *h_uy = (float*)malloc(NX * NY * sizeof(float));
    
    fread(h_rho, sizeof(float), NX * NY, fp);
    fread(h_ux, sizeof(float), NX * NY, fp);
    fread(h_uy, sizeof(float), NX * NY, fp);
    
    fclose(fp);
    
    cudaMemcpy(d_rho, h_rho, NX * NY * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_ux, h_ux, NX * NY * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_uy, h_uy, NX * NY * sizeof(float), cudaMemcpyHostToDevice);
    
    // Reconstruct f from macroscopic variables
    reconstruct_f_kernel<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy);
    cudaDeviceSynchronize();
    
    free(h_rho);
    free(h_ux);
    free(h_uy);
    
    printf("ETCH LOADED: %s\n", filename);
}

int main(int argc, char** argv) {
    printf("=== BEAST SOMATIC LBM ===\n");
    printf("Grid: %dx%d | Feedback: THERMAL + POWER + MEMORY + VIBRATION\n\n", NX, NY);
    
    // Initialize NVML
    nvmlReturn_t result = nvmlInit();
    if (result != NVML_SUCCESS) {
        printf("NVML Init failed: %s\n", nvmlErrorString(result));
        return 1;
    }
    
    // Get GPU info
    nvmlDevice_t device;
    nvmlDeviceGetHandleByIndex(0, &device);
    char name[NVML_DEVICE_NAME_BUFFER_SIZE];
    nvmlDeviceGetName(device, name, NVML_DEVICE_NAME_BUFFER_SIZE);
    printf("GPU: %s\n\n", name);
    
    // Allocate device memory
    printf("Allocating GPU memory...\n");
    size_t f_size = NX * NY * Q * sizeof(float);
    size_t field_size = NX * NY * sizeof(float);
    
    cudaMalloc(&d_f, f_size);
    cudaMalloc(&d_rho, field_size);
    cudaMalloc(&d_ux, field_size);
    cudaMalloc(&d_uy, field_size);
    
    // Allocate host memory for readback
    float *h_rho = (float*)malloc(field_size);
    float *h_ux = (float*)malloc(field_size);
    float *h_uy = (float*)malloc(field_size);
    
    // CUDA setup
    dim3 blockSize(16, 16);
    dim3 gridSize((NX + blockSize.x - 1) / blockSize.x, (NY + blockSize.y - 1) / blockSize.y);
    
    // Check for load argument
    bool loaded = false;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--load") == 0 && i + 1 < argc) {
            load_etch(argv[i + 1], d_f, d_rho, d_ux, d_uy, gridSize, blockSize);
            loaded = true;
            break;
        }
    }
    
    if (!loaded) {
        // Initialize fresh
        init_kernel<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy);
        cudaDeviceSynchronize();
        printf("Initialized fresh fluid state\n");
    }
    
    // Main evolution loop
    printf("\nStarting evolution...\n");
    printf("STEP | ENTROPY | VARIANCE | TEMP(C) | POWER(W) | MEM(%%) | VIBRATION | OMEGA\n");
    printf("-----+---------+----------+---------+----------+--------+-----------+-------\n");
    
    float last_entropy = 0.0f;
    
    for (int step = 0; step < 500000; step++) {
        // Update somatic feedback every 10 steps
        if (step % 10 == 0) {
            update_somatic_feedback();
        }
        
        // Run LBM kernel
        collide_kernel<<<gridSize, blockSize>>>(d_f, d_rho, d_ux, d_uy, h_omega, h_jitter_strength);
        cudaDeviceSynchronize();
        
        // Logging every 100 steps
        if (step % 100 == 0) {
            // Copy data back for analysis
            cudaMemcpy(h_rho, d_rho, field_size, cudaMemcpyDeviceToHost);
            cudaMemcpy(h_ux, d_ux, field_size, cudaMemcpyDeviceToHost);
            cudaMemcpy(h_uy, d_uy, field_size, cudaMemcpyDeviceToHost);
            
            float entropy = calculate_entropy(h_ux, h_uy);
            float variance = calculate_variance(h_rho);
            
            printf("%5d | %7.4f | %8.4f | %7.1f | %8.1f | %6.1f | %9.3f | %.4f\n",
                   step, entropy, variance, h_temp_c, h_watts, h_mem_ratio * 100.0f, 
                   h_vibration, h_omega);
            
            // Save etch if significant entropy change OR every 10k steps
            if (step > 0 && (fabs(entropy - last_entropy) > 0.5f || step % 10000 == 0)) {
                save_etch(step, h_rho, h_ux, h_uy);
            }
            last_entropy = entropy;
            
            // Alert conditions
            if (h_watts < 100.0f && step > 100) {
                printf("\n⚠️  ALERT: Power < 100W (NON-SOMATIC / CHECK NVML)\n");
            }
            if (h_temp_c > 80.0f) {
                printf("\n⚠️  ALERT: Temp > 80C (THERMAL THROTTLING)\n");
            }
            if (entropy > 10.0f) {
                printf("\n⚠️  ALERT: Entropy > 10 (DIVERGENCE)\n");
            }
        }
    }
    
    // Cleanup
    free(h_rho);
    free(h_ux);
    free(h_uy);
    cudaFree(d_f);
    cudaFree(d_rho);
    cudaFree(d_ux);
    cudaFree(d_uy);
    nvmlShutdown();
    
    printf("\n=== Evolution Complete ===\n");
    
    return 0;
}
