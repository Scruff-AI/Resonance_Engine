# Build fractal_habit for Windows
Write-Host "Setting up Visual Studio environment..." -ForegroundColor Yellow

# Set Visual Studio environment
$vsPath = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
$vcvarsPath = "$vsPath\VC\Auxiliary\Build\vcvars64.bat"

if (-not (Test-Path $vcvarsPath)) {
    Write-Host "Error: vcvars64.bat not found at $vcvarsPath" -ForegroundColor Red
    exit 1
}

# Run vcvars64.bat to set up environment
cmd /c "`"$vcvarsPath`" > nul 2>&1 && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        $name = $matches[1]
        $value = $matches[2]
        [Environment]::SetEnvironmentVariable($name, $value)
    }
}

Write-Host "Building fractal_habit.cu..." -ForegroundColor Yellow

# CUDA compilation flags
$cudaFlags = @(
    "-arch=sm_89",
    "-O3",
    "-D_USE_MATH_DEFINES",  # For M_PI on Windows
    "-DWIN32",              # Windows define
    "-D_CRT_SECURE_NO_WARNINGS",
    "--compiler-options", "/EHsc", "/W3", "/nologo"
)

# Source and output paths
$sourceDir = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src"
$outputDir = "D:\openclaw-local\workspace-main\build"
$sourceFile = "$sourceDir\fractal_habit.cu"
$outputExe = "$outputDir\fractal_habit.exe"

# Create output directory
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Build command
$buildCmd = "nvcc $($cudaFlags -join ' ') `"$sourceFile`" -o `"$outputExe`" -lnvml -lcufft"

Write-Host "Running: $buildCmd" -ForegroundColor Cyan

# Execute build
$result = cmd /c "$buildCmd 2>&1"

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful! Output: $outputExe" -ForegroundColor Green
    Write-Host "File size: $((Get-Item $outputExe).Length) bytes" -ForegroundColor Green
} else {
    Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
    Write-Host "Output:" -ForegroundColor Red
    $result
    exit $LASTEXITCODE
}