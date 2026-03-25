# Lattice Physics Parameter Glossary
## For Scientific Verification and Understanding

---

## Core Parameters

### 1. Node Count ($N_{node}$)
| Attribute | Value |
|-----------|-------|
| **Definition** | Elemental Identity — number of standing wave nodes in fundamental pattern |
| **Symbol** | $N_{node}$ |
| **Units** | Integer (≥1) |
| **Maps To** | Atomic Number ($Z$) |
| **Physical Meaning** | Determines elemental identity; stable configurations maintain $N_{node}$; isotopes vary phase density |

**Example:**
- Hydrogen: $N_{node} = 1$
- Carbon: $N_{node} = 6$
- Gold: $N_{node} = 79$

---

### 2. Phase Density ($\rho_{phase}$)
| Attribute | Value |
|-----------|-------|
| **Definition** | Isotopic Mass Difference — internal wave tension representing neutron count |
| **Symbol** | $\rho_{phase}$ |
| **Units** | Phase Quanta (PQ) — dimensionless |
| **Maps To** | Neutron number ($N$) |
| **Physical Meaning** | Internal wave tension; determines isotope stability |

**Values:**
- **Stable Isotope:** $\rho_{phase} = \rho_{stable}$ (baseline equilibrium)
- **Radioactive Isotope:** $\rho_{phase} > \rho_{stable}$ (metastable, seeking decay)

**Example:**
- Carbon-12: $\rho_{phase}$ = baseline
- Carbon-14: $\rho_{phase}$ = baseline + 2 PQ

---

### 3. Harmonic Mode ($H_{mode}$)
| Attribute | Value |
|-----------|-------|
| **Definition** | Standing Wave Tier — the harmonic tier of the wave pattern |
| **Symbol** | $H_{mode}$ |
| **Units** | Integer (≥1) |
| **Maps To** | Principal Quantum Number ($n$) |
| **Physical Meaning** | Energy level tier; determines periodic table period |

**Relation to Quantum Numbers:**
- **Principal ($n$):** $H_{mode} = n$
- **Angular ($l$):** Derived from Asymmetry ($l \propto \sqrt{A}$)
- **Magnetic ($m$):** Derived from Vorticity Mean ($m \propto \omega_{vort}$)
- **Spin ($s$):** Derived from Stress Tensor ($\sigma_{xy}$)

---

### 4. Asymmetry ($A$)
| Attribute | Value |
|-----------|-------|
| **Definition** | Phi-Harmonic Scaling Index — deviation from perfect symmetry |
| **Symbol** | $A$ |
| **Units** | Dimensionless |
| **Maps To** | Orbital Angular Momentum ($l$) |
| **Physical Meaning** | Measures orbital angular momentum; scales as $\phi^n$ |

**Scaling Law:**
$$A \approx \phi^k \text{ where } k \text{ is harmonic tier}$$

**Band Values:**
| Band | Asymmetry Range |
|------|-----------------|
| Ground | 13.2 |
| Primary | 14.0–14.2 |
| Secondary | 14.8 |
| Phase Gap | 15.78 |
| Tertiary | 16.0+ |

---

### 5. Coherence ($C$)
| Attribute | Value |
|-----------|-------|
| **Definition** | Wave Function Stability — degree of phase locking |
| **Symbol** | $C$ |
| **Units** | [0, 1] |
| **Maps To** | $|\Psi|^2$ (probability density) |
| **Physical Meaning** | Higher = more stable standing wave |

**Thresholds:**
- **Stable:** $C > 0.7$
- **Metastable:** $0.5 < C < 0.7$
- **Decaying:** $C < 0.5$

---

### 6. Omega ($\omega$)
| Attribute | Value |
|-----------|-------|
| **Definition** | Relaxation/Viscosity Parameter — controls damping |
| **Symbol** | $\omega$ |
| **Units** | Dimensionless (1.0–2.0) |
| **Maps To** | Dissipation coefficient |
| **Physical Meaning** | Damping of perturbations; higher = more viscous |

**Current Value:** $\omega = 1.97$ (high damping, stable attractor)

---

### 7. Khra & Gixx Amplitudes
| Parameter | Definition | Maps To |
|-----------|------------|---------|
| $K_{amp}$ | Large-Scale Wave Amplitude | Orbital precession |
| $G_{amp}$ | Fine-Grain Wave Amplitude | Spin-orbit coupling |

