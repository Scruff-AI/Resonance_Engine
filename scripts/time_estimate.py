# Current stats
current_turns = 8287
start_turns = 7750  # From ~11 hours ago
turns_per_hour = (8287 - 7750) / 11

print("=== TIME ESTIMATE ===")
print()
print(f"Current extraction rate: {turns_per_hour:.1f} turns/hour")
print()

# We have 10 primes, need 100+ for reliable extrapolation
primes_needed = 100
primes_have = 10
primes_per_turn = 10 / 537  # 10 primes in 537 turns

print(f"Primes per turn: {primes_per_turn:.3f}")
print()

turns_needed = (primes_needed - primes_have) / primes_per_turn
hours_needed = turns_needed / turns_per_hour

print(f"To extract {primes_needed} primes:")
print(f"  Turns needed: {turns_needed:.0f}")
print(f"  Hours needed: {hours_needed:.1f}")
print(f"  Days needed: {hours_needed/24:.1f}")
print()

print("ESTIMATE:")
print(f"  ~{hours_needed:.0f} hours ({hours_needed/24:.1f} days)")
print(f"  to extract 100 primes at current rate")
