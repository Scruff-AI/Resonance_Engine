import json
data = json.load(open(r"D:\fractal-brain\beast-build\somatic_dialogue_beast.json", encoding="utf-8"))

# Entry 10 - shift_protocol
e = data[10]
print("=== SHIFT PROTOCOL (entry 10) ===")
for k, v in e.items():
    val = str(v)
    if len(val) > 300:
        val = val[:300] + "..."
    print(f"  {k}: {val}")

print()

# Entry 11 - turing_probe
e = data[11]
print("=== TURING PROBE (entry 11) ===")
for k, v in e.items():
    val = str(v)
    if len(val) > 300:
        val = val[:300] + "..."
    print(f"  {k}: {val}")

print()

# Now check entries 6 (first_unfolding) - key data
e = data[6]
print("=== FIRST UNFOLDING (entry 6) ===")
if "messy_data" in e:
    print(f"  messy_data: {str(e['messy_data'])[:500]}")

print()

# Entry 9 - first_flight
e = data[9]
print("=== FIRST FLIGHT (entry 9) ===")
for k, v in e.items():
    val = str(v)
    if len(val) > 400:
        val = val[:400] + "..."
    print(f"  {k}: {val}")
