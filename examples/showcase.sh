#!/bin/bash
# ============================================================
# json_builtin interactive showcase
# Demonstrates each feature one screen at a time.
# Press any key to advance, q to quit.
# Usage: bash examples/showcase.sh [path/to/json.so]
# ============================================================

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SO_PATH="${1:-$ROOT_DIR/build/src/json.so}"

# ── terminal colours ──────────────────────────────────────
BOLD='\033[1m';  DIM='\033[2m';   RESET='\033[0m'
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'
BLUE='\033[34m'; RED='\033[31m';   MAGENTA='\033[35m'

TOTAL_STEPS=12   # update when adding steps

# ── helpers ───────────────────────────────────────────────

# Print a 78-char horizontal rule
hr() { printf "${DIM}%s${RESET}\n" "$(printf '─%.0s' {1..78})"; }

# Print the header bar for each step
header() {
  local title="$1" step="$2"
  clear
  printf "${BOLD}${CYAN}  json_builtin showcase${RESET}"
  printf "  ${DIM}step %d/%d${RESET}  " "$step" "$TOTAL_STEPS"
  printf "${BOLD}%s${RESET}\n" "$title"
  hr
}

# Wait for a keypress; return 1 if user pressed q/Q
wait_key() {
  hr
  printf "${DIM}  [any key] continue   [q] quit${RESET}  "
  local key
  IFS= read -r -s -n1 key
  echo
  [[ "$key" == "q" || "$key" == "Q" ]] && return 1
  return 0
}

# Show a labelled command then its output (indented)
run_show() {
  local label="$1"; shift
  printf "${YELLOW}  \$${RESET} ${GREEN}%s${RESET}\n" "$label"
  local out
  out=$( "$@" 2>&1 ) || true
  if [[ -n "$out" ]]; then
    while IFS= read -r line; do
      printf "    %s\n" "$line"
    done <<< "$out"
  fi
}

# Emit a comment line
comment() { printf "${DIM}  # %s${RESET}\n" "$1"; }
# Emit a blank separator
blank() { echo; }

# ── guard ─────────────────────────────────────────────────

if [[ ! -f "$SO_PATH" ]]; then
  echo "Error: json.so not found at $SO_PATH"
  echo "Build first:  cd build && cmake .. -DBASH_HEADERS=... && ninja"
  exit 1
fi

enable -f "$SO_PATH" json

# ══════════════════════════════════════════════════════════
# STEP 1 — Introduction
# ══════════════════════════════════════════════════════════
step1() {
  header "Introduction" 1
  blank
  printf "  ${BOLD}json_builtin${RESET} is a dynamically-loadable bash builtin that\n"
  printf "  parses JSON and materialises it as native bash variables.\n"
  blank
  comment "Load the builtin from the compiled .so"
  printf "  ${YELLOW}\$${RESET} ${GREEN}enable -f ./build/src/json.so json${RESET}\n"
  blank
  comment "Basic syntax"
  printf "  ${YELLOW}\$${RESET} ${GREEN}json -v VARNAME [-j JSON | -f FILE | -a PTR] [-s /path]${RESET}\n"
  blank
  printf "  Each call creates ${BOLD}two${RESET} bash variables:\n"
  printf "    ${CYAN}VARNAME${RESET}   — display values  (assoc/indexed array or scalar)\n"
  printf "    ${CYAN}VARNAME_${RESET}  — JSON pointers   (hex addresses for re-navigation)\n"
  blank
  printf "  JSON type mapping:\n"
  printf "    object  ${DIM}→${RESET}  associative array\n"
  printf "    array   ${DIM}→${RESET}  indexed array\n"
  printf "    scalar  ${DIM}→${RESET}  simple variable\n"
}

# ══════════════════════════════════════════════════════════
# STEP 2 — Parsing a JSON object
# ══════════════════════════════════════════════════════════
step2() {
  header "Parsing a JSON object" 2
  blank
  comment "Parse a JSON object; creates cfg and cfg_ associative arrays"

  json -v cfg -j '{"host":"localhost","port":8080,"debug":false}'

  run_show 'json -v cfg -j '"'"'{"host":"localhost","port":8080,"debug":false}'"'"'' \
           true   # already executed above; just show the command

  blank
  comment "Access individual keys"
  run_show 'echo "host  = ${cfg[host]}"'  bash -c "
    enable -f '$SO_PATH' json
    json -v cfg -j '{\"host\":\"localhost\",\"port\":8080,\"debug\":false}'
    echo \"host  = \${cfg[host]}\"
    echo \"port  = \${cfg[port]}\"
    echo \"debug = \${cfg[debug]}\""
  blank
  comment "Iterate all keys"
  run_show 'for k in "${!cfg[@]}"; do echo "$k = ${cfg[$k]}"; done' \
           bash -c "
    enable -f '$SO_PATH' json
    json -v cfg -j '{\"host\":\"localhost\",\"port\":8080,\"debug\":false}'
    for k in \"\${!cfg[@]}\"; do echo \"\$k = \${cfg[\$k]}\"; done"
}

