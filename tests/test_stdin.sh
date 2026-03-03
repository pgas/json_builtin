#!/bin/bash
# Test: reading JSON from stdin (here-string)
SO_PATH="$1"
enable -f "$SO_PATH" json

json -v info <<< '{"tool": "bash", "version": 5}'

[[ "${info[tool]}" == "bash" ]] || { echo "FAIL: info[tool]='${info[tool]}' expected 'bash'"; exit 1; }
[[ "${info[version]}" == "5" ]] || { echo "FAIL: info[version]='${info[version]}' expected '5'"; exit 1; }

exit 0
