# json_builtin

A dynamically-loadable bash builtin for parsing JSON and creating bash variables.

**json_builtin** enables bash scripts to work with JSON data by parsing it into bash variables. It automatically detects JSON types (objects, arrays, scalars) and creates appropriate variable structures with both display-friendly and pointer-based access patterns.

## Features

- **Multiple Input Sources**: Parse JSON from command-line strings (`-j`), files (`-f`), stdin, or existing pointers (`-a`)
- **Automatic Type Detection**: Seamlessly handles JSON objects (→ associative arrays), arrays (→ indexed arrays), and scalars (→ strings)
- **Deep Nesting Support**: Navigate arbitrary nesting levels using pointer variables, allowing re-parsing from intermediate JSON objects
- **Full Iteration Support**: Iterate over all JSON elements using standard bash array syntax (`${var[@]}`)
- **JSON Pointer Selectors**: Use RFC 6901 JSON Pointer syntax (`-s` flag) for direct deep access without intermediate steps
- **JSON Patch (RFC 6902)**: Apply a sequence of `add`, `remove`, `replace`, `move`, `copy`, `test` operations via `-p`
- **JSON Merge Patch (RFC 7396)**: Merge an object patch (present keys overwrite, `null` keys delete) via `-m`
- **Dual Variable System**: Each invocation creates three bash variables:
  - Display variable (e.g., `mydata`): maps keys/indices to pretty-printed values
  - Pointer variable (e.g., `mydata_`): maps keys/indices to internal memory addresses for re-parsing
  - Root pointer scalar (e.g., `mydata__`): the memory address of the entire document (for `-a`, `-p`, `-m`)
- **Assignment Callbacks**: Assigning `var[key]=value` or `var_[key]=ptr` updates the underlying JSON in-place
- **Display Configuration**: `JSON_BASH_INDENT` and `JSON_BASH_ENSURE_ASCII` shell variables control output formatting
- **JSON5 Comment Support**: Single-line (`//`) and block (`/* */`) comments are stripped before parsing
- **Memory Management**: Automatic tracking and cleanup of heap-allocated JSON objects

## Building

### Prerequisites

- bash (same source tree used to load the builtin)
- CMake 3.10 or later
- C++20 capable compiler (g++, clang++)

### Build Steps

```bash
# In the project root
mkdir -p build
cd build

# Configure (replace /path/to/bash-source with actual bash source directory)
cmake .. -DBASH_HEADERS=/path/to/bash-source

# Build
ninja  # or: make
```

After building, `src/json.so` will be the compiled builtin.

### Testing the Build

```bash
cd ..  # Back to project root
bash test.sh
```

All 20 tests should pass. Each test file demonstrates a specific feature.

## Usage

### Loading the Builtin

```bash
enable -f ./src/json.so json
```

Or set an alias for convenience:

```bash
alias json='enable -f ./src/json.so json; json'
```

### Basic Syntax

```bash
json -v VARNAME [INPUT_SOURCE] [OPTIONS]
```

**Where:**
- `-v VARNAME` — destination variable name (required)
- `INPUT_SOURCE` — one of:
  - `-j JSON_STRING` — parse this JSON string
  - `-f FILENAME` — read and parse JSON from file
  - `-a POINTER` — re-parse from a pointer variable (from `VARNAME_`)
  - (stdin) — read JSON from stdin if no other source
- `OPTIONS`:
  - `-s SELECTOR` — apply RFC 6901 JSON Pointer selector

### Example: Parse a JSON Object

```bash
json -v config -j '{"host": "localhost", "port": 8080}'

# Display variable
echo "${config[host]}"    # localhost
echo "${config[port]}"    # 8080

# Iterate
for key in "${!config[@]}"; do
  echo "$key: ${config[$key]}"
done
```

### Example: Parse a JSON Array

```bash
json -v items -j '[
  {"id": 1, "name": "Alice"},
  {"id": 2, "name": "Bob"}
]'

# Access
echo "${items[0]}"        # {ID: 1, ...} (pretty-printed)
echo "${items[1]}"        # {ID: 2, ...}

# Iterate
for index in "${!items[@]}"; do
  echo "Item $index: ${items[$index]}"
done
```

### Example: Read from File

