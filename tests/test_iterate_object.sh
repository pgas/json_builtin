#!/bin/bash
# Test: iterating over object elements with ${var[@]}
SO_PATH="$1"
enable -f "$SO_PATH" json

json -v var -j '{"name": "John", "age": 12}'

# Collect all values via ${var[@]}
values=()
for e in "${var[@]}"; do
  values+=("$e")
done

# Should have exactly 2 elements (name and age)
[[ ${#values[@]} -eq 2 ]] || { echo "FAIL: expected 2 elements, got ${#values[@]}: ${values[*]}"; exit 1; }

# Check that both "John" and "12" are present (order may vary for assoc arrays)
found_john=0
found_age=0
for e in "${values[@]}"; do
  [[ "$e" == "John" ]] && found_john=1
  [[ "$e" == "12" ]] && found_age=1
done
[[ $found_john -eq 1 ]] || { echo "FAIL: 'John' not found in values: ${values[*]}"; exit 1; }
[[ $found_age -eq 1 ]] || { echo "FAIL: '12' not found in values: ${values[*]}"; exit 1; }

exit 0
