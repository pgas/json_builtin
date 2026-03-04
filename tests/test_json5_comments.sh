#!/bin/bash
# Test: JSON5 comment stripping (// and /* */ style)
SO_PATH="$1"
enable -f "$SO_PATH" json

# Single-line comments (//)
json -v obj -j '{
  // this is a comment
  "name": "Alice",
  "age": 30  // inline comment
}'

[[ "${obj[name]}" == "Alice" ]] || { echo "FAIL: obj[name]='${obj[name]}' expected 'Alice'"; exit 1; }
[[ "${obj[age]}" == "30" ]] || { echo "FAIL: obj[age]='${obj[age]}' expected '30'"; exit 1; }

# Block comments (/* */)
json -v obj2 -j '{
  /* block comment */
  "x": 1,
  /* another
     multi-line
     block comment */
  "y": 2
}'

[[ "${obj2[x]}" == "1" ]] || { echo "FAIL: obj2[x]='${obj2[x]}' expected '1'"; exit 1; }
[[ "${obj2[y]}" == "2" ]] || { echo "FAIL: obj2[y]='${obj2[y]}' expected '2'"; exit 1; }

# Comments in a file
TMPFILE=$(mktemp /tmp/test_json5_XXXXXX.json)
cat > "$TMPFILE" << 'EOF'
{
  // config file with comments
  "host": "localhost",
  "port": 8080, /* default port */
  "debug": false
}
EOF

json -v cfg -f "$TMPFILE"
rm -f "$TMPFILE"

[[ "${cfg[host]}" == "localhost" ]] || { echo "FAIL: cfg[host]='${cfg[host]}' expected 'localhost'"; exit 1; }
[[ "${cfg[port]}" == "8080" ]] || { echo "FAIL: cfg[port]='${cfg[port]}' expected '8080'"; exit 1; }
[[ "${cfg[debug]}" == "false" ]] || { echo "FAIL: cfg[debug]='${cfg[debug]}' expected 'false'"; exit 1; }

exit 0
