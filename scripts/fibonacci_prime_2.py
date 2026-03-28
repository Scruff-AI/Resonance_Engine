#!/usr/bin/env python3
"""Fibonacci, Phi, Primes, and the Number 2.
Chain: 2 -> phi -> Fibonacci -> Zeckendorf -> prime distribution -> zeta -> lattice.
"""
import math
from collections import defaultdict
PHI=(1+math.sqrt(5))/2
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
def fib(n):
    f=[0,1]
    for i in range(2,n):f.append(f[-1]+f[-2])
    return f
def lucas(n):
    l=[2,1]
    for i in range(2,n):l.append(l[-1]+l[-2])
    return l
def pisano(m):
    a,b=0,1
    for i in range(1,m*m+1):
        a,b=b,(a+b)%m
        if a==0 and b==1:return i
    return -1
def zeckendorf(n):
    fs=[f for f in fib(30) if 0<f<=n];fs.reverse()
    rep=[];rem=n
    for f in fs:
        if f<=rem:rep.append(f);rem-=f
    return rep
def main():
    print('='*70+'\n  FIBONACCI, PHI, PRIMES, AND THE NUMBER 2\n'+'='*70)
    print(f'\n--- 1. PHI IS DEFINED BY 2 ---')
    print(f'phi = (1+sqrt(5))/2 = {PHI:.10f}')
    print(f'phi^2 = phi+1 = {PHI**2:.10f}')
    print(f'The 2 is the degree of the polynomial. Phi exists because equations can be degree 2.')
    print(f'\n--- 2. FIBONACCI AND POWERS OF 2 ---')
    fs=fib(30);p2={2**i for i in range(20)}
    fp2=[(i,f) for i,f in enumerate(fs) if f in p2 and f>0]
    print(f'Fib powers of 2: {fp2}')
    print(f'F(3)=2 is the departure point. After 2, Fibonacci leaves 2^n permanently.')
    print(f'\n--- 3. FIBONACCI PRIMES ---')
    fs40=fib(40);fpr=[(i,f) for i,f in enumerate(fs40) if is_prime(f)]
    print(f'F(n) prime: {fpr}')
    idx=[i for i,_ in fpr];pidx=[i for i in idx if is_prime(i)]
    print(f'Indices: {idx}  Prime indices: {pidx}')
    print(f'\n--- 4. ZECKENDORF OF PRIMES ---')
    for p in sieve(50):print(f'  {p:>4} = {" + ".join(str(f) for f in zeckendorf(p))}')
    print(f'\n--- 5. LUCAS = FIBONACCI STARTING FROM 2 ---')
    lc=lucas(15);print(f'Lucas: {lc}');print(f'Fib:   {fs[:15]}')
    print(f'\n--- 6. PHI POWERS = LUCAS NUMBERS ---')
    for n in range(1,15):
        pn=PHI**n;ni=round(pn)
        if abs(pn-ni)<0.05:
            fl='FIB' if ni in set(fs) else 'LUCAS' if ni in set(lc) else ''
            print(f'  phi^{n:>2} = {pn:>10.4f} ~ {ni:>5}  {fl}')
    print(f'\n--- 7. LATTICE: 16 = phi^{math.log(16)/math.log(PHI):.4f} ---')
    print(f'Khra/Gixx ratio 16 sits between phi^5 and phi^6')
    print(f'\n--- 8. CONTINUED FRACTIONS ---')
    print(f'phi = [1;1,1,1,...] (most irrational)')
    print(f'sqrt(2) = [1;2,2,2,...] (second most irrational)')
    print(f'sqrt(2) = 2^(1/2) — self-referential')
    print(f'\n--- 9. PISANO PERIODS ---')
    for p in [2,3,5,7,11,13,17,19,23,29]:
        pp=pisano(p);print(f'  p={p:>3}: pi={pp:>4} pi/p={pp/p:.4f}')
    print(f'  p=2: pi(2)=3. The number 2 generates 3 through Fibonacci.')
    print(f'\n--- SYNTHESIS ---')
    print(f'2 -> phi -> Fibonacci -> primes -> zeta -> zeros -> lattice')
    print(f'2 is at the TOP. It generates everything. It is the axiom.')
if __name__=='__main__':main()