# ══════════════════════════════════════════════════════════
# STEP 3 — JSON arrays
# ══════════════════════════════════════════════════════════
step3() {
  header "JSON arrays  →  indexed arrays" 3
  blank
  comment "Parse a JSON array"
  run_show 'json -v fruits -j '"'"'["apple","banana","cherry"]'"'"'' \
           bash -c "
    enable -f '$SO_PATH' json
    json -v fruits -j '[\"apple\",\"banana\",\"cherry\"]'
    echo \"fruits[0] = \${fruits[0]}\"
    echo \"fruits[1] = \${fruits[1]}\"
    echo \"fruits[2] = \${fruits[2]}\"
    echo \"length    = \${#fruits[@]}\""
  blank
  comment "Array of objects — each element is a JSON sub-object"
  run_show 'json -v users -j '"'"'[{"name":"Alice"},{"name":"Bob"}]'"'"'' \
           bash -c "
    enable -f '$SO_PATH' json
    json -v users -j '[{\"name\":\"Alice\",\"age\":30},{\"name\":\"Bob\",\"age\":25}]'
    echo \"users[0] = \${users[0]}\"
    echo \"users[1] = \${users[1]}\""
  blank
  comment "Use the pointer variable to navigate into an element"
  run_show 'json -v u0 -a "${users_[0]}"; echo "${u0[name]}"' \
           bash -c "
    enable -f '$SO_PATH' json
    json -v users -j '[{\"name\":\"Alice\",\"age\":30},{\"name\":\"Bob\",\"age\":25}]'
    json -v u0 -a \"\${users_[0]}\"
    echo \"u0[name] = \${u0[name]}, u0[age] = \${u0[age]}\""
}

# ══════════════════════════════════════════════════════════
# STEP 4 — Deep nesting with pointer navigation
# ══════════════════════════════════════════════════════════
step4() {
  header "Deep nesting with pointer navigation" 4
  blank
  local JSON='{"org":{"dept":{"team":{"lead":"Carol","size":4}}}}'
  comment "Parse a deeply-nested object"
  run_show "json -v doc -j '$JSON'" bash -c "
    enable -f '$SO_PATH' json
    json -v doc -j '$JSON'
    echo \"doc[org] = \${doc[org]}\""
  blank
  comment "Navigate level-by-level using pointer variables"
  run_show 'json -v org  -a "${doc_[org]}"
  json -v dept -a "${org_[dept]}"
  json -v team -a "${dept_[team]}"
  echo "${team[lead]}  (size=${team[size]})"' \
           bash -c "
    enable -f '$SO_PATH' json
    json -v doc  -j '$JSON'
    json -v org  -a \"\${doc_[org]}\"
    json -v dept -a \"\${org_[dept]}\"
    json -v team -a \"\${dept_[team]}\"
    echo \"lead = \${team[lead]}, size = \${team[size]}\""
}

# ══════════════════════════════════════════════════════════
# STEP 5 — JSON Pointer selectors (-s)
# ══════════════════════════════════════════════════════════
step5() {
  header "JSON Pointer selectors  (-s,  RFC 6901)" 5
  blank
  comment "Jump straight to a nested value in one command"
  run_show 'json -v team -j '"'"'{"org":{"dept":{"team":{"lead":"Carol"}}}}'"'"' \
       -s /org/dept/team' \
           bash -c "
    enable -f '$SO_PATH' json
    json -v team -j '{\"org\":{\"dept\":{\"team\":{\"lead\":\"Carol\",\"size\":4}}}}' \
         -s /org/dept/team
    echo \"lead = \${team[lead]}, size = \${team[size]}\""
  blank
  comment "Selectors work on arrays too"
  run_show 'json -v name -j '"'"'{"users":[{"name":"Alice"},{"name":"Bob"}]}'"'"' \
       -s /users/1/name' \
           bash -c "
    enable -f '$SO_PATH' json
    json -v name -j '{\"users\":[{\"name\":\"Alice\"},{\"name\":\"Bob\"}]}' \
         -s /users/1/name
    echo \"name = \$name\""
  blank
  comment "Also usable after -a to sub-select from an existing pointer"
  run_show 'json -v data -j '"'"'{"a":{"b":{"c":42}}}'"'"'
  json -v result -a "${data_[a]}" -s /b/c
  echo "$result"' \
           bash -c "
    enable -f '$SO_PATH' json
    json -v data -j '{\"a\":{\"b\":{\"c\":42}}}'
    json -v result -a \"\${data_[a]}\" -s /b/c
    echo \"result = \$result\""
}

