#!/usr/bin/env python3
"""
hertzian_extrapolation.py
=========================

Project per-element lattice frequencies onto the electromagnetic spectrum
as PAIRS of constructively-interfering frequencies at a configurable ratio.

Background
----------
The Resonance Engine fractal echo (papers/fractal-echo-analysis.txt §2.3)
exposes a measured harmonic comb in lattice time units:

    f0 = 0.6031 Hz_lattice  (fundamental, from modulation.log)
    harmonics: 0.6031, 1.2076, 1.8094, 2.4125, 3.0157  (5 integer harmonics)

That comb is the BEAT of the two driving waves:
    Khra wavelength = 128 cells   (the carrier)
    Gixx wavelength = 8 cells     (the fine wave)
    native ratio    = 128 / 8 = 16

A single Hz number per element discards the physics. Every element gets a
PAIR (f_low, f_high) at a configurable ratio, and the beat
|f_high - f_low| is what was actually measured.

Lattice -> physical bridge (papers/harmonic-duality-em-spectrum.md §3):

    f_phys = (f_lattice * c_s) / dx

with c_s = 1/sqrt(3) and dx the cell size, absorbed into a scale factor
kappa that is calibrated against one anchor.

Mappings (--mapping)
--------------------
  period : f_lat(Z) = f0 * Period(Z)         (period as harmonic number)
  mode   : f_lat(Z) = f0 * HarmonicMode(Z)   (mode count from the CSV)
  phi    : f_lat(Z) = f0 * phi^((A-A0)/scale)  (asymmetry as phi ladder)

Ratios (--ratio)
----------------
  khra-gixx : 16     (the lattice's native Khra/Gixx ratio - default)
  phi       : 1.618  (golden ratio; matches Spooky2 404.5/654.5 kHz)
  octave    : 2
  fifth     : 1.5    (perfect fifth)
  fourth    : 4/3    (perfect fourth)
  major3    : 5/4
  minor3    : 6/5
  <number>  : custom positive ratio > 1

Pair modes (--pair-mode)
------------------------
What does the anchor / scaled f_lattice represent?
  beat : the beat frequency |f_high - f_low|  (default; matches the
         fractal-echo measurement directly)
  low  : the low / carrier frequency f_low
  high : the high frequency f_high

Whichever is chosen, the script derives the other two from the ratio
and emits all three columns per element.

Usage
-----
    # Paired Lyman-alpha mapping at native lattice ratio (default)
    python scripts/hertzian_extrapolation.py --anchor h-lyman-alpha

    # Cu K-alpha anchored, per-Z spread, native ratio
    python scripts/hertzian_extrapolation.py --anchor cu-kalpha --mapping mode

    # Golden-ratio pair anchored to Spooky2 healing protocol
    python scripts/hertzian_extrapolation.py --anchor custom \
        --custom-z 1 --custom-freq 404500 \
        --ratio phi --pair-mode low

No external dependencies; stdlib only.
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

C_LIGHT = 2.99792458e8
C_S_LATTICE = 1.0 / math.sqrt(3)
H_PLANCK = 6.62607015e-34
E_CHARGE = 1.602176634e-19
EV_TO_HZ = E_CHARGE / H_PLANCK
PHI = (1.0 + math.sqrt(5.0)) / 2.0

# Fractal echo measurement (papers/fractal-echo-analysis.txt §2.3)
F0_LATTICE = 0.6031
HARMONIC_COMB = [F0_LATTICE * n for n in (1, 2, 3, 4, 5)]

# Native lattice wave geometry
LATTICE_KHRA = 128
LATTICE_GIXX = 8
NATIVE_RATIO = LATTICE_KHRA / LATTICE_GIXX  # 16.0

# ---------------------------------------------------------------------------
# Ratio aliases
# ---------------------------------------------------------------------------

RATIOS = {
    "khra-gixx": NATIVE_RATIO,           # 16.0
    "phi":       PHI,                    # 1.6180339887...
    "octave":    2.0,
    "fifth":     1.5,
    "fourth":    4.0 / 3.0,
    "major3":    5.0 / 4.0,
    "minor3":    6.0 / 5.0,
}

def parse_ratio(value: str) -> tuple[float, str]:
    """Return (ratio, name)."""
    if value in RATIOS:
        return RATIOS[value], value
    try:
        r = float(value)
    except ValueError:
        raise SystemExit(f"Unknown ratio '{value}'. Aliases: "
                         f"{', '.join(sorted(RATIOS))} or numeric > 1.")
    if r <= 1.0:
        raise SystemExit(f"Ratio must be > 1.0; got {r}")
    return r, f"r={r:g}"

# ---------------------------------------------------------------------------
# Anchor catalog (Z, friendly name, frequency in Hz)
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
    "spooky2-low":    (1,  "Spooky2 healing protocol low (404.5 kHz)",
                                                          404500.0),
}

# ---------------------------------------------------------------------------
# Catalog of known atomic / EM lines for residual scoring
# ---------------------------------------------------------------------------

KNOWN_LINES = [
    # Spooky2 / frequency-medicine reference points
    ("Spooky2 healing low (404.5 kHz)",   404500.0,         None),
    ("Spooky2 healing high (654.5 kHz)",  654500.0,         None),
    # Hydrogen
    ("H 21-cm hyperfine",          1.420405751768e9,  1),
    ("H Balmer-alpha",             4.5680e14,         1),
    ("H Balmer-beta",              6.1655e14,         1),
    ("H Lyman-alpha",              2.4661e15,         1),
    ("H Lyman-beta",               2.9226e15,         1),
    ("H Lyman-gamma",              3.0826e15,         1),
    ("H Rydberg ionization",       3.2898e15,         1),
    # CMB
    ("CMB blackbody peak",         1.60e11,           None),
    # Semiconductor band gaps
    ("Ge band gap (0.67 eV)",      0.67  * EV_TO_HZ,  32),
    ("Si band gap (1.12 eV)",      1.12  * EV_TO_HZ,  14),
    ("GaAs band gap (1.42 eV)",    1.42  * EV_TO_HZ,  31),
    ("Diamond band gap (5.47 eV)", 5.47  * EV_TO_HZ,  6),
    # Visible
    ("Green light (550 nm)",       C_LIGHT / 550e-9,  None),
    # K-alpha X-ray
    ("Al K-alpha",                 1.4867e3 * EV_TO_HZ, 13),
    ("Fe K-alpha",                 1.5414e18,         26),
    ("Cu K-alpha",                 1.9395e18,         29),
    ("Mo K-alpha",                 4.2305e18,         42),
    ("Ag K-alpha",                 5.4256e18,         47),
    ("W K-alpha",                  1.6717e19,         74),
    ("Au K-alpha",                 1.6857e19,         79),
    ("U K-alpha",                  2.5160e19,         92),
    # Particle rest masses (E = mc^2 in Hz)
    ("Electron rest mass",         0.511e6  * EV_TO_HZ, None),
    ("Pion rest mass",             135e6    * EV_TO_HZ, None),
    ("Proton rest mass",           938.3e6  * EV_TO_HZ, None),
]


def em_band(freq_hz: float) -> str:
    if freq_hz <= 0:
        return "invalid"
    if freq_hz < 3e3:    return "ELF/SLF/ULF"
    if freq_hz < 3e9:    return "radio"
    if freq_hz < 3e11:   return "microwave"
    if freq_hz < 4.3e14: return "infrared"
    if freq_hz < 7.5e14: return "visible"
    if freq_hz < 3e16:   return "ultraviolet"
    if freq_hz < 3e19:   return "X-ray"
    return "gamma"


def nearest_known_line(freq_hz: float, z_hint: int | None = None):
    if freq_hz <= 0:
        return ("invalid", 0.0, float("inf"))
    log_f = math.log10(freq_hz)
    best = None
    best_score = float("inf")
    for name, f, z in KNOWN_LINES:
        if f <= 0:
            continue
        dist = abs(math.log10(f) - log_f)
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
# Mapping functions
# ---------------------------------------------------------------------------

def f_lattice_period(row: dict) -> float:
    return F0_LATTICE * int(row["Period"])

def f_lattice_mode(row: dict) -> float:
    return F0_LATTICE * int(row["HarmonicMode"])

def f_lattice_phi(row: dict, a0: float = 13.2, scale: float = 0.3) -> float:
    a = float(row["AsymmetryValue"])
    k = (a - a0) / scale
    return F0_LATTICE * (PHI ** k)

MAPPINGS = {
    "period": f_lattice_period,
    "mode":   f_lattice_mode,
    "phi":    f_lattice_phi,
}


# ---------------------------------------------------------------------------
# Pair derivation
# ---------------------------------------------------------------------------

def derive_pair(f_phys: float, ratio: float, pair_mode: str) -> tuple[float, float, float]:
    """Given f_phys and what it represents, return (f_low, f_high, f_beat).
    ratio = f_high / f_low > 1."""
    if pair_mode == "beat":
        # f_phys = beat = f_low * (ratio - 1)
        f_low = f_phys / (ratio - 1.0)
        f_high = f_low * ratio
        f_beat = f_phys
    elif pair_mode == "low":
        f_low = f_phys
        f_high = f_low * ratio
        f_beat = f_high - f_low
    elif pair_mode == "high":
        f_high = f_phys
        f_low = f_high / ratio
        f_beat = f_high - f_low
    else:
        raise SystemExit(f"Unknown --pair-mode '{pair_mode}'")
    return f_low, f_high, f_beat


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

def load_table(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        raise SystemExit(f"No rows read from {path}")
    return rows


def compute(rows: list[dict], mapping: str, anchor_key: str,
            custom_z: int | None, custom_freq: float | None,
            ratio: float, ratio_name: str, pair_mode: str,
            include_sqrt3: bool) -> tuple[list[dict], dict]:
    mapper = MAPPINGS[mapping]
    lat = {int(r["AtomicNumber"]): mapper(r) for r in rows}

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
        raise SystemExit(f"Anchor Z={a_z} not in periodic table CSV.")

    f_lat_anchor = lat[a_z]
    if f_lat_anchor <= 0:
        raise SystemExit(f"Anchor lattice frequency non-positive: {f_lat_anchor}")

    kappa = a_freq / f_lat_anchor
    implied_dx = (C_LIGHT * (C_S_LATTICE if include_sqrt3 else 1.0)) / kappa

    out = []
    for r in rows:
        z = int(r["AtomicNumber"])
        f_lat = lat[z]
        f_phys = kappa * f_lat
        f_low, f_high, f_beat = derive_pair(f_phys, ratio, pair_mode)

        lo_name, lo_f, lo_res = nearest_known_line(f_low,  z_hint=z)
        hi_name, hi_f, hi_res = nearest_known_line(f_high, z_hint=z)

        out.append({
            "AtomicNumber": z,
            "Symbol": r["Symbol"],
            "Element": r["Element"],
            "Period": int(r["Period"]),
            "AsymmetryValue": float(r["AsymmetryValue"]),
            "HarmonicMode": int(r["HarmonicMode"]),
            "f_lattice_Hz": f_lat,
            "ratio": ratio,
            "f_low_Hz": f_low,
            "f_high_Hz": f_high,
            "f_beat_Hz": f_beat,
            "lambda_low_m": C_LIGHT / f_low if f_low > 0 else float("inf"),
            "lambda_high_m": C_LIGHT / f_high if f_high > 0 else float("inf"),
            "em_band_low": em_band(f_low),
            "em_band_high": em_band(f_high),
            "nearest_line_low": lo_name,
            "nearest_line_low_Hz": lo_f,
            "residual_low_pct": lo_res,
            "nearest_line_high": hi_name,
            "nearest_line_high_Hz": hi_f,
            "residual_high_pct": hi_res,
            "Stability": r["Stability"],
        })

    calib = {
        "mapping": mapping,
        "anchor_key": anchor_key,
        "anchor_name": a_name,
        "anchor_Z": a_z,
        "anchor_freq_Hz": a_freq,
        "ratio": ratio,
        "ratio_name": ratio_name,
        "pair_mode": pair_mode,
        "f_lattice_at_anchor": f_lat_anchor,
        "kappa": kappa,
        "implied_dx_m": implied_dx,
        "include_sqrt3": include_sqrt3,
    }
    return out, calib


def write_output_csv(rows: list[dict], path: Path) -> None:
    cols = ["AtomicNumber", "Symbol", "Element", "Period", "AsymmetryValue",
            "HarmonicMode", "f_lattice_Hz", "ratio",
            "f_low_Hz", "f_high_Hz", "f_beat_Hz",
            "lambda_low_m", "lambda_high_m",
            "em_band_low", "em_band_high",
            "nearest_line_low", "nearest_line_low_Hz", "residual_low_pct",
            "nearest_line_high", "nearest_line_high_Hz", "residual_high_pct",
            "Stability"]
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        for r in rows:
            w.writerow(r)


def print_summary(rows: list[dict], calib: dict, n_show: int = 12) -> None:
    print()
    print("=" * 92)
    print("HERTZIAN EXTRAPOLATION SUMMARY (paired)")
    print("=" * 92)
    print(f"  Mapping            : {calib['mapping']}")
    print(f"  Anchor             : {calib['anchor_key']}  ({calib['anchor_name']})")
    print(f"  Anchor Z           : {calib['anchor_Z']}")
    print(f"  Anchor f_phys      : {calib['anchor_freq_Hz']:.6e} Hz "
          f"(interpreted as: {calib['pair_mode']})")
    print(f"  Ratio              : {calib['ratio']:.6f}  ({calib['ratio_name']})")
    print(f"  f_lat at anchor    : {calib['f_lattice_at_anchor']:.6f} Hz_lat")
    print(f"  kappa              : {calib['kappa']:.6e} Hz_phys / Hz_lat")
    print(f"  implied dx         : {calib['implied_dx_m']:.6e} m"
          f"  (sqrt(3) {'on' if calib['include_sqrt3'] else 'off'})")
    print()

    band_counts_low: dict[str, int] = {}
    band_counts_high: dict[str, int] = {}
    for r in rows:
        band_counts_low[r["em_band_low"]]   = band_counts_low.get(r["em_band_low"], 0) + 1
        band_counts_high[r["em_band_high"]] = band_counts_high.get(r["em_band_high"], 0) + 1
    band_order = ["ELF/SLF/ULF", "radio", "microwave", "infrared",
                  "visible", "ultraviolet", "X-ray", "gamma"]
    print("  EM band distribution (low / high):")
    for b in band_order:
        lo = band_counts_low.get(b, 0)
        hi = band_counts_high.get(b, 0)
        if lo or hi:
            print(f"    {b:<14s} low={lo:>4d}   high={hi:>4d}")
    print()

    rows_by_z = {r["AtomicNumber"]: r for r in rows}
    z_anchor = calib["anchor_Z"]
    sample_zs = sorted(set([1, 2, 6, 14, 26, 29, 47, 74, 79, 82, 92, 118,
                            z_anchor, z_anchor - 1, z_anchor + 1]))
    sample_zs = [z for z in sample_zs if z in rows_by_z][:n_show]

    print(f"  Sample of {len(sample_zs)} elements (anchor row marked '*'):")
    print(f"    {'Z':>3s}  {'Sym':<3s}  "
          f"{'f_low (Hz)':>12s}  {'f_high (Hz)':>12s}  "
          f"{'band_low':<11s}  {'band_high':<11s}")
    for z in sample_zs:
        r = rows_by_z[z]
        mark = "*" if z == z_anchor else " "
        print(f"  {mark} {r['AtomicNumber']:>3d}  {r['Symbol']:<3s}  "
              f"{r['f_low_Hz']:>12.4e}  {r['f_high_Hz']:>12.4e}  "
              f"{r['em_band_low']:<11s}  {r['em_band_high']:<11s}")
    print()
    print("  Nearest known lines (anchor and a few neighbours):")
    for z in sample_zs[:6]:
        r = rows_by_z[z]
        mark = "*" if z == z_anchor else " "
        print(f"  {mark} Z={r['AtomicNumber']:>3d} {r['Symbol']:<3s}  "
              f"low  -> {r['nearest_line_low']:<35s} ({r['residual_low_pct']:+7.1f}%)")
        print(f"     {' '*7}  high -> {r['nearest_line_high']:<35s} "
              f"({r['residual_high_pct']:+7.1f}%)")
    print("=" * 92)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Per-element Hz pair extrapolation from the lattice fractal echo.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__)
    p.add_argument("--csv-in",
                   default=str(Path(__file__).resolve().parent.parent
                               / "data" / "lattice-periodic-table.csv"),
                   help="Path to lattice-periodic-table.csv")
    p.add_argument("--out", "--csv-out", default=None,
                   help="Output CSV path (default: data/hertzian-pairs-"
                        "<mapping>-<anchor>-<ratio>-<pairmode>.csv)")
    p.add_argument("--mapping", choices=list(MAPPINGS), default="period",
                   help="Lattice frequency mapping (default: period)")
    p.add_argument("--anchor", default="h-lyman-alpha",
                   help=f"Calibration anchor. Options: "
                        f"{', '.join(sorted(ANCHORS))}, or 'custom'.")
    p.add_argument("--custom-z", type=int, default=None,
                   help="Atomic number for custom anchor")
    p.add_argument("--custom-freq", type=float, default=None,
                   help="Frequency in Hz for custom anchor")
    p.add_argument("--ratio", default="khra-gixx",
                   help=f"Pair ratio. Aliases: {', '.join(sorted(RATIOS))}, "
                        f"or numeric > 1. Default: khra-gixx (16).")
    p.add_argument("--pair-mode", choices=["beat", "low", "high"],
                   default="beat",
                   help="What the anchor frequency represents. Default: beat "
                        "(matches the fractal-echo measurement).")
    p.add_argument("--include-sqrt3", action="store_true",
                   help="Honour c_s = 1/sqrt(3) when computing implied dx")
    p.add_argument("--quiet", action="store_true",
                   help="Suppress the stdout summary table")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    csv_in = Path(args.csv_in)
    if not csv_in.exists():
        print(f"ERROR: input CSV not found: {csv_in}", file=sys.stderr)
        return 2

    ratio, ratio_name = parse_ratio(args.ratio)
    rows = load_table(csv_in)
    out_rows, calib = compute(rows, args.mapping, args.anchor,
                              args.custom_z, args.custom_freq,
                              ratio, ratio_name, args.pair_mode,
                              args.include_sqrt3)

    if args.out is None:
        rn = ratio_name.replace("=", "").replace(".", "p")
        out_path = csv_in.parent / (
            f"hertzian-pairs-{args.mapping}-{args.anchor}"
            f"-{rn}-{args.pair_mode}.csv")
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
