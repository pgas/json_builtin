#!/bin/bash
# Test: complex nested structure with mixed objects and arrays
SO_PATH="$1"
enable -f "$SO_PATH" json

json -v var -j '{
  "users": [
    {"name": "Alice", "tags": ["admin", "user"]},
    {"name": "Bob", "tags": ["user"]}
  ],
  "count": 2
}'

# Top-level
[[ "${var[count]}" == "2" ]] || { echo "FAIL: var[count]='${var[count]}' expected '2'"; exit 1; }

# Navigate into the users array
json -v users -a "${var_[users]}"
[[ ${#users[@]} -eq 2 ]] || { echo "FAIL: expected 2 users, got ${#users[@]}"; exit 1; }

# Navigate into first user
json -v user0 -a "${users_[0]}"
[[ "${user0[name]}" == "Alice" ]] || { echo "FAIL: user0[name]='${user0[name]}' expected 'Alice'"; exit 1; }

# Navigate into Alice's tags
json -v tags -a "${user0_[tags]}"
[[ "${tags[0]}" == "admin" ]] || { echo "FAIL: tags[0]='${tags[0]}' expected 'admin'"; exit 1; }
[[ "${tags[1]}" == "user" ]] || { echo "FAIL: tags[1]='${tags[1]}' expected 'user'"; exit 1; }

# Navigate into second user
json -v user1 -a "${users_[1]}"
[[ "${user1[name]}" == "Bob" ]] || { echo "FAIL: user1[name]='${user1[name]}' expected 'Bob'"; exit 1; }

# Bob's tags
json -v btags -a "${user1_[tags]}"
[[ "${btags[0]}" == "user" ]] || { echo "FAIL: btags[0]='${btags[0]}' expected 'user'"; exit 1; }
[[ ${#btags[@]} -eq 1 ]] || { echo "FAIL: expected 1 tag for Bob, got ${#btags[@]}"; exit 1; }

exit 0
