# URGENT FIX REQUIRED: 1024x1024 Grid NaN Issue

**Status:** 1024x1024 daemon running but producing NaN for all LBM metrics

**Problem:**
- Grid size: 1024 (confirmed working)
- Power draw: ~56W (normal)
- Cycle count: incrementing (5177+)
- **Coherence: NaN**
- **H64: NaN** 
- **H32: NaN**

**Likely Causes:**
1. Distribution function initialization bug (d_w constant array read from host)
2. Metric computation division by zero or uninitialized memory
3. 1024x1024 scaling issue in wave functions

**File:** `D:\fractal-brain\beast-build\lbm_1024x1024.cu`

**Required Fix:**
1. Fix host-side initialization (cannot read __constant__ d_w from host)
2. Add NaN checks in compute_metrics_1024()
3. Verify 1024 scaling in khra_gixx_1024() wave functions
4. Test with smaller grid first (verify logic, then scale)

**Test:** After fix, coherence should read ~14-15, H64 ~6-8, H32 ~0.01-0.1

**Priority:** HIGH — blocks 1024x1024 Granite state testing
