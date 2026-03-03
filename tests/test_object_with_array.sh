#!/bin/bash
# Test: object containing an array
SO_PATH="$1"
enable -f "$SO_PATH" json

json -v var -j '{"k": 12, "l": [1, {"k": "foo"}]}'

# Top-level object keys
[[ "${var[k]}" == "12" ]] || { echo "FAIL: var[k]='${var[k]}' expected '12'"; exit 1; }

# "l" should be a pretty-printed JSON array string
echo "${var[l]}" | grep -q '1' || { echo "FAIL: var[l] doesn't contain '1'"; exit 1; }
echo "${var[l]}" | grep -q '"foo"' || { echo "FAIL: var[l] doesn't contain '\"foo\"'"; exit 1; }

# Navigate into the array via pointer
json -v arr -a "${var_[l]}"

# arr should be an indexed array
[[ "${arr[0]}" == "1" ]] || { echo "FAIL: arr[0]='${arr[0]}' expected '1'"; exit 1; }

# arr[1] should be a pretty-printed object
echo "${arr[1]}" | grep -q '"k"' || { echo "FAIL: arr[1] doesn't contain '\"k\"'"; exit 1; }
echo "${arr[1]}" | grep -q '"foo"' || { echo "FAIL: arr[1] doesn't contain '\"foo\"'"; exit 1; }

# Navigate into the nested object inside the array
json -v obj -a "${arr_[1]}"
[[ "${obj[k]}" == "foo" ]] || { echo "FAIL: obj[k]='${obj[k]}' expected 'foo'"; exit 1; }

exit 0
