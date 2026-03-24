# Heavy GPU stress to push power above 150W
import torch
import time

def heavy_stress():
    print("Heavy GPU stress starting...")
    print("Target: Push GPU power above 150W")
    
    # Multiple large tensors to maximize memory and compute
    tensors = []
    for i in range(5):
        size = 15000
        a = torch.randn(size, size, device='cuda')
        b = torch.randn(size, size, device='cuda')
        tensors.append((a, b))
    
    print(f"Allocated {sum(a.nelement() + b.nelement() for a, b in tensors) * 4 / 1e9:.1f} GB")
    
    iterations = 0
    start = time.time()
    
    try:
        while time.time() - start < 120:  # 2 minutes
            for a, b in tensors:
                c = torch.matmul(a, b)
                torch.cuda.synchronize()
            iterations += 1
            if iterations % 10 == 0:
                print(f"Iterations: {iterations}, Time: {time.time() - start:.1f}s")
    except KeyboardInterrupt:
        pass
    
    print(f"Completed {iterations} iterations")

if __name__ == '__main__':
    if torch.cuda.is_available():
        print(f"GPU: {torch.cuda.get_device_name(0)}")
        heavy_stress()
    else:
        print("CUDA not available")
