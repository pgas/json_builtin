#!/bin/bash
# Test: basic JSON parsing with -j
SO_PATH="$1"
enable -f "$SO_PATH" json

# Parse a simple JSON object
json -v data -j '{"name": "John", "age": 30, "active": true}'

# Check key values
[[ "${data[name]}" == "John" ]] || { echo "FAIL: data[name]='${data[name]}' expected 'John'"; exit 1; }
[[ "${data[age]}" == "30" ]] || { echo "FAIL: data[age]='${data[age]}' expected '30'"; exit 1; }
[[ "${data[active]}" == "true" ]] || { echo "FAIL: data[active]='${data[active]}' expected 'true'"; exit 1; }

# The pointer variable should also exist
[[ -n "${data_[name]}" ]] || { echo "FAIL: data_[name] is empty"; exit 1; }
[[ "${data_[name]}" == 0x* ]] || { echo "FAIL: data_[name]='${data_[name]}' doesn't look like a pointer"; exit 1; }

exit 0
