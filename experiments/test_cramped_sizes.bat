@echo off
echo Testing 3 critical grid sizes with 194 guardians (cramped)...
echo ============================================================

set sizes=512 384 256

for %%s in (%sizes%) do (
    echo.
    echo === Testing %%sx%%s ===
    
    rem Create test directory
    if not exist test_%%sx%%s mkdir test_%%sx%%s
    if not exist test_%%sx%%s\build mkdir test_%%sx%%s\build
    
    rem Check if brain state exists
    if exist harmonic_brain_states\build_%%sx%%s\f_state_post_relax.bin (
        copy harmonic_brain_states\build_%%sx%%s\f_state_post_relax.bin test_%%sx%%s\build\ >nul
        echo   [OK] Brain state copied
    ) else (
        echo   [ERROR] Brain state not found for %%sx%%s
        goto :next
    )
    
    rem Run test
    echo   Running 50k steps...
    cd test_%%sx%%s
    ..\fractal_habit.exe 50000 1
    cd ..
    
    :next
)

echo.
echo ============================================================
echo All tests completed!
pause