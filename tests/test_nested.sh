#!/bin/bash
# Test: nested JSON objects
SO_PATH="$1"
enable -f "$SO_PATH" json

json -v var -j '{"name": "John", "age": 30, "address": {"line1": "red street", "line2": "cambridge"}}'

# Top-level keys
[[ "${var[name]}" == "John" ]] || { echo "FAIL: var[name]='${var[name]}' expected 'John'"; exit 1; }
[[ "${var[age]}" == "30" ]] || { echo "FAIL: var[age]='${var[age]}' expected '30'"; exit 1; }

# Nested object should be pretty-printed JSON
echo "${var[address]}" | grep -q '"line1"' || { echo "FAIL: var[address] doesn't contain '\"line1\"'"; exit 1; }
echo "${var[address]}" | grep -q '"red street"' || { echo "FAIL: var[address] doesn't contain '\"red street\"'"; exit 1; }

# Navigate into nested object via pointer
json -v addr -a "${var_[address]}"

[[ "${addr[line1]}" == "red street" ]] || { echo "FAIL: addr[line1]='${addr[line1]}' expected 'red street'"; exit 1; }
[[ "${addr[line2]}" == "cambridge" ]] || { echo "FAIL: addr[line2]='${addr[line2]}' expected 'cambridge'"; exit 1; }

exit 0
