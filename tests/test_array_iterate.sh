#!/bin/bash
# Test: iterating over JSON array elements
SO_PATH="$1"
enable -f "$SO_PATH" json

json -v arr -j '["foo", "bar", "baz"]'

# Iterate with ${arr[@]}
values=()
for e in "${arr[@]}"; do
  values+=("$e")
done

[[ ${#values[@]} -eq 3 ]] || { echo "FAIL: expected 3, got ${#values[@]}"; exit 1; }
[[ "${values[0]}" == "foo" ]] || { echo "FAIL: values[0]='${values[0]}' expected 'foo'"; exit 1; }
[[ "${values[1]}" == "bar" ]] || { echo "FAIL: values[1]='${values[1]}' expected 'bar'"; exit 1; }
[[ "${values[2]}" == "baz" ]] || { echo "FAIL: values[2]='${values[2]}' expected 'baz'"; exit 1; }

# Iterate over pointers
ptr_values=()
for a in "${arr_[@]}"; do
  json -v e -a "$a"
  ptr_values+=("$e")
done

[[ ${#ptr_values[@]} -eq 3 ]] || { echo "FAIL: expected 3 ptr values, got ${#ptr_values[@]}"; exit 1; }
[[ "${ptr_values[0]}" == "foo" ]] || { echo "FAIL: ptr_values[0]='${ptr_values[0]}' expected 'foo'"; exit 1; }
[[ "${ptr_values[1]}" == "bar" ]] || { echo "FAIL: ptr_values[1]='${ptr_values[1]}' expected 'bar'"; exit 1; }

exit 0
