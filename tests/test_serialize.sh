#!/bin/bash
# Test: -S serializes bash variables to JSON; -P prints the result
SO_PATH="$1"
enable -f "$SO_PATH" json

# ── plain string ──────────────────────────────────────────────────────────────
varstr="hello world"
out=$(json -S varstr -P)
[[ "$out" == '"hello world"' ]] || { echo "FAIL: string: got '$out'"; exit 1; }

# ── integer attribute (declare -i) → JSON number ──────────────────────────────
declare -i varint=42
out=$(json -S varint -P)
[[ "$out" == "42" ]] || { echo "FAIL: integer: got '$out'"; exit 1; }

# ── indexed array → JSON array ────────────────────────────────────────────────
declare -a fruits=(apple banana cherry)
out=$(JSON_BASH_INDENT=-1 json -S fruits -P)
[[ "$out" == '["apple","banana","cherry"]' ]] || { echo "FAIL: indexed array: got '$out'"; exit 1; }

# ── indexed array with numeric strings preserved as numbers ───────────────────
declare -a nums=(1 2 3)
out=$(JSON_BASH_INDENT=-1 json -S nums -P)
[[ "$out" == '[1,2,3]' ]] || { echo "FAIL: numeric array: got '$out'"; exit 1; }

# ── associative array → JSON object ──────────────────────────────────────────
declare -A person=([name]=Alice [score]=99)
out=$(JSON_BASH_INDENT=-1 json -S person -P)
# key order may vary; check both keys are present
[[ "$out" == *'"name":"Alice"'* ]] || { echo "FAIL: assoc object name: got '$out'"; exit 1; }
[[ "$out" == *'"score":99'* ]]     || { echo "FAIL: assoc object score: got '$out'"; exit 1; }

# ── -S -v: serialize and store as a json variable ────────────────────────────
declare -a nums2=(10 20 30)
json -S nums2 -v stored
[[ "${stored[0]}" == "10" ]]  || { echo "FAIL: stored[0]: got '${stored[0]}'"; exit 1; }
[[ "${stored[1]}" == "20" ]]  || { echo "FAIL: stored[1]: got '${stored[1]}'"; exit 1; }
[[ "${stored[2]}" == "30" ]]  || { echo "FAIL: stored[2]: got '${stored[2]}'"; exit 1; }

# ── -S -v on an assoc array ───────────────────────────────────────────────────
declare -A meta=([env]=prod [version]=3)
json -S meta -v doc
[[ "${doc[env]}"     == "prod" ]] || { echo "FAIL: doc[env]: got '${doc[env]}'"; exit 1; }
[[ "${doc[version]}" == "3"    ]] || { echo "FAIL: doc[version]: got '${doc[version]}'"; exit 1; }

# ── -S with selector (-s) ────────────────────────────────────────────────────
declare -A nested=([data]='{"x":7}')
json -S nested -v ndoc
out=$(json -S nested -v ndoc -P)
# ndoc should be the object; ndoc[data] should be the nested json string
[[ "${ndoc[data]}" == *'7'* ]] || { echo "FAIL: selector-ready nested: '${ndoc[data]}'"; exit 1; }

# ── error: non-existent variable ─────────────────────────────────────────────
if json -S __no_such_var__ -P 2>/dev/null; then
  echo "FAIL: expected error for missing variable"
  exit 1
fi

# ── error: -S combined with -j ────────────────────────────────────────────────
if json -S varstr -j '{}' -P 2>/dev/null; then
  echo "FAIL: expected error for -S combined with -j"
  exit 1
fi

# ── -P only (no -v): just prints, no variable created ────────────────────────
declare -i count=7
json -S count -P >/dev/null
# 'count_json' should not be set (we never used -v)
[[ -z "${count_json+x}" ]] || { echo "FAIL: unexpected variable created"; exit 1; }

exit 0
