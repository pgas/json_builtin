#!/bin/bash
# Test: array containing objects
SO_PATH="$1"
enable -f "$SO_PATH" json

json -v arr -j '[{"name": "Alice"}, {"name": "Bob"}, 42]'

# arr[0] should be a pretty-printed object
echo "${arr[0]}" | grep -q '"Alice"' || { echo "FAIL: arr[0] doesn't contain 'Alice'"; exit 1; }

# arr[1] should be a pretty-printed object
echo "${arr[1]}" | grep -q '"Bob"' || { echo "FAIL: arr[1] doesn't contain 'Bob'"; exit 1; }

# arr[2] should be a scalar
[[ "${arr[2]}" == "42" ]] || { echo "FAIL: arr[2]='${arr[2]}' expected '42'"; exit 1; }

# Navigate into first object via pointer
json -v obj0 -a "${arr_[0]}"
[[ "${obj0[name]}" == "Alice" ]] || { echo "FAIL: obj0[name]='${obj0[name]}' expected 'Alice'"; exit 1; }

# Navigate into second object
json -v obj1 -a "${arr_[1]}"
[[ "${obj1[name]}" == "Bob" ]] || { echo "FAIL: obj1[name]='${obj1[name]}' expected 'Bob'"; exit 1; }

# Navigate into scalar
json -v val -a "${arr_[2]}"
[[ "$val" == "42" ]] || { echo "FAIL: val='$val' expected '42'"; exit 1; }

exit 0