# ══════════════════════════════════════════════════════════
# STEP 6 — Reading from a file with JSON5 comments
# ══════════════════════════════════════════════════════════
step6() {
  header "File input  &  JSON5 comment stripping" 6
  blank
  local TMP
  TMP=$(mktemp /tmp/showcase_cfg_XXXXXX.json)
  cat > "$TMP" << 'EOF'
{
  // application config (JSON5-style comments allowed)
  "service": "api-gateway",
  "port": 9090,       /* default port */
  "tls": true,
  "workers": 4        // CPU count
}
EOF
  comment "Config file with // and /* */ comments:"
  printf "    ${DIM}%s${RESET}\n" "$(cat "$TMP")"
  blank
  comment "json strips comments automatically with -f"
  run_show "json -v cfg -f $TMP" bash -c "
    enable -f '$SO_PATH' json
    json -v cfg -f '$TMP'
    echo \"service = \${cfg[service]}\"
    echo \"port    = \${cfg[port]}\"
    echo \"tls     = \${cfg[tls]}\"
    echo \"workers = \${cfg[workers]}\""
  rm -f "$TMP"
}

# ══════════════════════════════════════════════════════════
# STEP 7 — Assignment callbacks: var[key]=value
# ══════════════════════════════════════════════════════════
step7() {
  header "Assignment callbacks  —  var[key]=value" 7
  blank
  comment "Parse an object and then mutate it via ordinary bash assignment"
  run_show 'json -v p -j '"'"'{"name":"Alice","score":0}'"'"'
  p[score]=42          # updates JSON in-place
  p[rank]="gold"       # new key (JSON object extended)
  echo "${p[name]}  score=${p[score]}  rank=${p[rank]}"' \
           bash -c "
    enable -f '$SO_PATH' json
    json -v p -j '{\"name\":\"Alice\",\"score\":0}'
    p[score]=42
    p[rank]=\"gold\"
    echo \"\${p[name]}  score=\${p[score]}  rank=\${p[rank]}\""
  blank
  comment "The companion pointer variable is kept in sync automatically"
  run_show 'json -v score_val -a "${p_[score]}"
  echo "score (via pointer) = $score_val"' \
           bash -c "
    enable -f '$SO_PATH' json
    json -v p -j '{\"name\":\"Alice\",\"score\":0}'
    p[score]=42
    json -v score_val -a \"\${p_[score]}\"
    echo \"score via pointer = \$score_val\""
  blank
  comment "Arrays work the same way"
  run_show 'json -v arr -j '"'"'[10,20,30]'"'"'; arr[1]=99
  echo "${arr[@]}"' \
           bash -c "
    enable -f '$SO_PATH' json
    json -v arr -j '[10,20,30]'
    arr[1]=99
    echo \"\${arr[@]}\""
}

# ══════════════════════════════════════════════════════════
# STEP 8 — Pointer assignment: var_[key]=ptr
# ══════════════════════════════════════════════════════════
step8() {
  header "Pointer assignment  —  var_[key]=ptr" 8
  blank
  comment "Build a patch object, then splice it into another object"
  run_show 'json -v patch -j '"'"'{"status":"active","role":"admin"}'"'"'
  json -v user  -j '"'"'{"name":"Bob","meta":{"status":"pending"}}'"'"'

  # Replace sub-object: deep-copy patch into user.meta via pointer slot
  user_[meta]="${patch_[status]}"    # splices scalar "active" into meta
  echo "meta now = ${user[meta]}"' \
           bash -c "
    enable -f '$SO_PATH' json
    json -v patch -j '{\"status\":\"active\",\"role\":\"admin\"}'
    json -v user  -j '{\"name\":\"Bob\",\"meta\":{\"status\":\"pending\",\"role\":\"guest\"}}'
    user_[meta]=\"\${patch_[status]}\"
    echo \"user[meta] = \${user[meta]}\"
    json -v meta -a \"\${user_[meta]}\"
    echo \"meta (via ptr) = \$meta\""
}

