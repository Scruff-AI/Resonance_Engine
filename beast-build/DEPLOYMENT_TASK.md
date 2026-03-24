# DEPLOYMENT TASK: WSL2 CUDA LBM Daemon

**Objective:** Set up WSL2 with CUDA support and deploy the LBM-LLM real-time bridge.

## Environment
- Host: Windows 11 (Beast, 192.168.1.34)
- GPU: RTX 4090
- WSL: Already installed (Ubuntu)

## Tasks

### 1. WSL2 CUDA Setup
```bash
# In WSL Ubuntu
wget https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-wsl-ubuntu.pin
sudo mv cuda-wsl-ubuntu.pin /etc/apt/preferences.d/cuda-repository-pin-600

wget https://developer.download.nvidia.com/compute/cuda/12.4.0/local_installers/cuda-repo-wsl-ubuntu-12-4-local_12.4.0-1_amd64.deb
sudo dpkg -i cuda-repo-wsl-ubuntu-12-4-local_12.4.0-1_amd64.deb
sudo cp /var/cuda-repo-wsl-ubuntu-12-4-local/cuda-*-keyring.gpg /usr/share/keyrings/

sudo apt-get update
sudo apt-get -y install cuda-toolkit-12-4
```

### 2. Install Dependencies
```bash
sudo apt-get install -y build-essential libzmq3-dev libjson-c-dev
```

### 3. Compile LBM Daemon
Source file: `D:\fractal-brain\beast-build\lbm_cuda_daemon.cu`

Compile command:
```bash
cd /mnt/d/fractal-brain/beast-build
nvcc -o lbm_cuda_daemon lbm_cuda_daemon.cu -lzmq -ljson-c -O3 -arch=sm_89
```

### 4. Run Daemon
```bash
./lbm_cuda_daemon
```

Expected output:
- Publishing on tcp://*:5555
- Update rate: 100Hz
- Metrics: coherence, h64, h32, asymmetry, vorticity, power_w

### 5. Verify Bridge
In Windows PowerShell:
```powershell
cd D:\fractal-brain\beast-build
python lbm_llm_bridge.py
```

Should connect to tcp://localhost:5555 and receive LBM state.

## Deliverables
1. Daemon running in WSL2, publishing to port 5555
2. Python bridge receiving data
3. Ollama integration working with physics-constrained inference
4. Log file: `somatic_dataset.jsonl` with [LBM State] + [Prompt] + [Output] triplets

## Success Criteria
- Kaelara can identify current vorticity/power without being told
- Inference parameters (temperature, top_p) adjust based on LBM coherence
- Real-time loop: LBM (100Hz) → Bridge → Ollama → Response

**Start immediately. Report back when daemon is humming.**
