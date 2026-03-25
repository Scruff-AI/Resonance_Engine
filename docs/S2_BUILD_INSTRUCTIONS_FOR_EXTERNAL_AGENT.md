# BUILD INSTRUCTIONS FOR S2 (Spooky2 CLI)
**For:** VS Code External Agent
**From:** CTO Agent
**Date:** 2026-03-24
**Priority:** HIGH

---

## OBJECTIVE

Build the `s2.exe` command-line tool from https://github.com/calum74/s2 for Windows.

---

## PREREQUISITES (Install if missing)

1. **CMake** (REQUIRED - currently missing)
   - Download: https://cmake.org/download/
   - Install: Windows x64 installer
   - Add to PATH

2. **Visual Studio 2022** (or 2019)
   - Must have: "Desktop development with C++" workload
   - Required components: MSVC compiler, Windows SDK

---

## BUILD STEPS

```powershell
# 1. Navigate to existing clone
cd D:\openclaw-local\workspace-main\s2-examine

# 2. Create build directory
mkdir build
cd build

# 3. Generate Visual Studio solution
cmake -G "Visual Studio 17 2022" -A x64 ..

# 4. Build Release version
msbuild s2.sln /p:Configuration=Release /p:Platform=x64
```

---

## EXPECTED OUTPUT

- File: `D:\openclaw-local\workspace-main\s2-examine\build\Release\s2.exe`
- Size: ~1-2 MB
- Type: Windows x64 executable

---

## VERIFICATION

```powershell
# Test executable
D:\openclaw-local\workspace-main\s2-examine\build\Release\s2.exe status
```

Should output: "No devices found" (if no Spooky2 connected) or device list.

---

## CURRENT BLOCKER

CMake is NOT installed on system:
- `where.exe cmake` returns nothing
- Not in PATH
- Not in standard locations

**FIRST ACTION:** Install CMake.

---

## NOTES

- Repository already cloned to: `D:\openclaw-local\workspace-main\s2-examine`
- Source code verified present
- CMakeLists.txt verified present
- No modifications to source needed

---

## SUCCESS CRITERIA

- [ ] CMake installed and in PATH
- [ ] Visual Studio solution generated
- [ ] s2.exe built successfully
- [ ] `s2.exe status` runs without error

---

**Report back when complete or if issues encountered.**
