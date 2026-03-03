#!/bin/bash
# Test: JSON array creates indexed array
SO_PATH="$1"
enable -f "$SO_PATH" json

json -v arr -j '["foo", "bar", "baz"]'

# Check indexed access
[[ "${arr[0]}" == "foo" ]] || { echo "FAIL: arr[0]='${arr[0]}' expected 'foo'"; exit 1; }
[[ "${arr[1]}" == "bar" ]] || { echo "FAIL: arr[1]='${arr[1]}' expected 'bar'"; exit 1; }
[[ "${arr[2]}" == "baz" ]] || { echo "FAIL: arr[2]='${arr[2]}' expected 'baz'"; exit 1; }

# Check count
[[ ${#arr[@]} -eq 3 ]] || { echo "FAIL: expected 3 elements, got ${#arr[@]}"; exit 1; }

# Pointer array should also be indexed
[[ "${arr_[0]}" == 0x* ]] || { echo "FAIL: arr_[0]='${arr_[0]}' doesn't look like a pointer"; exit 1; }
[[ "${arr_[1]}" == 0x* ]] || { echo "FAIL: arr_[1]='${arr_[1]}' doesn't look like a pointer"; exit 1; }

exit 0
