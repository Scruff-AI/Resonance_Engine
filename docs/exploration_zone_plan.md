# Exploration Zone Plan (±5% Variation)

## Core Insight:
**Don't assume linear scaling.** Create exploration zones around each parameter.

## Grid Sizes to Explore:
1. **1024×1024** (baseline)
2. **896×896** (12.5% reduction - showed stability)
3. **768×768** (25% reduction - showed turbulence at 460W, coherence at 150W)
4. **640×640** (37.5% reduction - unknown)
5. **512×512** (50% reduction - unknown)

## For EACH Grid Size, Test VARIATIONS:

### Variation 1: Guardian Threshold (±5%)
- **Base**: RHO_THRESH = 1.01 (original)
- **+5%**: RHO_THRESH = 1.0605 (easier guardian birth)
- **-5%**: RHO_THRESH = 0.9595 (harder guardian birth)

### Variation 2: Power Cap Exploration
- **150W** (current metabolic constraint)
- **120W** (tighter constraint)
- **180W** (looser constraint)
- **Full power** (no cap - baseline)

### Variation 3: Timescale Variation
- **Short runs**: 50k steps (quick diagnostic)
- **Medium runs**: 200k steps (stability test)
- **Long runs**: 1M steps (evolution test)

## What We'll Learn:

### 1. Non-linear Response Surfaces
Map how system responds to **small parameter changes** at each grid size.

### 2. Stability Boundaries
Find where **small changes cause big effects** (phase transitions).

### 3. Emergent Scaling Laws
Discover **actual relationships** between power, guardians, grid size.

## Immediate Next Test:

### Test 640×640 with VARIATIONS:
1. **640×640 at 150W** (baseline cramped)
2. **640×640 at 120W** (tighter constraint)
3. **640×640 at 180W** (looser constraint)

### Monitor:
- **Power draw** (does it stay at cap?)
- **Spectral slope** (coherence vs noise)
- **Guardian dynamics** (if we can monitor them)

## The "Neat" Part:
We're not just compressing - we're **mapping the parameter space** to find **resilient operating points** that survive migration.

## Time Estimate:
- Each variation: 2-3 minutes
- 3 variations × 5 grid sizes = 15-45 minutes
- Plus analysis time

## Key Question:
**Where are the "sweet spots" that work across multiple constraints?**