#!/bin/bash
# Test: -s selector with JSON Pointer (RFC 6901) on objects
SO_PATH="$1"
enable -f "$SO_PATH" json

json -v var -j '{
  "level1": {
    "level2": {
      "level3": {
        "value": "deep"
      }
    }
  }
}'

# Select level3 directly
json -v l3 -j '{
  "level1": {
    "level2": {
      "level3": {
        "value": "deep"
      }
    }
  }
}' -s '/level1/level2/level3'

[[ "${l3[value]}" == "deep" ]] || { echo "FAIL: l3[value]='${l3[value]}' expected 'deep'"; exit 1; }

# Select a scalar directly
json -v val -j '{"a": {"b": 42}}' -s '/a/b'
[[ "$val" == "42" ]] || { echo "FAIL: val='$val' expected '42'"; exit 1; }

# Select one level deep
json -v l2 -j '{"a": {"x": 1, "y": 2}}' -s '/a'
[[ "${l2[x]}" == "1" ]] || { echo "FAIL: l2[x]='${l2[x]}' expected '1'"; exit 1; }
[[ "${l2[y]}" == "2" ]] || { echo "FAIL: l2[y]='${l2[y]}' expected '2'"; exit 1; }

exit 0
