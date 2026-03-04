#!/bin/bash
# Test: JSON Merge Patch (RFC 7396) — -m flag

SO_PATH="$1"
enable -f "$SO_PATH" json

# ── add / overwrite keys ──────────────────────────────────────────────────────
json -v result -j '{"a":1,"b":2}' -m '{"b":99,"c":3}'

[[ "${result[a]}" == "1"  ]] || { echo "FAIL: add-overwrite/a='${result[a]}' expected '1'"; exit 1; }
[[ "${result[b]}" == "99" ]] || { echo "FAIL: add-overwrite/b='${result[b]}' expected '99'"; exit 1; }
[[ "${result[c]}" == "3"  ]] || { echo "FAIL: add-overwrite/c='${result[c]}' expected '3'"; exit 1; }

# ── remove key with null value ────────────────────────────────────────────────
json -v result -j '{"keep":"yes","drop":"no"}' -m '{"drop":null}'

[[ "${result[keep]}" == "yes" ]] || { echo "FAIL: remove-null/keep='${result[keep]}' expected 'yes'"; exit 1; }
[[ -z "${result[drop]}" ]]       || { echo "FAIL: remove-null/drop='${result[drop]}' should be absent"; exit 1; }

# ── source can be empty object ────────────────────────────────────────────────
json -v result -j '{}' -m '{"x":42}'

[[ "${result[x]}" == "42" ]] || { echo "FAIL: empty-src/x='${result[x]}' expected '42'"; exit 1; }

# ── merge with empty patch — no change ───────────────────────────────────────
json -v result -j '{"a":1}' -m '{}'

[[ "${result[a]}" == "1" ]] || { echo "FAIL: empty-patch/a='${result[a]}' expected '1'"; exit 1; }

# ── merge patch supplied via pointer ─────────────────────────────────────────
json -v mpatch -j '{"score":100}'
json -v result -j '{"name":"Bob","score":0}' -m "${mpatch__}"

[[ "${result[name]}"  == "Bob" ]]  || { echo "FAIL: via-ptr/name='${result[name]}' expected 'Bob'"; exit 1; }
[[ "${result[score]}" == "100" ]] || { echo "FAIL: via-ptr/score='${result[score]}' expected '100'"; exit 1; }

# ── merge applied to -a pointer source ───────────────────────────────────────
json -v base -j '{"v":1}'
json -v result -a "${base__}" -m '{"v":2,"w":3}'

[[ "${result[v]}" == "2" ]] || { echo "FAIL: merge-on-a/v='${result[v]}' expected '2'"; exit 1; }
[[ "${result[w]}" == "3" ]] || { echo "FAIL: merge-on-a/w='${result[w]}' expected '3'"; exit 1; }

# original base should be unchanged
[[ "${base[v]}" == "1" ]] || { echo "FAIL: merge-on-a/base unchanged v='${base[v]}' expected '1'"; exit 1; }

# ── -s selector then merge ────────────────────────────────────────────────────
json -v result -j '{"inner":{"x":1,"y":2}}' \
     -s '/inner' \
     -m '{"y":null,"z":9}'

[[ "${result[x]}" == "1" ]] || { echo "FAIL: selector+merge/x='${result[x]}' expected '1'"; exit 1; }
[[ -z "${result[y]}" ]]     || { echo "FAIL: selector+merge/y='${result[y]}' should be absent"; exit 1; }
[[ "${result[z]}" == "9" ]] || { echo "FAIL: selector+merge/z='${result[z]}' expected '9'"; exit 1; }

# ── both -p and -m can be combined: patch first, then merge ──────────────────
json -v result -j '{"a":1,"b":2}' \
     -p '[{"op":"add","path":"/c","value":3}]' \
     -m '{"b":null}'

[[ "${result[a]}" == "1" ]] || { echo "FAIL: combined/a='${result[a]}' expected '1'"; exit 1; }
[[ -z "${result[b]}" ]]     || { echo "FAIL: combined/b='${result[b]}' should be absent"; exit 1; }
[[ "${result[c]}" == "3" ]] || { echo "FAIL: combined/c='${result[c]}' expected '3'"; exit 1; }

exit 0