```bash
json -v data -f config.json
```

### Example: Deep Nesting with Pointers

```bash
# Parse top-level object
json -v data -j '{
  "users": [
    {"name": "Alice", "age": 30},
    {"name": "Bob", "age": 25}
  ]
}'

# Navigate to 'users' array (pointer stored in data_[users])
json -v users -a "${data_[users]}"

# Navigate to first user object
json -v user0 -a "${users_[0]}"

# Access fields
echo "${user0[name]}"     # Alice
echo "${user0[age]}"      # 30
```

### Example: JSON Pointer Selectors

RFC 6901 JSON Pointers provide direct access to nested values without intermediate steps.

```bash
json -v data -j '{
  "level1": {
    "level2": {
      "value": "deep data"
    }
  }
}'

# Selector syntax: /key/subkey/index
json -v result -a "${data_[level1]}" -s "/level2/value"

# Or use from the top:
json -v direct -j '{"a": {"b": [1, 2, 3]}}' -s "/a/b/0"
# direct now contains "1"
```

## Output Variables

Each call to `json` creates two bash variables:

### Display Variable (`VARNAME`)

- For **objects**: associative array with keys mapped to pretty-printed values
  - `${var[key]}` → value (pretty-printed if nested)
- For **arrays**: indexed array with indices mapped to pretty-printed values
  - `${var[0]}` → first element (pretty-printed if nested)
- For **scalars**: simple string variable
  - `$var` → the literal value

### Pointer Variable (`VARNAME_`)

- For **objects**: associative array with keys mapped to hex-encoded memory pointers
  - `${var_[key]}` → `0x7f1234567890` (pointer to nested JSON object)
- For **arrays**: indexed array with indices mapped to pointers
  - `${var_[0]}` → `0x7f1234567890`
- For **scalars**: simple string with the root pointer
  - `$var_` → `0x7f1234567890`

### Root Pointer Scalar (`VARNAME__`)

A plain scalar variable holding the memory address of the **entire document** root.

- `$var__` → `0x7f1234567890` (always a simple `$var__` expansion)
- Available for **objects** and **arrays** (for scalars, `$var_` already serves this role)
- Use it with `-a` to re-parse the whole document, or with `-p` / `-m` to pass a pre-parsed patch/merge argument

```bash
json -v cfg -j '{"host":"localhost","port":8080}'
# Re-parse the whole document via its root pointer
json -v cfg2 -a "$cfg__"      # equivalent to re-parsing from JSON text
echo "${cfg2[host]}"          # localhost

# Use a pre-parsed merge patch via root pointer
json -v patch -j '{"port":9090}'
json -v cfg3 -a "$cfg__" -m "$patch__"
echo "${cfg3[port]}"          # 9090
```

**Purpose of Pointers:**
Pointers enable re-parsing intermediate JSON structures without rebuilding from text:

```bash
json -v data -j '{"nested": {"value": 42}}'
json -v nested_obj -a "${data_[nested]}"
# nested_obj can now be used like a fresh variable
echo "${nested_obj[value]}"  # 42
```

## Advanced Examples

### Example: Processing API Response

```bash
# Fetch JSON from API
response=$(curl -s https://api.example.com/users)

json -v users -j "$response" -s "/data"
echo "Found ${#users[@]} users"

for idx in "${!users[@]}"; do
  json -v user -a "${users_[$idx]}"
  echo "User ${user[name]} (${user[email]})"
done
```

### Example: Configuration with Defaults

```bash
# Merge with defaults
json -v defaults -j '{
  "timeout": 30,
  "retries": 3,
  "debug": false
}'

# Parse user config
if [[ -f ~/.myapp.json ]]; then
  json -v config -f ~/.myapp.json
else
  config=("${defaults[@]}")
  config_=("${defaults_[@]}")
fi

timeout=${config[timeout]:-${defaults[timeout]}}
retries=${config[retries]:-${defaults[retries]}}
```

### Example: Transforming Nested JSON

```bash
# Extract names from nested user objects
json -v response -j '{
  "users": [
    {"name": "Alice", "role": "admin"},
    {"name": "Bob", "role": "user"}
  ]
}'

# Navigate to array
json -v users -a "${response_[users]}"

# Extract names
for idx in "${!users[@]}"; do
  json -v user -a "${users_[$idx]}"
  echo "${user[name]}"
done
```

