#!/bin/bash
# Test: JSON Patch (RFC 6902) — -p flag

SO_PATH="$1"
enable -f "$SO_PATH" json

# ── add operation ──────────────────────────────────────────────────────────────
json -v result -j '{"a":1}' \
     -p '[{"op":"add","path":"/b","value":2}]'

[[ "${result[a]}" == "1" ]] || { echo "FAIL: add/a='${result[a]}' expected '1'"; exit 1; }
[[ "${result[b]}" == "2" ]] || { echo "FAIL: add/b='${result[b]}' expected '2'"; exit 1; }

# ── remove operation ──────────────────────────────────────────────────────────
json -v result -j '{"x":10,"y":20}' \
     -p '[{"op":"remove","path":"/y"}]'

[[ "${result[x]}" == "10" ]] || { echo "FAIL: remove/x='${result[x]}' expected '10'"; exit 1; }
[[ -z "${result[y]}" ]]      || { echo "FAIL: remove/y='${result[y]}' should be absent"; exit 1; }

# ── replace operation ─────────────────────────────────────────────────────────
json -v result -j '{"name":"Alice","score":0}' \
     -p '[{"op":"replace","path":"/score","value":99}]'

[[ "${result[name]}"  == "Alice" ]] || { echo "FAIL: replace/name='${result[name]}'"; exit 1; }
[[ "${result[score]}" == "99" ]]    || { echo "FAIL: replace/score='${result[score]}' expected '99'"; exit 1; }

# ── move operation ────────────────────────────────────────────────────────────
json -v result -j '{"a":{"b":42}}' \
     -p '[{"op":"move","from":"/a/b","path":"/c"}]'

[[ "${result[c]}" == "42" ]] || { echo "FAIL: move/c='${result[c]}' expected '42'"; exit 1; }

# ── copy operation ────────────────────────────────────────────────────────────
json -v result -j '{"src":7}' \
     -p '[{"op":"copy","from":"/src","path":"/dst"}]'

[[ "${result[src]}" == "7" ]] || { echo "FAIL: copy/src='${result[src]}' expected '7'"; exit 1; }
[[ "${result[dst]}" == "7" ]] || { echo "FAIL: copy/dst='${result[dst]}' expected '7'"; exit 1; }

# ── test operation (passes) ───────────────────────────────────────────────────
json -v result -j '{"val":"ok"}' \
     -p '[{"op":"test","path":"/val","value":"ok"},{"op":"add","path":"/done","value":true}]'

[[ "${result[done]}" == "true" ]] || { echo "FAIL: test-op/done='${result[done]}' expected 'true'"; exit 1; }

# ── test operation (fails) → json patch error ─────────────────────────────────
if json -v bad -j '{"val":"ok"}' \
        -p '[{"op":"test","path":"/val","value":"wrong"}]' 2>/dev/null; then
  echo "FAIL: test-fail should have returned EXECUTION_FAILURE"
  exit 1
fi

# ── patch supplied via pointer ────────────────────────────────────────────────
json -v patch -j '[{"op":"add","path":"/z","value":99}]'
json -v result -j '{"z":0}' -p "${patch__}"

[[ "${result[z]}" == "99" ]] || { echo "FAIL: patch-via-ptr/z='${result[z]}' expected '99'"; exit 1; }

# ── patch applied to -a pointer source ───────────────────────────────────────
json -v base -j '{"n":1}'
json -v result -a "${base__}" -p '[{"op":"replace","path":"/n","value":42}]'

[[ "${result[n]}" == "42" ]] || { echo "FAIL: patch-on-a/n='${result[n]}' expected '42'"; exit 1; }

# original base should be unchanged (deep copy)
[[ "${base[n]}" == "1" ]] || { echo "FAIL: patch-on-a/base unchanged n='${base[n]}' expected '1'"; exit 1; }

# ── -s selector then patch ────────────────────────────────────────────────────
json -v result -j '{"inner":{"v":5}}' \
     -s '/inner' \
     -p '[{"op":"replace","path":"/v","value":99}]'

[[ "${result[v]}" == "99" ]] || { echo "FAIL: selector+patch/v='${result[v]}' expected '99'"; exit 1; }

exit 0
