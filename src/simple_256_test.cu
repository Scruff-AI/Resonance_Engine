// Simple 256×256 test - minimal CUDA code to verify compilation
#include <cuda_runtime.h>
#include <stdio.h>

#define NX 256
#define NY 256
#define NN (NX * NY)

__global__ void test_kernel(float* data) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < NN) {
        data[idx] = idx * 0.001f;
    }
}

int main() {
    printf("Testing 256×256 compilation...\n");
    printf("Grid: %d x %d = %d cells\n", NX, NY, NN);
    
    float* d_data;
    cudaMalloc(&d_data, NN * sizeof(float));
    
    int threads = 256;
    int blocks = (NN + threads - 1) / threads;
    
    test_kernel<<<blocks, threads>>>(d_data);
    
    cudaDeviceSynchronize();
    printf("Kernel launched: %d blocks, %d threads\n", blocks, threads);
    
    cudaFree(d_data);
    printf("Test completed successfully!\n");
    
    return 0;
}