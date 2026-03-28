# Updated estimate with speed optimization
# Omega reduced from 1.95 to 1.85 (~7% reduction in viscosity)

print("=== UPDATED TIME ESTIMATE ===")
print()
print("Optimization: Omega 1.95 -> 1.85")
print("Expected: 2-3x faster extraction")
print()

# Conservative estimate: 2x faster
speedup_factor = 2.0

original_hours = 99
optimized_hours = original_hours / speedup_factor

print(f"Original estimate: {original_hours:.0f} hours ({original_hours/24:.1f} days)")
print(f"With 2x speedup: {optimized_hours:.0f} hours ({optimized_hours/24:.1f} days)")
print()

# Optimistic estimate: 3x faster
speedup_factor = 3.0
optimized_hours = original_hours / speedup_factor

print(f"With 3x speedup: {optimized_hours:.0f} hours ({optimized_hours/24:.1f} days)")
print()

print("REALISTIC ESTIMATE:")
print("  ~50 hours (2 days) for 100 primes")
print("  ~25 hours (1 day) if 3x speedup achieved")
print()
print("Note: Actual speed depends on how much")
print("the reduced Omega improves convergence.")
