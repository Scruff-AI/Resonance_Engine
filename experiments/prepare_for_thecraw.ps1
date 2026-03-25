# Prepare files for compilation on the-craw (Ubuntu server with CUDA)

Write-Host "=== Preparing 256×256 Build for the-craw ===" -ForegroundColor Cyan
Write-Host "Target: GTX 1050 (sm_61) @ 80W" -ForegroundColor Yellow
Write-Host "Grid: 256×256 | Guardians: 12" -ForegroundColor Yellow

# Create directory structure
$buildDir = "thecraw_build_256"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
New-Item -ItemType Directory -Force -Path "$buildDir/src" | Out-Null
New-Item -ItemType Directory -Force -Path "$buildDir/include" | Out-Null
New-Item -ItemType Directory -Force -Path "$buildDir/build" | Out-Null

Write-Host "Created directory: $buildDir" -ForegroundColor Green

# Copy modified source files
Write-Host "`nCopying source files..." -ForegroundColor Cyan

# Copy probe_256.cu (modified for 256×256 with 12 guardians)
Copy-Item "probe_256.cu" "$buildDir/src/probe_256.cu" -Force
Write-Host "  probe_256.cu" -ForegroundColor Gray

# Copy fractal_habit_256_full.cu  
Copy-Item "fractal_habit_256_full.cu" "$buildDir/src/fractal_habit_256.cu" -Force
Write-Host "  fractal_habit_256.cu" -ForegroundColor Gray

# Copy original source files that haven't been modified
$originalSrc = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\src\"
Copy-Item "$originalSrc/kernels.cu" "$buildDir/src/" -Force
Copy-Item "$originalSrc/calibration.cu" "$buildDir/src/" -Force
Write-Host "  kernels.cu, calibration.cu" -ForegroundColor Gray

# Copy include files
$originalInclude = "D:\openclaw-docker-BACKUP-DO-NOT-USE\seed-brain\include\"
if (Test-Path $originalInclude) {
    Copy-Item "$originalInclude/*" "$buildDir/include/" -Recurse -Force
    Write-Host "  include files" -ForegroundColor Gray
}

# Copy brain states
Write-Host "`nCopying brain states..." -ForegroundColor Cyan
Copy-Item "harmonic_brain_states/build_256x256/f_state_post_relax.bin" "$buildDir/build/" -Force
Write-Host "  256×256 brain state" -ForegroundColor Gray

# Create build script for the-craw
$buildScript = @'
#!/bin/bash
# Build script for 256×256 Resonance Engine on the-craw (GTX 1050)
# Run on the-craw: ./build_256.sh

echo "=== Building 256×256 Resonance Engine ==="
echo "Target: GTX 1050 (sm_61)"
echo "Grid: 256×256 | Guardians: 12"

# Check CUDA
if ! command -v nvcc &> /dev/null; then
    echo "ERROR: nvcc not found. Install CUDA toolkit."
    exit 1
fi

# Compile probe_256
echo "Compiling probe_256..."
nvcc -O3 -arch=sm_61 -o probe_256 src/probe_256.cu -lnvidia-ml -lpthread
if [ $? -eq 0 ]; then
    echo "  [OK] probe_256 compiled"
    ls -lh probe_256
else
    echo "  [FAILED] probe_256 compilation"
    exit 1
fi

# Compile fractal_habit_256
echo "Compiling fractal_habit_256..."
nvcc -O3 -arch=sm_61 -o fractal_habit_256 src/fractal_habit_256.cu -lnvidia-ml -lpthread -lcufft
if [ $? -eq 0 ]; then
    echo "  [OK] fractal_habit_256 compiled"
    ls -lh fractal_habit_256
else
    echo "  [FAILED] fractal_habit_256 compilation"
    exit 1
fi

# Test brain state
echo "`nTesting brain state..."
if [ -f "build/f_state_post_relax.bin" ]; then
    echo "  Brain state found: build/f_state_post_relax.bin"
    # Quick header check
    python3 -c "
import struct
with open('build/f_state_post_relax.bin', 'rb') as f:
    hdr = f.read(16)
    magic, nx, ny, q = struct.unpack('IIII', hdr)
    print(f'    Header: {nx}x{ny}, Q={q}')
    if nx == 256 and ny == 256:
        print('    [OK] Correct size (256×256)')
    else:
        print(f'    [ERROR] Wrong size: {nx}x{ny} (expected 256×256)')
"
else
    echo "  [WARNING] Brain state not found"
fi

echo "`n=== Build Complete ==="
echo "To test:"
echo "  ./probe_256"
echo "  ./fractal_habit_256 100000 1  # 100k steps test"
echo "`nGuardian count: 12 (scaled from 194 for 256×256)"
echo "Target power: 40-60W on GTX 1050"
'@

Set-Content -Path "$buildDir/build_256.sh" -Value $buildScript -Encoding UTF8
Write-Host "Created build_256.sh" -ForegroundColor Green

# Create README
$readme = @'
# 256×256 Resonance Engine Build for the-craw

## Target Hardware
- **GPU**: GTX 1050 (Pascal, sm_61)
- **Power target**: 80W (aim for 40-60W operation)
- **Grid size**: 256×256 (1/16 of 1024×1024)
- **Guardians**: 12 (scaled from 194)

## Source Modifications
1. **probe_256.cu**: Modified for 256×256 grid
   - `#define NX 256`, `#define NY 256`
   - `#define MAX_PARTICLES 12` (was 256)

2. **fractal_habit_256.cu**: Modified for 256×256 grid
   - `#define NX 256`, `#define NY 256`
   - Guardian system needs similar modification

## Build Instructions (on the-craw)
```bash
chmod +x build_256.sh
./build_256.sh
```

## Test Instructions
```bash
# Quick test
./fractal_habit_256 100000 1

# Full test (100k steps)
./fractal_habit_256 100000 1 > test_256.log 2>&1

# Check power usage
watch -n 1 nvidia-smi --query-gpu=power.draw --format=csv
```

## Success Criteria
- **Power**: 40-60W sustained
- **Coherence slope**: -3.8 ± 0.2
- **Guardian survival**: > 80% after migration
- **Stability**: No crashes in 24h

## Notes
- Original 1024×1024 binaries remain untouched on Beast
- This is MVP for GTX 1050 migration
- After successful test, create 512×512 and 384×384 versions
'@

Set-Content -Path "$buildDir/README.md" -Value $readme -Encoding UTF8
Write-Host "Created README.md" -ForegroundColor Green

# Summary
Write-Host "`n=== Preparation Complete ===" -ForegroundColor Green
Write-Host "Directory: $buildDir" -ForegroundColor Cyan
Write-Host "Contents:" -ForegroundColor Yellow
Get-ChildItem $buildDir -Recurse | ForEach-Object {
    $indent = "  " * ($_.FullName.Split('\').Length - $buildDir.Split('\').Length)
    Write-Host "$indent$($_.Name)" -ForegroundColor Gray
}

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Copy $buildDir to the-craw" -ForegroundColor Gray
Write-Host "2. Run ./build_256.sh on the-craw" -ForegroundColor Gray
Write-Host "3. Test 256×256 with 12 guardians" -ForegroundColor Gray
Write-Host "4. Report results" -ForegroundColor Gray

Write-Host "`nReady for the-craw compilation!" -ForegroundColor Green