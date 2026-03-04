#!/bin/bash
# Test: assignment to pointer variable (var_[key]=ptr) deep-copies the object
SO_PATH="$1"
enable -f "$SO_PATH" json

# Prepare two separate JSON objects
json -v src -j '{"value": "deep-copy-me", "num": 42}'
json -v dst -j '{"name": "Alice", "nested": {"value": "old", "num": 0}}'

# Navigate to dst's nested object and verify current state
json -v before -a "${dst_[nested]}"
[[ "${before[value]}" == "old" ]] || { echo "FAIL: before[value]='${before[value]}' expected 'old'"; exit 1; }

# Replace dst_[nested] with a pointer from src (deep copy)
dst_[nested]="${src_[value]}"   # src_[value] is a scalar pointer
                                 # The callback validates and deep-copies it

# Read the nested object again from dst — it should now mirror src[value]
json -v after -a "${dst_[nested]}"
# src_[value] points to the scalar "deep-copy-me"
[[ "$after" == "deep-copy-me" ]] || { echo "FAIL: after='$after' expected 'deep-copy-me'"; exit 1; }

# The display variable dst[nested] must also be updated
[[ "${dst[nested]}" == "deep-copy-me" ]] || { echo "FAIL: dst[nested]='${dst[nested]}' expected 'deep-copy-me'"; exit 1; }

# --- Array variant ---
json -v src2 -j '{"label": "replaced"}'
json -v arr  -j '[{"label": "original"}, {"label": "second"}]'

# Replace first element of arr via its pointer slot
arr_[0]="${src2_[label]}"   # src2_[label] points to scalar "replaced"

json -v elem -a "${arr_[0]}"
[[ "$elem" == "replaced" ]] || { echo "FAIL: elem='$elem' expected 'replaced'"; exit 1; }
[[ "${arr[0]}" == "replaced" ]] || { echo "FAIL: arr[0]='${arr[0]}' expected 'replaced'"; exit 1; }

# Second element must be untouched
json -v elem2 -a "${arr_[1]}"
json -v inner -a "${elem2_[label]}"
[[ "$inner" == "second" ]] || { echo "FAIL: inner='$inner' expected 'second'"; exit 1; }

exit 0
