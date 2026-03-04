#!/bin/bash
# Test: assignment callbacks — var[key]=value updates JSON in-place
SO_PATH="$1"
enable -f "$SO_PATH" json

# --- Object: assign a scalar value to an existing key ---
json -v obj -j '{"name": "Alice", "age": 30}'

obj[name]="Bob"
[[ "${obj[name]}" == "Bob" ]] || { echo "FAIL: obj[name]='${obj[name]}' expected 'Bob'"; exit 1; }

# The companion pointer variable must reflect the new value
json -v name_val -a "${obj_[name]}"
[[ "$name_val" == "Bob" ]] || { echo "FAIL: name_val after pointer='$name_val' expected 'Bob'"; exit 1; }

# --- Object: assign a JSON number ---
obj[age]="99"
[[ "${obj[age]}" == "99" ]] || { echo "FAIL: obj[age]='${obj[age]}' expected '99'"; exit 1; }

# --- Object: add a new key ---
obj[city]="London"
[[ "${obj[city]}" == "London" ]] || { echo "FAIL: obj[city]='${obj[city]}' expected 'London'"; exit 1; }

# --- Array: assign a new element value ---
json -v arr -j '["a", "b", "c"]'

arr[0]="x"
[[ "${arr[0]}" == "x" ]] || { echo "FAIL: arr[0]='${arr[0]}' expected 'x'"; exit 1; }

# Pointer for index 0 should resolve to the new value
json -v elem -a "${arr_[0]}"
[[ "$elem" == "x" ]] || { echo "FAIL: elem after pointer='$elem' expected 'x'"; exit 1; }

# Other elements must be untouched
[[ "${arr[1]}" == "b" ]] || { echo "FAIL: arr[1]='${arr[1]}' expected 'b'"; exit 1; }

exit 0
