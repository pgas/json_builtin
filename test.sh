#!/bin/bash
# Test harness for the json bash builtin
# Usage: bash test.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SO_PATH="$ROOT_DIR/build/src/json.so"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
TOTAL=0

# Run a single test script in a subshell
run_test() {
  local test_name="$1"
  local test_file="$2"
  TOTAL=$((TOTAL + 1))
  printf "${YELLOW}[%d] %-40s${NC} " "$TOTAL" "$test_name"

  local output
  if output=$(bash "$test_file" "$SO_PATH" 2>&1); then
    printf "${GREEN}PASS${NC}\n"
    PASS=$((PASS + 1))
  else
    printf "${RED}FAIL${NC}\n"
    echo "$output" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
  fi
}

echo "JSON Bash Builtin Test Suite"
echo "============================"
echo

# Check if json.so exists
if [ ! -f "$SO_PATH" ]; then
  echo -e "${RED}Error: json.so not found at $SO_PATH${NC}"
  echo "  Build first: cd build && cmake .. -DBASH_HEADERS=/home/pgas/proj && ninja"
  exit 1
fi

# Run all test scripts
for t in "$ROOT_DIR"/tests/test_*.sh; do
  test_name=$(basename "$t" .sh)
  test_name=${test_name#test_}
  run_test "$test_name" "$t"
done

echo
echo "============================"
printf "Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}, %d total\n" "$PASS" "$FAIL" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