# ══════════════════════════════════════════════════════════
# STEP 9 — Display formatting: JSON_BASH_INDENT / JSON_BASH_ENSURE_ASCII
# ══════════════════════════════════════════════════════════
step9() {
  header "Display formatting  —  JSON_BASH_XXX variables" 9
  blank
  comment "Default indent = 2 spaces"
  run_show 'json -v obj -j '"'"'{"a":{"b":1}}'"'"'; echo "${obj[a]}"' \
           bash -c "
    enable -f '$SO_PATH' json
    json -v obj -j '{\"a\":{\"b\":1}}'
    echo \"\${obj[a]}\""
  blank
  comment "JSON_BASH_INDENT=-1  →  compact / single-line"
  run_show 'JSON_BASH_INDENT=-1  json -v obj2 -j '"'"'{"a":{"b":1}}'"'"'
  echo "${obj2[a]}"' \
           bash -c "
    enable -f '$SO_PATH' json
    JSON_BASH_INDENT=-1 json -v obj2 -j '{\"a\":{\"b\":1}}'
    echo \"\${obj2[a]}\""
  blank
  comment "JSON_BASH_INDENT=4  →  4-space indent"
  run_show 'JSON_BASH_INDENT=4  json -v obj3 -j '"'"'{"a":{"b":1}}'"'"'
  echo "${obj3[a]}"' \
           bash -c "
    enable -f '$SO_PATH' json
    JSON_BASH_INDENT=4 json -v obj3 -j '{\"a\":{\"b\":1}}'
    echo \"\${obj3[a]}\""
  blank
  comment "JSON_BASH_ENSURE_ASCII=1  →  escape non-ASCII chars"
  run_show 'JSON_BASH_ENSURE_ASCII=1  json -v s -j '"'"'"café"'"'"'
  echo "$s"' \
           bash -c "
    enable -f '$SO_PATH' json
    JSON_BASH_ENSURE_ASCII=1 json -v s -j '\"caf\u00e9\"'
    echo \"\$s\""
}

