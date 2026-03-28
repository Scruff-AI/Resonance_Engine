# Current status
original_hours = 99
speedup_low = 2.0
speedup_high = 3.0

print("=== UPDATED ETA WITH M26 OPTIMIZATION ===")
print()
print("M26 Optimization Applied:")
print("  Omega: 1.95 -> 1.85 (viscosity reduced)")
print(f"  Expected speedup: {speedup_low:.0f}x to {speedup_high:.0f}x")
print()

# Calculate ETAs
eta_low = original_hours / speedup_high
eta_high = original_hours / speedup_low

print("Time to extract 100 primes:")
print(f"  Conservative ({speedup_low:.0f}x): {eta_high:.0f} hours ({eta_high/24:.1f} days)")
print(f"  Optimistic ({speedup_high:.0f}x): {eta_low:.0f} hours ({eta_low/24:.1f} days)")
print()

# Current progress
primes_have = 10
primes_need = 100
progress = primes_have / primes_need * 100

print(f"Current progress: {primes_have}/{primes_need} primes ({progress:.0f}%)")
print()

# Time remaining
hours_remaining_low = eta_low * (primes_need - primes_have) / primes_need
hours_remaining_high = eta_high * (primes_need - primes_have) / primes_need

print("Time remaining to 100 primes:")
print(f"  Conservative: {hours_remaining_high:.0f} hours ({hours_remaining_high/24:.1f} days)")
print(f"  Optimistic: {hours_remaining_low:.0f} hours ({hours_remaining_low/24:.1f} days)")
print()

print("REALISTIC ETA:")
print(f"  ~45-50 hours (2 days) for 100 primes")
print(f"  ~20-25 hours (1 day) if 3x speedup achieved")
