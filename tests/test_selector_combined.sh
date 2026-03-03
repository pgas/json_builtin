#!/bin/bash
# Test: -s selector combined with -a (pointer) and -f (file)
SO_PATH="$1"
enable -f "$SO_PATH" json

# First parse the full object
json -v data -j '{"config": {"db": {"host": "localhost", "port": 5432}}}'

# Use -a with -s to select from an existing pointer
json -v db -a "${data_[config]}" -s '/db'
[[ "${db[host]}" == "localhost" ]] || { echo "FAIL: db[host]='${db[host]}' expected 'localhost'"; exit 1; }
[[ "${db[port]}" == "5432" ]] || { echo "FAIL: db[port]='${db[port]}' expected '5432'"; exit 1; }

# Use -s with -f (file)
TMPFILE=$(mktemp /tmp/json_test_XXXXXX.json)
trap "rm -f '$TMPFILE'" EXIT
cat > "$TMPFILE" <<'EOF'
{"data": {"items": [10, 20, 30]}}
EOF

json -v items -f "$TMPFILE" -s '/data/items'
[[ "${items[0]}" == "10" ]] || { echo "FAIL: items[0]='${items[0]}' expected '10'"; exit 1; }
[[ "${items[2]}" == "30" ]] || { echo "FAIL: items[2]='${items[2]}' expected '30'"; exit 1; }

# Use -s with stdin
json -v val -s '/a/b' <<< '{"a": {"b": "hello"}}'
[[ "$val" == "hello" ]] || { echo "FAIL: val='$val' expected 'hello'"; exit 1; }

exit 0
