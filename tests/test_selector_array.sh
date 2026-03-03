#!/bin/bash
# Test: -s selector with arrays and mixed paths
SO_PATH="$1"
enable -f "$SO_PATH" json

# Select an array element by index
json -v val -j '["a", "b", "c"]' -s '/1'
[[ "$val" == "b" ]] || { echo "FAIL: val='$val' expected 'b'"; exit 1; }

# Select from array of objects
json -v user -j '[{"name": "Alice"}, {"name": "Bob"}]' -s '/1'
[[ "${user[name]}" == "Bob" ]] || { echo "FAIL: user[name]='${user[name]}' expected 'Bob'"; exit 1; }

# Mixed: object -> array -> element
json -v item -j '{"items": ["x", "y", "z"]}' -s '/items/2'
[[ "$item" == "z" ]] || { echo "FAIL: item='$item' expected 'z'"; exit 1; }

# Mixed: object -> array -> object -> field
json -v name -j '{"users": [{"name": "Alice"}, {"name": "Bob"}]}' -s '/users/0/name'
[[ "$name" == "Alice" ]] || { echo "FAIL: name='$name' expected 'Alice'"; exit 1; }

# Select an array from within an object
json -v tags -j '{"user": {"tags": ["admin", "user"]}}' -s '/user/tags'
[[ "${tags[0]}" == "admin" ]] || { echo "FAIL: tags[0]='${tags[0]}' expected 'admin'"; exit 1; }
[[ "${tags[1]}" == "user" ]] || { echo "FAIL: tags[1]='${tags[1]}' expected 'user'"; exit 1; }

exit 0
