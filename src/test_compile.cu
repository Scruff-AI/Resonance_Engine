#include <stdio.h>

__global__ void test_kernel() {
    printf("Test kernel running\n");
}

int main() {
    printf("CUDA compilation test\n");
    test_kernel<<<1, 1>>>();
    cudaDeviceSynchronize();
    return 0;
}