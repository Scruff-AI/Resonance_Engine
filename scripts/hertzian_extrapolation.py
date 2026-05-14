#!/usr/bin/env python3
"""
hertzian_extrapolation.py
=========================

Project per-element lattice frequencies onto the electromagnetic spectrum.

Background
----------
The Resonance Engine fractal echo (papers/fractal-echo-analysis.txt §2.3)
exposes a measured harmonic comb in lattice time units:

    f0 = 0.6031 Hz_lattice  (fundamental, from modulation.log)
    harmonics: 0.6031, 1.2076, 1.8094, 2.4125, 3.0157  (5 integer harmonics)

The LBM bridge formula (papers/harmonic-duality-em-spectrum.md §3) is:

    f_phys = (f_lattice * c_s) / dx

with c_s = 1/sqrt(3) (lattice speed of sound) and dx the physical cell size.
Equivalently we can absorb the (c_s / dx) factor into a single scale constant
kappa, calibrated against one well-measured atomic anchor.

Per-element lattice frequency is computed via a chosen mapping:
  --mapping period : f_lat(Z) = f0 * Period(Z)        (period as harmonic number)
  --mapping mode   : f_lat(Z) = f0 * HarmonicMode(Z)  (mode count from the CSV)
  --mapping phi    : f_lat(Z) = f0 * phi^((A-A0)/scale)  (asymmetry as phi ladder)

The script:
  1. Reads data/lattice-periodic-table.csv.
  2. Computes f_lat(Z) for every element.
  3. Calibrates kappa using the chosen --anchor.
  4. Emits a CSV with f_phys, wavelength, EM band, nearest known line, residual.
  5. Prints a short summary table to stdout.

Usage
-----
    python scripts/hertzian_extrapolation.py --anchor h-lyman-alpha
    python scripts/hertzian_extrapolation.py --anchor cu-kalpha --mapping mode
    python scripts/hertzian_extrapolation.py --anchor custom \
        --custom-z 1 --custom-freq 2.466e15 --out my_table.csv

No external dependencies; stdlib only. numpy is in requirements.txt but
deliberately not used here to keep this script trivially portable.
"""

from __future__ import annotations

import argparse
import csv
import math
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Physical constants and measured lattice values
# ---------------------------------------------------------------------------

C_LIGHT = 2.99792458e8         # m/s
C_S_LATTICE = 1.0 / math.sqrt(3)  # lattice speed of sound (D2Q9)
H_PLANCK = 6.62607015e-34      # J s
E_CHARGE = 1.602176634e-19     # C
EV_TO_HZ = E_CHARGE / H_PLANCK # 2.4180e14 Hz per eV
PHI = (1.0 + math.sqrt(5.0)) / 2.0

# Fractal echo measurement (papers/fractal-echo-analysis.txt §2.3)
F0_LATTICE = 0.6031            # Hz_lattice, fundamental
HARMONIC_COMB = [F0_LATTICE * n for n in (1, 2, 3, 4, 5)]

# ---------------------------------------------------------------------------
# Anchor catalog: (Z, friendly name, frequency in Hz)
# Used to calibrate the scale factor kappa = f_anchor / f_lat(Z_anchor).
# ---------------------------------------------------------------------------

ANCHORS = {
    "h-21cm":         (1,  "H 21-cm hyperfine line",      1.420405751768e9),
    "h-lyman-alpha":  (1,  "H Lyman-alpha (n=2 -> n=1)",  2.4660718e15),
    "h-balmer-alpha": (1,  "H Balmer-alpha (n=3 -> n=2)", 4.5680000e14),
    "h-rydberg":      (1,  "H Rydberg / ionization",      3.2898419603e15),
    "cmb-peak":       (1,  "CMB blackbody peak (160 GHz)",1.60e11),
    "cu-kalpha":      (29, "Cu K-alpha",                  1.9395e18),
    "mo-kalpha":      (42, "Mo K-alpha",                  4.2305e18),
    "ag-kalpha":      (47, "Ag K-alpha",                  5.4256e18),
    "au-kalpha":      (79, "Au K-alpha",                  1.6857e19),
    "fe-kalpha":      (26, "Fe K-alpha",                  1.5414e18),
}

# ---------------------------------------------------------------------------
# Catalog of known atomic / EM lines for residual scoring (nearest-match).
# Frequencies in Hz. Each entry: (name, freq, optional_Z_hint).
# ---------------------------------------------------------------------------

