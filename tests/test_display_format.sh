#!/bin/bash
# Test: JSON_BASH_XXX variables for display formatting
SO_PATH="$1"
enable -f "$SO_PATH" json

# Default indent is 2
json -v obj -j '{"a":{"b":1}}'
# Display for nested object should contain two-space indentation
echo "${obj[a]}" | grep -q '  "b"' || { echo "FAIL: default indent=2 not found in '${obj[a]}'"; exit 1; }

# JSON_BASH_INDENT=-1 produces compact output
JSON_BASH_INDENT=-1
json -v obj2 -j '{"a":{"b":1}}'
# Compact: the nested display value must not contain any embedded newlines
if [[ "${obj2[a]}" == *$'\n'* ]]; then
  echo "FAIL: JSON_BASH_INDENT=-1 produced multi-line output: '${obj2[a]}'"
  exit 1
fi
unset JSON_BASH_INDENT

# JSON_BASH_INDENT=4 produces 4-space indentation
JSON_BASH_INDENT=4
json -v obj3 -j '{"a":{"b":1}}'
echo "${obj3[a]}" | grep -q '    "b"' || { echo "FAIL: indent=4 not found in '${obj3[a]}'"; exit 1; }
unset JSON_BASH_INDENT

# JSON_BASH_ENSURE_ASCII=1 escapes non-ASCII characters
JSON_BASH_ENSURE_ASCII=1
json -v scalar -j '"café"'
# The display should NOT contain the raw é character
if [[ "${scalar}" == *"é"* ]]; then
  echo "FAIL: ensure_ascii=1 did not escape 'é' in '${scalar}'"
  exit 1
fi
unset JSON_BASH_ENSURE_ASCII

# Without ensure_ascii (default 0) non-ASCII is preserved
json -v scalar2 -j '"café"'
[[ "${scalar2}" == "café" ]] || { echo "FAIL: scalar2='${scalar2}' expected 'café'"; exit 1; }

exit 0