# ══════════════════════════════════════════════════════════
# STEP 10 — Real-world pattern: process API response
# ══════════════════════════════════════════════════════════
step10() {
  header "Real-world pattern  —  process a response payload" 10
  blank
  comment "Simulate an API response with a users list"
  run_show 'json -v resp -j '"'"'{"status":"ok","users":[
    {"name":"Alice","role":"admin"},
    {"name":"Bob",  "role":"user"},
    {"name":"Carol","role":"user"}]}'"'"'' true
  blank
  comment "Navigate to the users array, then iterate"
  run_show 'json -v users -a "${resp_[users]}"
  for i in "${!users[@]}"; do
    json -v u -a "${users_[$i]}"
    printf "  [%d] %-8s %s\n" "$i" "${u[name]}" "${u[role]}"
  done' \
           bash -c "
    enable -f '$SO_PATH' json
    json -v resp -j '{\"status\":\"ok\",\"users\":[
      {\"name\":\"Alice\",\"role\":\"admin\"},
      {\"name\":\"Bob\",\"role\":\"user\"},
      {\"name\":\"Carol\",\"role\":\"user\"}]}'
    json -v users -a \"\${resp_[users]}\"
    for i in \"\${!users[@]}\"; do
      json -v u -a \"\${users_[\$i]}\"
      printf \"  [%d] %-8s %s\n\" \"\$i\" \"\${u[name]}\" \"\${u[role]}\"
    done"
  blank
  printf "  ${BOLD}${GREEN}Press any key for JSON Patch / Merge Patch …${RESET}\n"
}

step12() {
  header "Serializing bash variables to JSON  (-S, -P)" 12
  blank
  comment "Serialize a plain string"
  run_show 'mystr="hello world"
  json -S mystr -P' \
           bash -c "
    enable -f '$SO_PATH' json
    mystr='hello world'
    json -S mystr -P"
  blank
  comment "Serialize a declare -i integer  →  JSON number"
  run_show 'declare -i count=42
  json -S count -P' \
           bash -c "
    enable -f '$SO_PATH' json
    declare -i count=42
    json -S count -P"
  blank
  comment "Serialize an indexed array  →  JSON array"
  run_show 'declare -a colors=(red green blue)
  json -S colors -P' \
           bash -c "
    enable -f '$SO_PATH' json
    declare -a colors=(red green blue)
    json -S colors -P"
  blank
  comment "Serialize an associative array  →  JSON object"
  run_show 'declare -A person=([name]=Alice [score]=99)
  json -S person -P' \
           bash -c "
    enable -f '$SO_PATH' json
    declare -A person=([name]=Alice [score]=99)
    json -S person -P"
  blank
  comment "Store serialized output as a live json variable (-v) for further use"
  run_show 'declare -A cfg=([host]=localhost [port]=8080)
  json -S cfg -v doc -P
  echo \"port via var: \${doc[port]}\"' \
           bash -c "
    enable -f '$SO_PATH' json
    declare -A cfg=([host]=localhost [port]=8080)
    json -S cfg -v doc -P
    echo \"port via var: \${doc[port]}\""
  blank
  comment "-S is composable with -s, -p, -m exactly like other sources"
  run_show 'declare -A data=([x]=1 [y]=2)
  json -S data -v result -m '\''\'''{\"z\":3}'\'\'''\'' -P' \
           bash -c "
    enable -f '$SO_PATH' json
    declare -A data=([x]=1 [y]=2)
    json -S data -v result -m '{\"z\":3}' -P"
  printf "  ${BOLD}${GREEN}End of showcase.${RESET}  See README.md for full documentation.\n"

}

step11() {
  header "JSON Patch (RFC 6902) & JSON Merge Patch (RFC 7396)" 11
  blank
  comment "-p applies an array of patch operations (add / remove / replace …)"
  run_show 'json -v doc -j '"'"'{"a":1,"b":2,"c":3}'"'"'
  json -v doc -a "${doc__}" \
    -p '"'"'[{"op":"replace","path":"/a","value":99},{"op":"remove","path":"/c"}]'"'"'
  echo "a=${doc[a]}  b=${doc[b]}  c='"'"'${doc[c]}'"'"'"' \
       bash -c "
  enable -f '$SO_PATH' json
  json -v doc -j '{\"a\":1,\"b\":2,\"c\":3}'
  json -v doc -a \"\${doc__}\" \
    -p '[{\"op\":\"replace\",\"path\":\"/a\",\"value\":99},{\"op\":\"remove\",\"path\":\"/c\"}]'
  echo \"a=\${doc[a]}  b=\${doc[b]}  c='\${doc[c]}'\""
  blank
  comment "-m merges: present keys overwrite, null keys remove"
  run_show 'json -v doc -j '"'"'{"a":1,"b":2,"keep":"yes"}'"'"'
  json -v doc -a "${doc__}" -m '"'"'{"b":null,"c":3}'"'"'
  echo "a=${doc[a]}  b='"'"'${doc[b]}'"'"'  c=${doc[c]}  keep=${doc[keep]}"' \
       bash -c "
  enable -f '$SO_PATH' json
  json -v doc -j '{\"a\":1,\"b\":2,\"keep\":\"yes\"}'
  json -v doc -a \"\${doc__}\" -m '{\"b\":null,\"c\":3}'
  echo \"a=\${doc[a]}  b='\${doc[b]}'  c=\${doc[c]}  keep=\${doc[keep]}\""
  blank
  comment "-p and -m chain: patch runs first, then merge"
  run_show 'json -v doc -j '"'"'{"a":0,"rem":"bye"}'"'"'
  json -v doc -a "${doc__}" \
    -p '"'"'[{"op":"replace","path":"/a","value":7}]'"'"' \
    -m '"'"'{"rem":null,"new":"hi"}'"'"'
  echo "a=${doc[a]}  rem='"'"'${doc[rem]}'"'"'  new=${doc[new]}"' \
       bash -c "
  enable -f '$SO_PATH' json
  json -v doc -j '{\"a\":0,\"rem\":\"bye\"}'
  json -v doc -a \"\${doc__}\" \
    -p '[{\"op\":\"replace\",\"path\":\"/a\",\"value\":7}]' \
    -m '{\"rem\":null,\"new\":\"hi\"}'
  echo \"a=\${doc[a]}  rem='\${doc[rem]}'  new=\${doc[new]}\""
  blank
}

# ══════════════════════════════════════════════════════════
# Main loop
# ══════════════════════════════════════════════════════════
STEPS=(step1 step2 step3 step4 step5 step6 step7 step8 step9 step10 step11 step12)

for step_fn in "${STEPS[@]}"; do
  "$step_fn"
  wait_key || { clear; echo "Goodbye."; exit 0; }
done

clear
echo "Showcase complete."
