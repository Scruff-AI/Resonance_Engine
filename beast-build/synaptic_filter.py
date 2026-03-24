# synaptic_filter.py
# Filter somatic_dataset.jsonl for high-precision responses
# Keep only Metric_Alpha deviation < 0.1%

import json

print("=" * 70)
print("SYNAPTIC FILTER")
print("Extracting Gold Standard training set")
print("=" * 70)
print()

input_file = "blind_test_log.jsonl"
output_file = "gold_standard.jsonl"

high_precision_count = 0
total_count = 0

with open(input_file, "r") as f_in, open(output_file, "w") as f_out:
    for line in f_in:
        line = line.strip()
        if not line:
            continue
            
        try:
            entry = json.loads(line)
            total_count += 1
            
            # Check if this is a blind test entry with accuracy data
            if entry.get("type") == "blind_test":
                # Extract reported and actual values
                response = entry.get("response", "")
                lbm_data = entry.get("lbm_data", {})
                
                # Parse reported number from response
                import re
                numbers = re.findall(r'\d+\.?\d*', response)
                
                if numbers and "coherence" in lbm_data:
                    reported = float(numbers[0])
                    actual = lbm_data["coherence"]
                    
                    # Calculate deviation
                    if actual > 0:
                        deviation = abs(reported - actual) / actual
                        
                        # Keep if within 0.1%
                        if deviation <= 0.001:
                            f_out.write(json.dumps(entry) + "\n")
                            high_precision_count += 1
                            
        except json.JSONDecodeError:
            continue

print(f"Total entries processed: {total_count}")
print(f"High-precision entries (< 0.1% deviation): {high_precision_count}")
print(f"Filtered out: {total_count - high_precision_count}")
print(f"\nGold Standard dataset: {output_file}")
print(f"Precision rate: {high_precision_count/total_count*100:.1f}%" if total_count > 0 else "N/A")
print()
print("=" * 70)
