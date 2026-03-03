#!/bin/bash
# Test: reading JSON from a file with -f
SO_PATH="$1"
enable -f "$SO_PATH" json

TMPFILE=$(mktemp /tmp/json_test_XXXXXX.json)
trap "rm -f '$TMPFILE'" EXIT

cat > "$TMPFILE" <<'EOF'
{
  "city": "Paris",
  "country": "France",
  "population": 2161000
}
EOF

json -v geo -f "$TMPFILE"

[[ "${geo[city]}" == "Paris" ]] || { echo "FAIL: geo[city]='${geo[city]}' expected 'Paris'"; exit 1; }
[[ "${geo[country]}" == "France" ]] || { echo "FAIL: geo[country]='${geo[country]}' expected 'France'"; exit 1; }
[[ "${geo[population]}" == "2161000" ]] || { echo "FAIL: geo[population]='${geo[population]}' expected '2161000'"; exit 1; }

exit 0
