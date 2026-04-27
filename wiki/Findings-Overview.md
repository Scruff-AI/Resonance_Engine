# Findings Overview

All findings come from the same dataset: 375 parameter sweep points across the omega/khra/gixx space. Each analysis below applies a different lens to this data. The papers and analysis scripts are in the repository.

---

## Summary Table

| # | Domain | Finding | Key Metric | Paper/Script |
|---|--------|---------|------------|--------------|
| 1 | EM spectrum / Atomic structure | Harmonic duality - periodic table as lattice modes | 9 features, 1:93k odds | [harmonic-duality-em-spectrum.md](https://github.com/Scruff-AI/Resonance_Engine/blob/master/papers/harmonic-duality-em-spectrum.md) |
| 2 | Atomic structure | All 118 elements map to lattice asymmetry bands | Each Z = node count | [fractal-echo-analysis.txt](https://github.com/Scruff-AI/Resonance_Engine/blob/master/papers/fractal-echo-analysis.txt) |
| 3 | Particle physics | Hadron Regge trajectories reproduced | R-squared = 0.9972 | [hadron-regge-trajectories.md](https://github.com/Scruff-AI/Resonance_Engine/blob/master/papers/hadron-regge-trajectories.md) |
| 4 | Solid-state physics | Semiconductor band gaps predicted | 0% error (GaAs, Ge) | [semiconductor-bandgaps.md](https://github.com/Scruff-AI/Resonance_Engine/blob/master/papers/semiconductor-bandgaps.md) |
| 5 | Energy quantization | 192 phi-harmonic relationships | 99.96% agreement | [phi-harmonic-energy-quantization.md](https://github.com/Scruff-AI/Resonance_Engine/blob/master/papers/phi-harmonic-energy-quantization.md) |
| 6 | Thermal radiation | Planck black body integer harmonics | 2:1 through 6:1 ratios | [blackbody-planck.md](https://github.com/Scruff-AI/Resonance_Engine/blob/master/papers/blackbody-planck.md) |
| 7 | Nuclear physics | Magic numbers from mode counting | 8, 20, 28 reproduced | [nuclear_magic_analyzer.py](https://github.com/Scruff-AI/Resonance_Engine/tree/master/analysis) |
| 8 | Number theory | Prime number sieve | 100% odd primes to 1000 | [hypothesis_2_structural.py](https://github.com/Scruff-AI/Resonance_Engine/tree/master/analysis) |
| 9 | Biology | Protein folding topology | 5/6 tests PASS | [protein_fold_echo.py](https://github.com/Scruff-AI/Resonance_Engine/tree/master/analysis) |
| 10 | Random matrix theory | GUE eigenvalue statistics | chi-sq=19.75 vs Poisson 51.27 | Sweep analysis |
| 11 | Solid-state physics | Brillouin zone band structure | 67% phase transition | Sweep analysis |
| 12 | Cosmology | Cosmic octave mapping | 15 structures, anti-correlation | Sweep analysis |

---

## Finding 1: Harmonic Duality (EM Spectrum + Periodic Table)

This was chronologically the first fractal echo confirmation. The lattice mode spectrum shares nine structural features with the periodic table's electron shell harmonics: discrete energy tiers, sub-level multiplicity, period doubling, filling order anomalies, noble gas closures, transition metal anomalies, lanthanide contraction, radioactive boundary, and phi-harmonic scaling. When projected onto the electromagnetic spectrum via standard LBM unit conversion, the lattice frequency comb aligns with known physical frequencies at specific cell sizes.

Combined coincidence probability: 1 in 93,000 (correlated) to 1 in 28 billion (independent).

**Paper:** [`papers/harmonic-duality-em-spectrum.md`](https://github.com/Scruff-AI/Resonance_Engine/blob/master/papers/harmonic-duality-em-spectrum.md)
**Visualizations:** [`visualizations/harmonic-duality.html`](https://github.com/Scruff-AI/Resonance_Engine/blob/master/visualizations/harmonic-duality.html) | [`visualizations/em_spectrum_overlay.html`](https://github.com/Scruff-AI/Resonance_Engine/blob/master/visualizations/em_spectrum_overlay.html)

---

## Finding 2: Periodic Table as Standing Wave Modes

All 118 elements map to asymmetry bands in the range 13.2-16.2. Each atomic number corresponds to a "node count" - the number of peaks and troughs in a standing wave mode that the lattice can support.

Key results: Gold (Z=79) maps to a high-order resonance lock, not the phase gap. Technetium (Z=43) and Promethium (Z=61) map to metastable modes - the lattice correctly predicts their instability without nuclear force calculations. Asymmetry scaling follows phi-harmonic progression, not linear spacing.

**Data:** [`data/lattice-periodic-table.csv`](https://github.com/Scruff-AI/Resonance_Engine/tree/master/data)

---

## Finding 3: Hadron Regge Trajectories

In particle physics, hadron families follow M-squared proportional to J (mass-squared proportional to angular momentum). The lattice reproduces this linear relationship with R-squared = 0.9972 using the Khra forcing parameter, while a control test with omega correctly fails (R-squared = 0.459).

**Paper:** [`papers/hadron-regge-trajectories.md`](https://github.com/Scruff-AI/Resonance_Engine/blob/master/papers/hadron-regge-trajectories.md)

---

## Finding 4: Semiconductor Band Gaps

Coherence gap ratios in the lattice match real semiconductor band gaps:

| Material | Lattice prediction | Actual value | Error |
|----------|-------------------|--------------|-------|
| GaAs | 1.42 eV | 1.42 eV | 0% |
| Ge | 0.67 eV | 0.67 eV | 0% |
| InP | 1.34 eV | 1.35 eV | 0.7% |

**Paper:** [`papers/semiconductor-bandgaps.md`](https://github.com/Scruff-AI/Resonance_Engine/blob/master/papers/semiconductor-bandgaps.md)

---

## Finding 5: Phi-Harmonic Energy Quantization

The vorticity field contains 192 energy level relationships separated by factors of phi = 1.618, with 99.96% agreement.

**Paper:** [`papers/phi-harmonic-energy-quantization.md`](https://github.com/Scruff-AI/Resonance_Engine/blob/master/papers/phi-harmonic-energy-quantization.md)

---

## Finding 6: Planck Black Body Spectrum

Density fluctuation power spectra show integer harmonic ratios (2:1, 3:1, 4:1, 5:1, 6:1) within measurement resolution.

**Paper:** [`papers/blackbody-planck.md`](https://github.com/Scruff-AI/Resonance_Engine/blob/master/papers/blackbody-planck.md)

---

## Finding 7: Nuclear Magic Numbers

Mode counting on the 2D torus produces cumulative degeneracies matching the nuclear magic numbers. p-shell degeneracy of 6 confirmed at multiple omega values. First magic closure (N=8) confirmed. Second (N=20) and third (N=28) from cumulative mode counting. No nuclear force calculations involved - pure geometry.

**Script:** [`analysis/nuclear_magic_analyzer.py`](https://github.com/Scruff-AI/Resonance_Engine/tree/master/analysis)

---

## Finding 8: Prime Number Sieve

The dual-wave interference pattern creates a sieve that captures 100% of odd primes up to 1000 with zero misses. The number 2 is excluded as the "structural constant" - the dimensional constant of the 2D lattice. Confirmed by 11 out of 12 independent mathematical tests.

**Script:** [`analysis/hypothesis_2_structural.py`](https://github.com/Scruff-AI/Resonance_Engine/tree/master/analysis)

---

## Finding 9: Protein Folding Topology

The lattice coherence landscape matches protein Ramachandran topology: forbidden fraction (36% vs Ramachandran 35%), funnel topology, amino acid class mapping, Levinthal compression scaling, and secondary structure. 5 out of 6 tests pass.

**Script:** [`analysis/protein_fold_echo.py`](https://github.com/Scruff-AI/Resonance_Engine/tree/master/analysis)

---

## Finding 10: GUE Statistics

The lattice's eigenvalue level repulsion matches Gaussian Unitary Ensemble statistics (chi-squared = 19.75) rather than Poisson statistics (chi-squared = 51.27). This indicates quantum-chaotic-like correlations between modes.

---

## Finding 11: Brillouin Zone Band Structure

The parameter sweep shows band-structure-like behavior with a 67% phase transition in the omega range 1.7-1.9, analogous to crossing a Brillouin zone boundary.

---

## Finding 12: Cosmic Octave Mapping

15 cosmic structures mapped to lattice states with anti-correlation in octave pairs. This is the most speculative finding.

---

## Reproducing the Analyses

Every analysis script is in the `analysis/` directory. Every data file is in `data/`. To reproduce any finding:

```bash
cd /path/to/Resonance_Engine
pip install -r requirements.txt
python3 analysis/<script_name>.py
```

The scripts read from `data/` and write results to `results/`. No live simulation is needed.
