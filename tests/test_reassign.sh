#!/bin/bash
# Test: re-assignment overwrites previous variable
SO_PATH="$1"
enable -f "$SO_PATH" json

# First assignment
json -v x -j '{"a": "1", "b": "2"}'
[[ "${x[a]}" == "1" ]] || { echo "FAIL: x[a]='${x[a]}' expected '1'"; exit 1; }

# Second assignment to same variable
json -v x -j '{"c": "3", "d": "4"}'
[[ "${x[c]}" == "3" ]] || { echo "FAIL: x[c]='${x[c]}' expected '3'"; exit 1; }
[[ "${x[d]}" == "4" ]] || { echo "FAIL: x[d]='${x[d]}' expected '4'"; exit 1; }

# Old keys should NOT exist
[[ -z "${x[a]+isset}" ]] || { echo "FAIL: x[a] should not exist after reassignment, got '${x[a]}'"; exit 1; }

exit 0
