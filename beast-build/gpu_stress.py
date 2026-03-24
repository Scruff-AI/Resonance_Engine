# GPU stress test to simulate LLM load
import torch
import time

def stress_gpu(duration_seconds=30):
    print(f"Stressing GPU for {duration_seconds} seconds...")
    
    # Large matrix multiplication to simulate LLM workload
    size = 10000
    a = torch.randn(size, size, device='cuda')
    b = torch.randn(size, size, device='cuda')
    
    start = time.time()
    iterations = 0
    
    while time.time() - start < duration_seconds:
        c = torch.matmul(a, b)
        torch.cuda.synchronize()
        iterations += 1
    
    print(f"Completed {iterations} matmul operations")
    print(f"GPU memory used: {torch.cuda.memory_allocated() / 1e9:.2f} GB")

if __name__ == '__main__':
    if torch.cuda.is_available():
        print(f"GPU: {torch.cuda.get_device_name(0)}")
        stress_gpu(60)  # 60 seconds of GPU load
    else:
        print("CUDA not available")
