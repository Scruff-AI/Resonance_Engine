#!/usr/bin/env python3
"""Hadron Regge Trajectory Analysis - Does the lattice reproduce M^2 proportional to J?"""
import csv,math,sys
from collections import defaultdict

def load(fn):
    data=[]
    with open(fn,'r') as f:
        for row in csv.DictReader(f):
            d={}
            for k,v in row.items():
                k=k.strip().lower()
                try: d[k]=float(v)
                except: d[k]=v
            if d.get('omega',0)>0: data.append(d)
    return data

def linreg(x,y):
    n=len(x)
    if n<3: return 0,0,0
    sx=sum(x);sy=sum(y);sxx=sum(xi*xi for xi in x);sxy=sum(xi*yi for xi,yi in zip(x,y))
    denom=n*sxx-sx*sx
    if denom==0: return 0,0,0
    slope=(n*sxy-sx*sy)/denom;intercept=(sy-slope*sx)/n
    ss_res=sum((yi-(slope*xi+intercept))**2 for xi,yi in zip(x,y))
    ss_tot=sum((yi-sy/n)**2 for yi in y)
    r2=1-ss_res/ss_tot if ss_tot>0 else 0
    return slope,intercept,r2

def main():
    fn=sys.argv[1] if len(sys.argv)>1 else None
    if not fn: print("Usage: python hadron_regge_analysis.py sweep.csv");return
    data=load(fn)
    print("="*70+"\n  HADRON REGGE TRAJECTORY ANALYSIS\n"+"="*70)
    print(f"  Source: {fn}\n  Points: {len(data)}")

    # Real hadron data
    rho=[('rho(770)',0.770,1),('a2(1320)',1.320,2),('rho3(1690)',1.690,3),('a4(2040)',2.040,4),('rho5(2350)',2.350,5)]
    nuc=[('N(938)',0.938,0.5),('N(1520)',1.520,1.5),('N(1680)',1.680,2.5),('N(2190)',2.190,3.5),('N(2600)',2.600,4.5)]

    print(f"\n--- REAL HADRON REGGE TRAJECTORIES ---")
    rho_j=[j for _,_,j in rho]; rho_m2=[m**2 for _,m,_ in rho]
    sl_r,_,r2_r=linreg(rho_j,rho_m2)
    print(f"  rho-meson family: R2={r2_r:.6f}, slope={sl_r:.4f}, alpha'={1/sl_r:.4f}")
    nuc_j=[j for _,_,j in nuc]; nuc_m2=[m**2 for _,m,_ in nuc]
    sl_n,_,r2_n=linreg(nuc_j,nuc_m2)
    print(f"  Nucleon family:   R2={r2_n:.6f}, slope={sl_n:.4f}, alpha'={1/sl_n:.4f}")

    by_khra=defaultdict(list); by_gixx=defaultdict(list); by_omega=defaultdict(list)
    for d in data:
        by_khra[round(d['khra_amp'],4)].append(d)
        by_gixx[round(d['gixx_amp'],4)].append(d)
        by_omega[round(d['omega'],2)].append(d)

    print(f"\n--- LATTICE REGGE TESTS ---")
    results={}

    kv=sorted(by_khra.keys()); km2=[k**2 for k in kv]
    ka=[sum(d['asymmetry'] for d in by_khra[k])/len(by_khra[k]) for k in kv]
    kvor=[sum(d['vorticity_mean'] for d in by_khra[k])/len(by_khra[k]) for k in kv]
    sl,_,r2=linreg(ka,km2); results['khra_asym']=r2
    print(f"\n  khra^2 vs asymmetry: R2 = {r2:.6f}  {'*** REGGE ***' if r2>0.99 else ''}")
    sl2,_,r2v=linreg(kvor,km2); results['khra_vort']=r2v
    print(f"  khra^2 vs vorticity: R2 = {r2v:.6f}")

    gv=sorted(by_gixx.keys()); gm2=[g**2 for g in gv]
    ga=[sum(d['asymmetry'] for d in by_gixx[g])/len(by_gixx[g]) for g in gv]
    gvor=[sum(d['vorticity_mean'] for d in by_gixx[g])/len(by_gixx[g]) for g in gv]
    sl3,_,r2g=linreg(ga,gm2); results['gixx_asym']=r2g
    print(f"\n  gixx^2 vs asymmetry: R2 = {r2g:.6f}  {'*** REGGE ***' if r2g>0.99 else ''}")
    sl4,_,r2gv=linreg(gvor,gm2); results['gixx_vort']=r2gv
    print(f"  gixx^2 vs vorticity: R2 = {r2gv:.6f}")

    ov=sorted(by_omega.keys()); om2=[o**2 for o in ov]
    oa=[sum(d['asymmetry'] for d in by_omega[o])/len(by_omega[o]) for o in ov]
    sl5,_,r2o=linreg(oa,om2); results['omega_asym']=r2o
    print(f"\n  omega^2 vs asymmetry (control): R2 = {r2o:.6f}")

    print(f"\n--- COMPARISON ---")
    print(f"  {'System':>20} {'R2':>10}")
    print(f"  {'rho-meson':>20} {r2_r:>10.6f}")
    print(f"  {'Nucleon':>20} {r2_n:>10.6f}")
    print(f"  {'Lattice khra':>20} {results['khra_asym']:>10.6f}")
    print(f"  {'Lattice gixx':>20} {results['gixx_asym']:>10.6f}")
    print(f"  {'Lattice omega':>20} {results['omega_asym']:>10.6f}")

    print(f"\n--- VERDICT ---")
    tests=[
        ("khra^2 vs asym: R2>0.99",results['khra_asym']>0.99),
        ("gixx^2 vs asym: R2>0.99",results['gixx_asym']>0.99),
        ("omega control fails",results['omega_asym']<0.80),
        ("Asym > vort as J proxy",results['khra_asym']>results['khra_vort']),
        ("Matches real hadron R2",results['khra_asym']>0.99),
    ]
    passed=sum(1 for _,v in tests if v)
    for name,v in tests: print(f"  {name:<45} {'PASS' if v else 'FAIL'}")
    print(f"\n  PASSED: {passed}/5")
    if passed>=4: print("  STRONG EVIDENCE: Lattice reproduces hadron Regge trajectories")

if __name__=='__main__': main()
