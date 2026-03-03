#!/bin/bash
# Test: nested arrays (array inside array)
SO_PATH="$1"
enable -f "$SO_PATH" json

json -v var -j '[[1, 2], [3, 4], "hello"]'

# Top-level should be an indexed array with 3 elements
[[ ${#var[@]} -eq 3 ]] || { echo "FAIL: expected 3 elements, got ${#var[@]}"; exit 1; }

# var[0] should be a pretty-printed array
echo "${var[0]}" | grep -q '1' || { echo "FAIL: var[0] doesn't contain '1'"; exit 1; }
echo "${var[0]}" | grep -q '2' || { echo "FAIL: var[0] doesn't contain '2'"; exit 1; }

# var[2] should be "hello"
[[ "${var[2]}" == "hello" ]] || { echo "FAIL: var[2]='${var[2]}' expected 'hello'"; exit 1; }

# Navigate into first sub-array
json -v sub -a "${var_[0]}"
[[ "${sub[0]}" == "1" ]] || { echo "FAIL: sub[0]='${sub[0]}' expected '1'"; exit 1; }
[[ "${sub[1]}" == "2" ]] || { echo "FAIL: sub[1]='${sub[1]}' expected '2'"; exit 1; }

# Navigate into second sub-array
json -v sub2 -a "${var_[1]}"
[[ "${sub2[0]}" == "3" ]] || { echo "FAIL: sub2[0]='${sub2[0]}' expected '3'"; exit 1; }
[[ "${sub2[1]}" == "4" ]] || { echo "FAIL: sub2[1]='${sub2[1]}' expected '4'"; exit 1; }

exit 0