### Example: Conditional Processing

```bash
json -v config -f config.json

if [[ -n "${config[api_key]}" ]]; then
  echo "API key found: ${config[api_key]}"
else
  echo "No API key configured"
fi
```

### Example: Iterating Associative Arrays

```bash
json -v settings -j '{
  "feature_a": true,
  "feature_b": false,
  "feature_c": true
}'

# Iterate keys
for feature in "${!settings[@]}"; do
  if [[ "${settings[$feature]}" == "true" ]]; then
    echo "Enabling: $feature"
  fi
done
```

### Example: Type-Aware Processing

```bash
json -v value -j '42'
if [[ "$value" =~ ^[0-9]+$ ]]; then
  echo "Numeric: $((value + 10))"
fi

json -v value -j '"hello"'
echo "String: $value"

json -v value -j 'null'
if [[ -z "$value" ]]; then
  echo "Null or empty"
fi
```

### Example: Array-in-Object Navigation

```bash
json -v doc -j '{
  "items": [10, 20, 30],
  "metadata": {"count": 3}
}'

json -v items -a "${doc_[items]}"
echo "Second item: ${items[1]}"

json -v meta -a "${doc_[metadata]}"
echo "Count: ${meta[count]}"
```

### Example: JSON Patch (RFC 6902)

```bash
json -v doc -j '{"name":"Alice","score":0,"temp":"remove-me"}'

# Apply patch inline
json -v doc -a "$doc__" \
  -p '[
    {"op":"replace","path":"/score","value":99},
    {"op":"remove","path":"/temp"},
    {"op":"add","path":"/rank","value":"gold"}
  ]'

echo "${doc[name]}"   # Alice
echo "${doc[score]}"  # 99
echo "${doc[rank]}"   # gold
echo "${doc[temp]}"   # (empty — removed)
```

Pass a pre-parsed patch document via its root pointer (`$patch__`):

```bash
json -v patch -j '[{"op":"add","path":"/x","value":1}]'
json -v result -j '{"y":2}' -p "$patch__"
echo "${result[x]}"  # 1
```

### Example: JSON Merge Patch (RFC 7396)

```bash
json -v doc -j '{"a":1,"b":2,"c":"old"}'

# Keys in the merge object overwrite; null keys delete
json -v doc -a "$doc__" -m '{"b":99,"c":null,"d":"new"}'
echo "${doc[a]}"  # 1
echo "${doc[b]}"  # 99
echo "${doc[c]}"  # (empty — deleted by null)
echo "${doc[d]}"  # new
```

### Example: Chaining Patch and Merge

`-p` and `-m` can both be specified in the same invocation. The patch is applied first:

```bash
json -v doc -j '{"v":0,"drop":1}'
json -v doc -a "$doc__" \
  -p '[{"op":"replace","path":"/v","value":7}]' \
  -m '{"drop":null,"extra":"ok"}'
echo "${doc[v]}"      # 7
echo "${doc[drop]}"   # (empty)
echo "${doc[extra]}"  # ok
```

## Implementation Notes

### Design Principles

1. **Automatic Type Detection**: The builtin inspects the root JSON value and creates the appropriate bash variable type (associative array, indexed array, or scalar).

2. **Dual-Variable System**: Every variable can be re-parsed from a pointer, enabling navigation of arbitrary nesting depths without keeping large JSON texts in memory.

3. **Memory Tracking**: A global registry maps pointer addresses to JSON objects. When a variable is reassigned, old objects are freed. On builtin unload, all remaining objects are cleaned up.

4. **No Type Preservation**: JSON type information (number vs string, null vs empty) is lost in conversion to bash strings. This is a fundamental limitation of bash's data model.

## Limitations

1. **Type Information**: All values become bash strings. JSON's distinction between `"42"` (string) and `42` (number) is lost.

2. **Partial JSON5**: Only `//` and `/* */` comments are stripped. Other JSON5 extensions (trailing commas, unquoted keys, etc.) cause parse errors.

3. **Limited Bash Compatibility**: Requires a bash version built with dynamically-loadable builtins. Most distributions have this enabled.