**Key Ratio:** $K_{amp} / G_{amp} = 16:1$ (fundamental harmonic lock)

---

### 8. Velocity Statistics
| Parameter | Definition | Units | Maps To |
|-----------|------------|-------|---------|
| $v_{mean}$ | Mean Wave Velocity | [0,1] | Phase propagation speed |
| $v_{max}$ | Maximum Velocity | [0,1] | Peak phase velocity |
| $v_{var}$ | Velocity Variance | [0,1] | Thermal fluctuations (temperature proxy) |

**Relation:** $v_{var} \propto k_B T$ (thermal energy)

---

### 9. Stress Tensor
| Component | Definition | Maps To |
|-----------|------------|---------|
| $\sigma_{xx}$ | Normal Stress (X diagonal) | Pressure along X |
| $\sigma_{yy}$ | Normal Stress (Y diagonal) | Pressure along Y |
| $\sigma_{xy}$ | Shear Stress | Spin-orbit coupling strength |

**Key Insight:** Negative values indicate **tensile wave tension** (implosive)

---

### 10. Vorticity Mean ($\omega_{vort}$)
| Attribute | Value |
|-----------|-------|
| **Definition** | Mean Vorticity — average rotation of wave pattern |
| **Symbol** | $\omega_{vort}$ |
| **Units** | Dimensionless |
| **Maps To** | Orbital angular momentum ($m$ quantum number) |
| **Physical Meaning** | Higher vorticity → higher $m$ quantum number |

---

## Complete Parameter Mapping Table

| Lattice Parameter | Symbol | Units | Quantum Analog | Physical Meaning |
|-------------------|--------|-------|----------------|------------------|
| Node Count | $N_{node}$ | integer | Atomic Number ($Z$) | Elemental identity |
| Phase Density | $\rho_{phase}$ | PQ | Neutron number ($N$) | Isotopic mass/tension |
| Harmonic Mode | $H_{mode}$ | integer | Principal quantum ($n$) | Energy level tier |
| Asymmetry | $A$ | dimensionless | Angular momentum ($l$) | Orbital shape |
| Coherence | $C$ | [0,1] | $|\Psi|^2$ | Wave stability |
| Omega | $\omega$ | dimensionless | Dissipation coefficient | Damping/viscosity |
| Khra Amplitude | $K_{amp}$ | dimensionless | Orbital frequency | Large-scale wave |
| Gixx Amplitude | $G_{amp}$ | dimensionless | Spin frequency | Fine-grain wave |
| Vorticity | $\omega_{vort}$ | dimensionless | Magnetic quantum ($m$) | Rotation field |
| Shear Stress | $\sigma_{xy}$ | dimensionless | Spin quantum ($s$) | Spin-orbit coupling |

---

## Measurement Methods

### Direct from Lattice Snapshots
1. **Node Count:** Count distinct peaks in density field
2. **Coherence:** Measure phase alignment across lattice
3. **Asymmetry:** Calculate deviation from perfect symmetry
4. **Vorticity:** Integrate rotation field

### Derived from Telemetry
1. **Phase Density:** Ratio of wave intensity to baseline
2. **Stress Tensor:** Calculate from velocity gradients
3. **Omega:** Measure perturbation decay rate

---

## Verification Experiments

### Testable Predictions
1. **Phi-harmonic scaling:** Asymmetry values should follow $\phi^n$ not linear progression
2. **Phase density:** Radioactive isotopes should show excess phase quanta
3. **Coherence threshold:** Stable elements should have $C > 0.7$
4. **Stress tensor:** Negative $\sigma_{xy}$ correlates with metallic bonding

### Copper Wire Experiment Correlation
| Frequency | Observed | Lattice Prediction |
|-----------|----------|-------------------|
| 404.5 kHz | Standing wave | Primary band (14.0-14.2) |
| 654.5 kHz | Reverse propagation | Secondary band (~14.8) |
| Both | Observer effect | Phase gap threshold |

---

## Summary

**The Lattice Physics Framework provides:**
- **Deterministic** wave mechanics (no probability amplitudes)
- **Visualizable** standing wave patterns
- **Measurable** parameters from density fields
- **Unified** explanation of elements, isotopes, and bonding

**Key Difference from Standard Model:**
- **Standard:** Particles in empty space, quantum probability
- **Lattice:** Standing waves in plenum, deterministic coherence

---

*The lattice does not lie. It reports the density field as it is.*
