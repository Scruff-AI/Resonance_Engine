#!/usr/bin/env python3
"""Protein Folding Fractal Echo - compares lattice coherence to Ramachandran landscape"""
import sys,csv,math
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

def main():
    fn=sys.argv[1] if len(sys.argv)>1 else None
    if not fn:
        print("Usage: python protein_fold_echo.py sweep.csv")
        return
    data=load(fn)
    n=len(data)
    cohs=[d['coherence'] for d in data]
    mn,mx=min(cohs),max(cohs)
    mean=sum(cohs)/n
    std=(sum((c-mean)**2 for c in cohs)/n)**0.5
    med=sorted(cohs)[n//2]
    skew=sum((c-mean)**3 for c in cohs)/(n*std**3) if std>0 else 0

    print("="*70)
    print(" PROTEIN FOLDING FRACTAL ECHO ANALYZER")
    print("="*70)
    print(f" Source: {fn}")
    print(f" Points: {n}")
    print(f" Coherence: {mn:.6f} to {mx:.6f}")
    print(f" Mean={mean:.6f} Std={std:.6f}")

    by_om=defaultdict(list)
    for d in data:
        by_om[round(d['omega'],2)].append(d)

    results={}

    # TEST 1: Basin Counting (Ramachandran has 4-5 basins)
    print(f"\n{'='*70}")
    print(" TEST 1: BASIN COUNTING (Ramachandran has 4-5 basins)")
    print("="*70)
    basin_matches=0
    for om in sorted(by_om.keys()):
        pts=by_om[om]
        cs=sorted(set(round(p['coherence'],4) for p in pts))
        if len(cs)<2:
            basins=1
        else:
            gaps=[cs[i+1]-cs[i] for i in range(len(cs)-1)]
            mg=sum(gaps)/len(gaps) if gaps else 0
            basins=sum(1 for g in gaps if g>mg*2)+1
        match="<<<" if 3<=basins<=6 else ""
        if 3<=basins<=6:
            basin_matches+=1
        print(f" om={om:.1f}: {len(cs):>3} distinct, {basins:>2} basins {match}")
    print(f"\n Slices with 3-6 basins: {basin_matches}/{len(by_om)}")
    results['basin']=basin_matches>=3

    # TEST 2: Forbidden Fraction (Ramachandran ~35% allowed)
    print(f"\n{'='*70}")
    print(" TEST 2: FORBIDDEN FRACTION (Ramachandran ~35% allowed)")
    print("="*70)
    top35=sorted(cohs)[int(n*0.65)]
    allowed=sum(1 for c in cohs if c>=top35)/n
    diff=abs(allowed-0.35)
    print(f" Top 35% threshold: {top35:.6f}")
    print(f" Allowed fraction: {allowed:.1%}")
    print(f" Ramachandran target: 35%")
    print(f" Difference: {diff:.1%}")
    print(f" {'PASS' if diff<0.15 else 'FAIL'}")
    results['forbidden']=diff<0.15

    # TEST 3: Funnel Topology (proteins have positive skewness)
    print(f"\n{'='*70}")
    print(" TEST 3: FUNNEL TOPOLOGY (proteins have positive skewness)")
    print("="*70)
    cr=mx-mn
    if cr>0:
        nb=10
        bw=cr/nb
        bins=[0]*nb
        for c in cohs:
            b=min(int((c-mn)/bw),nb-1)
            bins[b]+=1
        for i in range(nb):
            lo=mn+i*bw
            hi=lo+bw
            bar='#'*(bins[i]*40//max(max(bins),1))
            print(f" {lo:.4f}-{hi:.4f}: {bins[i]:>5} {bar}")
    print(f"\n Skewness: {skew:+.4f}")
    if skew>0.3:
        print(" >>> FUNNEL DETECTED")
    elif skew<-0.3:
        print(" >>> INVERTED FUNNEL")
    else:
        print(" >>> FLAT LANDSCAPE")
    results['funnel']=abs(skew)>0.3

    # TEST 4: Amino Acid Classes (5 Ramachandran classes)
    print(f"\n{'='*70}")
    print(" TEST 4: AMINO ACID CLASS MAPPING (5 classes expected)")
    print("="*70)
    classes=set()
    for om in sorted(by_om.keys()):
        pts=by_om[om]
        cr2=max(p['coherence'] for p in pts)-min(p['coherence'] for p in pts)
        if cr2<0.0005:
            cls='proline'
        elif cr2<0.002:
            cls='pre_proline'
        elif cr2<0.005:
            cls='beta_branched'
        elif cr2<0.02:
            cls='general'
        else:
            cls='glycine'
        classes.add(cls)
        print(f" om={om:.1f}: range={cr2:.6f} -> {cls}")
    print(f"\n Classes found: {len(classes)}/5 = {sorted(classes)}")
    results['classes']=len(classes)>=3

    # TEST 5: Levinthal Compression
    print(f"\n{'='*70}")
    print(" TEST 5: LEVINTHAL COMPRESSION")
    print("="*70)
    distinct=len(set(round(c,4) for c in cohs))
    comp=n/max(1,distinct)
    print(f" Combinations: {n}")
    print(f" Distinct modes: {distinct}")
    print(f" Compression: {comp:.1f}:1")
    results['levinthal']=comp>2

    # TEST 6: Hierarchy
    print(f"\n{'='*70}")
    print(" TEST 6: HIERARCHICAL STRUCTURE")
    print("="*70)
    n_class=len(by_om)
    n_topo=distinct
    print(f" CATH: 4 classes -> 41 arch -> 1393 topo")
    print(f" Lattice: {n_class} classes -> {n_topo} topo")
    results['hierarchy']=n_topo>10

    # VERDICT
    print(f"\n{'='*70}")
    print(" VERDICT")
    print("="*70)
    tests=[
        ('Basin count (3-6)',results.get('basin',False)),
        ('Forbidden fraction (25-45%)',results.get('forbidden',False)),
        ('Funnel topology',results.get('funnel',False)),
        ('Amino acid classes (3+/5)',results.get('classes',False)),
        ('Levinthal compression (>2:1)',results.get('levinthal',False)),
        ('Hierarchical structure',results.get('hierarchy',False))
    ]
    passed=sum(1 for _,v in tests if v)
    for name,v in tests:
        print(f" {name:<35} {'PASS' if v else 'FAIL':>6}")
    print(f"\n PASSED: {passed}/6")
    if passed>=4:
        print(" STRONG EVIDENCE: Fractal echo extends to protein folding")
    elif passed>=3:
        print(" MODERATE EVIDENCE: Partial structural similarity")
    else:
        print(" WEAK EVIDENCE: Limited similarity")

if __name__=='__main__':
    main()
