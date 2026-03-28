#!/usr/bin/env python3
"""DIMENSIONAL PRIME ANALYSIS — mode counting in 1D/2D/3D/4D.
Tests whether primes are dimension-dependent.
Key finding: 2 is structural in dimensions 2 and 3.
At dimension 4 = 2^2, Lagrange's theorem exhausts 2's power.
"""
import math
from collections import defaultdict
def is_prime(n):
    if n<2:return False
    if n<4:return True
    if n%2==0 or n%3==0:return False
    i=5
    while i*i<=n:
        if n%i==0 or n%(i+2)==0:return False
        i+=6
    return True
def sieve(n):
    if n<2:return []
    ip=[True]*(n+1);ip[0]=ip[1]=False
    for i in range(2,int(n**0.5)+1):
        if ip[i]:
            for j in range(i*i,n+1,i):ip[j]=False
    return [i for i in range(n+1) if ip[i]]
def modes_1d(me):
    c=defaultdict(int);mk=int(me**0.5)+1
    for k in range(-mk,mk+1):
        e=k*k
        if 0<e<=me:c[e]+=1
    return dict(sorted(c.items()))
def modes_2d(me):
    c=defaultdict(int);mk=int(me**0.5)+1
    for kx in range(-mk,mk+1):
        for ky in range(-mk,mk+1):
            e=kx*kx+ky*ky
            if 0<e<=me:c[e]+=1
    return dict(sorted(c.items()))
def modes_3d(me):
    c=defaultdict(int);mk=int(me**0.5)+1
    for kx in range(-mk,mk+1):
        for ky in range(-mk,mk+1):
            for kz in range(-mk,mk+1):
                e=kx*kx+ky*ky+kz*kz
                if 0<e<=me:c[e]+=1
    return dict(sorted(c.items()))
def modes_4d(me):
    c=defaultdict(int);mk=int(me**0.5)+1
    for k1 in range(-mk,mk+1):
        for k2 in range(-mk,mk+1):
            for k3 in range(-mk,mk+1):
                r2=k1*k1+k2*k2+k3*k3
                if r2>me:continue
                for k4 in range(-mk,mk+1):
                    e=r2+k4*k4
                    if 0<e<=me:c[e]+=1
    return dict(sorted(c.items()))
def main():
    ME=50
    print('='*70+'\n  DIMENSIONAL PRIME ANALYSIS\n'+'='*70)
    print('\n  Computing modes...')
    m1=modes_1d(ME);m2=modes_2d(ME);m3=modes_3d(ME)
    print('  Computing 4D...')
    m4=modes_4d(ME)
    r1=set(m1.keys());r2=set(m2.keys());r3=set(m3.keys());r4=set(m4.keys())
    nr3=set(range(1,ME+1))-r3;nr4=set(range(1,ME+1))-r4
    print(f'\n--- REPRESENTABLE ENERGIES ---')
    print(f'1D: {len(r1)}/{ME} (perfect squares only)')
    print(f'2D: {len(r2)}/{ME}')
    print(f'3D: {len(r3)}/{ME}, NOT rep: {sorted(nr3)}')
    print(f'4D: {len(r4)}/{ME} (ALL — Lagrange theorem)')
    print(f'\n--- 3D EXCLUSIONS (4^a * (8b+7)) ---')
    for n in sorted(nr3):
        m=n;a=0
        while m%4==0:m//=4;a+=1
        print(f'  {n:>4} = 4^{a} x {m} (mod8={m%8}) prime={is_prime(n)}')
    print(f'\n--- MODE TABLE ---')
    print(f'{"E":>4} {"1D":>4} {"2D":>5} {"3D":>6} {"4D":>7} {"2Dcum":>6} {"3Dcum":>6}')
    c2=0;c3=0;nm={2,8,20,28,50,82,126};hm={2,8,20,40,70,112}
    for e in range(1,ME+1):
        d1=m1.get(e,0);d2=m2.get(e,0);d3=m3.get(e,0);d4=m4.get(e,0)
        c2+=d2;c3+=d3
        mk=[]
        if c2 in nm:mk.append(f'2D->N:{c2}')
        if c3 in nm:mk.append(f'3D->N:{c3}')
        if c2 in hm:mk.append(f'2D->HO:{c2}')
        if d2>0 or d3>0 or mk:
            print(f'  {e:>4} {d1:>4} {d2:>5} {d3:>6} {d4:>7} {c2:>6} {c3:>6}  {" ".join(mk)}')
    print(f'\n--- MAGIC NUMBER SPEED ---')
    for mg in [2,8,20,28,40,50,70,82,112,126]:
        c2=0;e2=None
        for e in sorted(m2.keys()):
            c2+=m2[e]
            if c2>=mg and not e2:e2=e
        c3=0;e3=None
        for e in sorted(m3.keys()):
            c3+=m3[e]
            if c3>=mg and not e3:e3=e
        print(f'  Magic {mg:>3}: 2D@E={e2}, 3D@E={e3} {"(3D faster)" if e3 and e2 and e3<e2 else ""}')
    print(f'\n--- COPRIME SIEVE IN 3D ---')
    p100=set(sieve(100))
    for wls in [(128,8),(128,8,6),(128,9,5),(127,9,5)]:
        sv=[n for n in range(2,101) if all(math.gcd(n,w)==1 for w in wls)]
        cap=p100&set(sv);miss=p100-set(sv)
        sp=set();
        for w in wls:
            n=w;d=2
            while d*d<=n:
                while n%d==0:sp.add(d);n//=d
                d+=1
            if n>1:sp.add(n)
        print(f'  WL{wls}: structural={sorted(sp)} prec={100*len(cap)/max(1,len(sv)):.1f}% miss={sorted(miss)}')
    print(f'\n--- SUMMARY ---')
    print(f'2 is structural in 2D (mod 4) and 3D (4^a(8b+7)).')
    print(f'At dim 4 = 2^2, Lagrange exhausts 2. Self-referential.')
    print(f'Odd primes (3,5,7,11...) are universal across all dimensions.')
    print(f'In dim D, the first D-1 primes can be made structural.')
if __name__=='__main__':main()
