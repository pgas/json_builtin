#!/bin/bash
# Test: -s selector error cases
SO_PATH="$1"
enable -f "$SO_PATH" json

# Invalid path (key doesn't exist) should fail
if json -v x -j '{"a": 1}' -s '/nonexistent' 2>/dev/null; then
  echo "FAIL: nonexistent key should fail"
  exit 1
fi

# Array out of bounds should fail
if json -v x -j '[1, 2]' -s '/5' 2>/dev/null; then
  echo "FAIL: out-of-bounds index should fail"
  exit 1
fi

# Invalid JSON Pointer syntax should fail
if json -v x -j '{"a": 1}' -s 'no-leading-slash' 2>/dev/null; then
  echo "FAIL: invalid JSON Pointer syntax should fail"
  exit 1
fi

exit 0