KNOWN_LINES = [
    # Hydrogen lines
    ("H 21-cm hyperfine",          1.420405751768e9,  1),
    ("H Balmer-alpha",             4.5680e14,         1),
    ("H Balmer-beta",              6.1655e14,         1),
    ("H Lyman-alpha",              2.4661e15,         1),
    ("H Lyman-beta",               2.9226e15,         1),
    ("H Lyman-gamma",              3.0826e15,         1),
    ("H Rydberg ionization",       3.2898e15,         1),
    # CMB / cosmology
    ("CMB blackbody peak",         1.60e11,           None),
    # Semiconductor band gaps (Hz from eV)
    ("Ge band gap (0.67 eV)",      0.67  * EV_TO_HZ,  32),
    ("Si band gap (1.12 eV)",      1.12  * EV_TO_HZ,  14),
    ("GaAs band gap (1.42 eV)",    1.42  * EV_TO_HZ,  31),
    ("Diamond band gap (5.47 eV)", 5.47  * EV_TO_HZ,  6),
    # Visible light reference
    ("Green light (550 nm)",       C_LIGHT / 550e-9,  None),
    # K-alpha X-ray emissions
    ("Al K-alpha",                 1.4867e3 * EV_TO_HZ, 13),
    ("Fe K-alpha",                 1.5414e18,         26),
    ("Cu K-alpha",                 1.9395e18,         29),
    ("Mo K-alpha",                 4.2305e18,         42),
    ("Ag K-alpha",                 5.4256e18,         47),
    ("W K-alpha",                  1.6717e19,         74),
    ("Au K-alpha",                 1.6857e19,         79),
    ("U K-alpha",                  2.5160e19,         92),
    # Particle physics rest masses (E = mc^2; expressed as freq)
    ("Electron rest mass",         0.511e6  * EV_TO_HZ, None),
    ("Pion rest mass",             135e6    * EV_TO_HZ, None),
    ("Proton rest mass",           938.3e6  * EV_TO_HZ, None),
]


def em_band(freq_hz: float) -> str:
    """Classify an electromagnetic frequency into a band name."""
    if freq_hz <= 0:
        return "invalid"
    if freq_hz < 3e3:        return "ELF/SLF/ULF"
    if freq_hz < 3e9:        return "radio"
    if freq_hz < 3e11:       return "microwave"
    if freq_hz < 4.3e14:     return "infrared"
    if freq_hz < 7.5e14:     return "visible"
    if freq_hz < 3e16:       return "ultraviolet"
    if freq_hz < 3e19:       return "X-ray"
    return "gamma"


def nearest_known_line(freq_hz: float, z_hint: int | None = None):
    """
    Return (name, freq, residual_pct) for the catalog entry closest in
    log-frequency. If z_hint matches a catalog entry's Z, it gets a small
    preference bonus.
    """
    if freq_hz <= 0:
        return ("invalid", 0.0, float("inf"))
    log_f = math.log10(freq_hz)
    best = None
    best_score = float("inf")
    for name, f, z in KNOWN_LINES:
        if f <= 0:
            continue
        dist = abs(math.log10(f) - log_f)
        # Small bonus for matching Z, so Z-specific lines win ties.
        if z_hint is not None and z is not None and z == z_hint:
            dist *= 0.5
        if dist < best_score:
            best_score = dist
            best = (name, f)
    if best is None:
        return ("none", 0.0, float("inf"))
    name, f = best
    residual_pct = 100.0 * (freq_hz - f) / f
    return (name, f, residual_pct)


# ---------------------------------------------------------------------------
# Mapping functions: lattice frequency for a given element row
# ---------------------------------------------------------------------------

def f_lattice_period(row: dict) -> float:
    """Period n -> harmonic n of the fundamental."""
    return F0_LATTICE * int(row["Period"])


def f_lattice_mode(row: dict) -> float:
    """HarmonicMode column directly (= Z in current CSV)."""
    return F0_LATTICE * int(row["HarmonicMode"])


def f_lattice_phi(row: dict, a0: float = 13.2, scale: float = 0.3) -> float:
    """
    Phi-harmonic ladder. The 'scale' parameter sets how much asymmetry
    change corresponds to one phi step. Default 0.3 was picked so that the
    full 13.2 -> 16.2 range spans ~10 phi steps.
    """
    a = float(row["AsymmetryValue"])
    k = (a - a0) / scale
    return F0_LATTICE * (PHI ** k)


