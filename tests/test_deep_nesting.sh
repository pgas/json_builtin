#!/bin/bash
# Test: deep nesting - navigate multiple levels
SO_PATH="$1"
enable -f "$SO_PATH" json

json -v root -j '{
  "level1": {
    "level2": {
      "level3": {
        "value": "deep"
      }
    }
  }
}'

# Navigate level by level
json -v l1 -a "${root_[level1]}"
json -v l2 -a "${l1_[level2]}"
json -v l3 -a "${l2_[level3]}"

[[ "${l3[value]}" == "deep" ]] || { echo "FAIL: l3[value]='${l3[value]}' expected 'deep'"; exit 1; }

exit 0