## Memory Management

### Object Lifecycle

1. **Creation**: When JSON is parsed, objects are allocated on the heap and registered in an internal global registry.

2. **Re-parsing**: When a pointer variable is used with `-a`, the referenced object is found in the registry and re-used (not re-allocated).

3. **Cleanup on Reassignment**: When a variable is assigned new JSON content, any old objects are freed from the registry.

4. **Cleanup on Unload**: When the builtin is unloaded with `enable -n json`, all remaining objects are freed.

### Safety

- **No memory leaks** on normal usage (reassignment, iteration, unload)
- **Registry prevents** use-after-free when navigating pointers
- **Pointer validation** returns errors if an invalid address is used

## Testing

The project includes 26 comprehensive test files covering:

- **Basic Parsing** (`test_basic.sh`) — objects, arrays, scalars
- **Input Sources** (`test_file.sh`, `test_stdin.sh`) — file and stdin input
- **Arrays** (`test_array_basic.sh`, `test_array_iterate.sh`) — array parsing and iteration
- **Nesting** (`test_nested.sh`, `test_deep_nesting.sh`) — nested structures
- **Combinations** (`test_object_with_array.sh`, `test_array_with_objects.sh`, `test_complex_nested.sh`) — mixed structures
- **Navigation** (`test_pointer.sh`, `test_reassign.sh`, `test_iterate_pointers.sh`) — pointer-based navigation
- **Selectors** (`test_selector_object.sh`, `test_selector_array.sh`, `test_selector_combined.sh`) — JSON Pointer support
- **Error Handling** (`test_errors.sh`) — invalid input and error cases
- **JSON5 Comments** (`test_json5_comments.sh`) — `//` and `/* */` comment stripping
- **Display Format** (`test_display_format.sh`) — `JSON_BASH_INDENT`, `JSON_BASH_ENSURE_ASCII`
- **Assignment Callbacks** (`test_assign_display.sh`, `test_assign_pointer.sh`) — in-place mutation
- **JSON Patch** (`test_json_patch.sh`) — RFC 6902 add/remove/replace/move/copy/test
- **JSON Merge Patch** (`test_json_merge_patch.sh`) — RFC 7396 merge semantics

Run all tests with:

```bash
bash test.sh
```

Each test file is an executable bash script that can also be run independently:

```bash
bash tests/test_basic.sh ./src/json.so
```

All tests must pass before considering a change complete.

## Troubleshooting

### "builtin not found"
Make sure the builtin is loaded:
```bash
enable -f /path/to/json.so json
```

### "JSON parse error"
Verify the JSON is valid. Use a JSON validator like `jq` to check:
```bash
echo '...' | jq .
```

### "unknown json pointer"
The pointer address is either invalid or the original variable was unset. Save pointer variables before unsetting display variables:

```bash
json -v data -j '{"x": {"y": 1}}'
ptr="${data_[x]}"       # Save pointer first
unset data              # Safe: pointer is captured
json -v nested -a "$ptr"
```

### Bash version issues
If the builtin fails to load, verify bash has loadable builtin support:
```bash
bash --version | head -1
```

And verify the bash source used for compilation matches the running bash:
```bash
which bash
$BASH --version
```

## Contributing

To extend the functional or fix bugs, use the `.github/copilot.md` file as a guide. It contains:
- Critical C/C++ interop constraints
- Code structure and patterns
- Memory management rules
- Testing requirements
- Safe enhancement ideas

Key files to understand:
- `src/json.cpp` — main implementation (547 lines, well-commented)
- `CMakeLists.txt` — build configuration
- `tests/test_*.sh` — executable specifications

## License

[Add your license here]

## References

- [nlohmann/json library](https://github.com/nlohmann/json) — JSON parsing
- [RFC 6901 JSON Pointer](https://tools.ietf.org/html/rfc6901) — selector syntax (`-s`)
- [RFC 6902 JSON Patch](https://tools.ietf.org/html/rfc6902) — patch operations (`-p`)
- [RFC 7396 JSON Merge Patch](https://tools.ietf.org/html/rfc7396) — merge semantics (`-m`)
- [Bash Builtins documentation](https://www.gnu.org/software/bash/manual/html_node/Bash-Builtins.html)
