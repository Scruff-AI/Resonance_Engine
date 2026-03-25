# Set up Visual Studio environment for CUDA compilation
Write-Host "Setting up Visual Studio 2022 Build Tools..." -ForegroundColor Cyan

# Visual Studio paths
$vsPath = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64"
$cudaPath = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin"

# Add to PATH
$env:PATH = "$vsPath;$cudaPath;" + $env:PATH

Write-Host "Visual Studio cl.exe: $vsPath\cl.exe" -ForegroundColor Green
Write-Host "CUDA nvcc: $cudaPath\nvcc.exe" -ForegroundColor Green

# Test cl.exe
Write-Host "`nTesting cl.exe..." -ForegroundColor Yellow
cl --version 2>&1 | Select-Object -First 3

# Test nvcc
Write-Host "`nTesting nvcc..." -ForegroundColor Yellow
nvcc --version 2>&1 | Select-Object -First 3

# Try to compile a simple test
Write-Host "`nCompiling simple test..." -ForegroundColor Cyan

$testCode = @'
#include <stdio.h>
int main() {
    printf("Test compilation works!\n");
    return 0;
}
'@

Set-Content -Path "test_compile.c" -Value $testCode
cl test_compile.c 2>&1

if (Test-Path "test_compile.exe") {
    Write-Host "`n✅ CL.EXE WORKS!" -ForegroundColor Green
    .\test_compile.exe
    Remove-Item test_compile.*
    
    # Now try CUDA compilation
    Write-Host "`nTrying CUDA compilation..." -ForegroundColor Cyan
    
    $cudaTest = @'
#include <cuda_runtime.h>
#include <stdio.h>
__global__ void test() {}
int main() {
    test<<<1,1>>>();
    cudaDeviceSynchronize();
    printf("CUDA test compiled!\n");
    return 0;
}
'@
    
    Set-Content -Path "test_cuda.cu" -Value $cudaTest
    nvcc -o test_cuda.exe test_cuda.cu 2>&1
    
    if (Test-Path "test_cuda.exe") {
        Write-Host "`n✅ CUDA COMPILATION WORKS!" -ForegroundColor Green
        .\test_cuda.exe
        Remove-Item test_cuda.*
        
        Write-Host "`n🎯 READY TO COMPILE FRACTAL_HABIT_256!" -ForegroundColor Green
    } else {
        Write-Host "`n❌ CUDA compilation failed" -ForegroundColor Red
    }
} else {
    Write-Host "`n❌ CL.EXE failed" -ForegroundColor Red
}