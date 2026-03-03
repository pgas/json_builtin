#!/bin/bash
# Test: error handling
SO_PATH="$1"
enable -f "$SO_PATH" json

# Missing -v should fail
if json -j '{"a":1}' 2>/dev/null; then
  echo "FAIL: json without -v should fail"
  exit 1
fi

# Invalid JSON should fail
if json -v x -j 'not json' 2>/dev/null; then
  echo "FAIL: invalid JSON should fail"
  exit 1
fi

# Non-existent file should fail
if json -v x -f /tmp/nonexistent_json_test_file_xyz 2>/dev/null; then
  echo "FAIL: non-existent file should fail"
  exit 1
fi

# Invalid pointer should fail
if json -v x -a "0xdeadbeef" 2>/dev/null; then
  echo "FAIL: invalid pointer should fail"
  exit 1
fi

# Multiple sources should fail
if json -v x -j '{}' -f /dev/null 2>/dev/null; then
  echo "FAIL: multiple sources should fail"
  exit 1
fi

exit 0