MAPPINGS = {
    "period": f_lattice_period,
    "mode":   f_lattice_mode,
    "phi":    f_lattice_phi,
}


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

def load_table(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        rows = list(reader)
    if not rows:
        raise SystemExit(f"No rows read from {path}")
    return rows


def compute(rows: list[dict], mapping: str, anchor_key: str,
            custom_z: int | None, custom_freq: float | None,
            include_sqrt3: bool) -> tuple[list[dict], dict]:
    """
    Returns (output_rows, calibration_info).
    """
    mapper = MAPPINGS[mapping]

    # Lattice frequencies first.
    lat = {int(r["AtomicNumber"]): mapper(r) for r in rows}

    # Resolve anchor.
    if anchor_key == "custom":
        if custom_z is None or custom_freq is None:
            raise SystemExit("--anchor custom requires --custom-z and --custom-freq")
        a_z, a_name, a_freq = custom_z, f"custom (Z={custom_z})", float(custom_freq)
    else:
        if anchor_key not in ANCHORS:
            raise SystemExit(f"Unknown anchor '{anchor_key}'. Options: "
                             f"{', '.join(sorted(ANCHORS))} or 'custom'.")
        a_z, a_name, a_freq = ANCHORS[anchor_key]

    if a_z not in lat:
        raise SystemExit(f"Anchor Z={a_z} not present in periodic table CSV.")

    f_lat_anchor = lat[a_z]
    if f_lat_anchor <= 0:
        raise SystemExit(f"Anchor lattice frequency is non-positive: {f_lat_anchor}")

    # kappa carries c_s and 1/dx implicitly. Optional explicit sqrt(3) factor
    # if you want to honour the paper's c_s = 1/sqrt(3) form verbatim.
    kappa = a_freq / f_lat_anchor
    if include_sqrt3:
        # Already absorbed; the flag is informational here.
        pass

    implied_dx = (C_LIGHT * (C_S_LATTICE if include_sqrt3 else 1.0)) / kappa

    out = []
    for r in rows:
        z = int(r["AtomicNumber"])
        f_lat = lat[z]
        f_phys = kappa * f_lat
        wavelength = C_LIGHT / f_phys if f_phys > 0 else float("inf")
        band = em_band(f_phys)
        line_name, line_freq, line_resid = nearest_known_line(f_phys, z_hint=z)
        out.append({
            "AtomicNumber": z,
            "Symbol": r["Symbol"],
            "Element": r["Element"],
            "Period": int(r["Period"]),
            "AsymmetryValue": float(r["AsymmetryValue"]),
            "HarmonicMode": int(r["HarmonicMode"]),
            "f_lattice_Hz": f_lat,
            "f_phys_Hz": f_phys,
            "wavelength_m": wavelength,
            "em_band": band,
            "nearest_line": line_name,
            "nearest_line_Hz": line_freq,
            "residual_pct": line_resid,
            "Stability": r["Stability"],
        })

    calib = {
        "mapping": mapping,
        "anchor_key": anchor_key,
        "anchor_name": a_name,
        "anchor_Z": a_z,
        "anchor_freq_Hz": a_freq,
        "f_lattice_at_anchor": f_lat_anchor,
        "kappa": kappa,
        "implied_dx_m": implied_dx,
        "include_sqrt3": include_sqrt3,
    }
    return out, calib


def write_output_csv(rows: list[dict], path: Path) -> None:
    cols = ["AtomicNumber", "Symbol", "Element", "Period", "AsymmetryValue",
            "HarmonicMode", "f_lattice_Hz", "f_phys_Hz", "wavelength_m",
            "em_band", "nearest_line", "nearest_line_Hz", "residual_pct",
            "Stability"]
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        for r in rows:
            w.writerow(r)


def print_summary(rows: list[dict], calib: dict, n_show: int = 12) -> None:
    print()
    print("=" * 78)
    print("HERTZIAN EXTRAPOLATION SUMMARY")
    print("=" * 78)
    print(f"  Mapping            : {calib['mapping']}")
    print(f"  Anchor             : {calib['anchor_key']}  ({calib['anchor_name']})")
    print(f"  Anchor Z           : {calib['anchor_Z']}")
    print(f"  Anchor f_phys      : {calib['anchor_freq_Hz']:.6e} Hz")
    print(f"  f_lat at anchor    : {calib['f_lattice_at_anchor']:.6f} Hz_lat")
    print(f"  kappa              : {calib['kappa']:.6e} Hz_phys / Hz_lat")
    print(f"  implied dx         : {calib['implied_dx_m']:.6e} m"
          f"  (sqrt(3) {'on' if calib['include_sqrt3'] else 'off'})")
    print()

    # Band distribution
    band_counts: dict[str, int] = {}
    for r in rows:
        band_counts[r["em_band"]] = band_counts.get(r["em_band"], 0) + 1
    band_order = ["ELF/SLF/ULF", "radio", "microwave", "infrared",
                  "visible", "ultraviolet", "X-ray", "gamma"]
    print("  EM band distribution:")
    for b in band_order:
        if b in band_counts:
            print(f"    {b:<14s} {band_counts[b]:>4d} elements")
    print()

    # Anchor row + 6 elements either side + a few highlights
    rows_by_z = {r["AtomicNumber"]: r for r in rows}
    z_anchor = calib["anchor_Z"]
    sample_zs = sorted(set([1, 2, 6, 14, 26, 29, 47, 74, 79, 82, 92, 118,
                            z_anchor, z_anchor - 1, z_anchor + 1]))
    sample_zs = [z for z in sample_zs if z in rows_by_z][:n_show]

    print(f"  Sample of {len(sample_zs)} elements (anchor row marked '*'):")
    print(f"    {'Z':>3s}  {'Sym':<3s}  {'P':>1s}  {'f_phys (Hz)':>14s}  "
          f"{'lambda (m)':>12s}  {'band':<11s}  nearest line")
    for z in sample_zs:
        r = rows_by_z[z]
        mark = "*" if z == z_anchor else " "
        print(f"  {mark} {r['AtomicNumber']:>3d}  {r['Symbol']:<3s}  "
              f"{r['Period']:>1d}  {r['f_phys_Hz']:>14.4e}  "
              f"{r['wavelength_m']:>12.4e}  {r['em_band']:<11s}  "
              f"{r['nearest_line']} ({r['residual_pct']:+.1f}%)")
    print("=" * 78)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Per-element Hz extrapolation from the lattice fractal echo.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__)
    p.add_argument("--csv-in",
                   default=str(Path(__file__).resolve().parent.parent
                               / "data" / "lattice-periodic-table.csv"),
                   help="Path to lattice-periodic-table.csv "
                        "(default: ../data/lattice-periodic-table.csv)")
    p.add_argument("--out", "--csv-out",
                   default=None,
                   help="Output CSV path (default: data/hertzian-extrapolation-"
                        "<mapping>-<anchor>.csv)")
    p.add_argument("--mapping", choices=list(MAPPINGS), default="period",
                   help="Lattice frequency mapping (default: period)")
    p.add_argument("--anchor", default="h-lyman-alpha",
                   help=f"Calibration anchor. Options: "
                        f"{', '.join(sorted(ANCHORS))}, or 'custom'.")
    p.add_argument("--custom-z", type=int, default=None,
                   help="Atomic number for custom anchor")
    p.add_argument("--custom-freq", type=float, default=None,
                   help="Frequency in Hz for custom anchor")
    p.add_argument("--include-sqrt3", action="store_true",
                   help="Honour c_s = 1/sqrt(3) explicitly when computing "
                        "implied dx. Does not change kappa-based predictions.")
    p.add_argument("--quiet", action="store_true",
                   help="Suppress the stdout summary table")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    csv_in = Path(args.csv_in)
    if not csv_in.exists():
        print(f"ERROR: input CSV not found: {csv_in}", file=sys.stderr)
        return 2

    rows = load_table(csv_in)
    out_rows, calib = compute(rows, args.mapping, args.anchor,
                               args.custom_z, args.custom_freq,
                               args.include_sqrt3)

    if args.out is None:
        default_dir = csv_in.parent
        out_path = default_dir / f"hertzian-extrapolation-{args.mapping}-{args.anchor}.csv"
    else:
        out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    write_output_csv(out_rows, out_path)

    if not args.quiet:
        print_summary(out_rows, calib)
        print(f"  Wrote: {out_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
