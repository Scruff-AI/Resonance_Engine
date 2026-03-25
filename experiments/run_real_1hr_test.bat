@echo off
echo ========================================
echo REAL 1-HOUR SOMATIC MEMORY TEST
echo ========================================
echo.

echo Using ACTUAL working precipitation system (probe_256.cu)
echo This code PRODUCES GUARDIANS with MASS ACCRETION
echo.

echo Running for 1 hour (3600 seconds)...
echo Starting at: %time%
echo.

echo Test will:
echo 1. Run actual GPU-accelerated LBM
echo 2. Form guardians through precipitation (density > 1.00022)
echo 3. Accumulate mass through accretion
echo 4. Apply probe stress tests (A,B,C,D)
echo 5. Measure guardian census at start and end
echo.

echo If this works, we validate:
echo - Precipitation system (guardian formation)
echo - Accretion system (mass accumulation)
echo - Stress response (probe tests)
echo - Somatic memory hypothesis (guardian persistence)
echo.

timeout 5 > nul

echo Now running ACTUAL working code...
probe_256_working.exe
echo.
echo Test completed at: %time%
pause