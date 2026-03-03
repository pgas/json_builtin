#!/bin/bash
# Test: pointer to scalar creates simple variable
SO_PATH="$1"
enable -f "$SO_PATH" json

json -v data -j '{"name": "John", "age": 30}'

# Extract a scalar via pointer
json -v myname -a "${data_[name]}"

# myname should be a simple scalar variable, not an assoc array
[[ "$myname" == "John" ]] || { echo "FAIL: myname='$myname' expected 'John'"; exit 1; }

# The pointer variable myname_ should also exist
[[ -n "$myname_" ]] || { echo "FAIL: myname_ is empty"; exit 1; }

# Extract a number
json -v myage -a "${data_[age]}"
[[ "$myage" == "30" ]] || { echo "FAIL: myage='$myage' expected '30'"; exit 1; }

exit 0
