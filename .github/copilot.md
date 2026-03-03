# Copilot Instructions for json_builtin

This file contains guidelines for GitHub Copilot when assisting with development of the json_builtin project.

## Project Overview

**json_builtin** is a dynamically-loadable bash builtin written in C++20 that parses JSON and creates bash variables for accessing JSON data. It works by:

1. Parsing JSON from various sources (`-j` string, `-f` file, stdin, or `-a` pointer)
2. Creating two bash variables per invocation:
   - Display variable (e.g., `var`): maps keys/indices to pretty-printed values
   - Pointer variable (e.g., `var_`): maps keys/indices to hex-encoded memory addresses of live JSON objects
3. Allowing navigation through nested structures by passing pointers with `-a` flag
4. Supporting JSON Pointer selectors (RFC 6901) with `-s` flag for direct deep access

## Code Structure

**File Organization:**
- `src/json.cpp` (547 lines) — entire implementation, organized into 10 logical sections separated by detailed comments
- `tests/test_*.sh` — 20 bash test scripts serving as specifications for desired behavior
- `CMakeLists.txt` — project configuration using FetchContent for nlohmann/json
- `src/CMakeLists.txt` — builds `json.so` as a CMake MODULE library

## Critical Constraints & Patterns

### 1. C/C++ Interoperability (MOST IMPORTANT)

**Header Inclusion Rules:**
```cpp
// ✅ CORRECT ORDER:
#include <config.h>                    // Before anything else
#define HAVE_STRCHRNUL 1               // Skip bash's conflicting declarations
#define HAVE_STRCASESTR 1
#include <string.h>                    // Standard C headers OUTSIDE extern "C"
#include <stdlib.h>
extern "C" {
  #include "builtins.h"                // Bash headers INSIDE extern "C"
  #include "shell.h"
  #include "arrayfunc.h"
  #include "assoc.h"
  #include "array.h"
}
#undef malloc                          // Undo bash's macro redefinitions
#undef free
#include <nlohmann/json.hpp>           // C++ libraries AFTER extern "C"
```

**Never:**
- Include bash headers before `<string.h>`
- Include bash headers outside `extern "C"`
- Use `xmalloc()` directly (not exported; use standard `malloc()`)
- Assume a bash symbol is exported without testing it

### 2. Memory Management

**Registry Pattern:**
```cpp
static std::unordered_map<uintptr_t, njson*> g_registry;
static std::unordered_map<std::string, std::vector<uintptr_t>> g_var_objects;
```

**Rules:**
- All heap-allocated JSON objects are registered with `register_json(varname, ptr)`
- When a variable is reassigned, call `release_var(varname)` to free old objects
- On builtin unload, `release_all()` is called from the unload hook
- **Never** directly `delete` without updating the registry first

**Memory Operations:**
```cpp
njson *root = new njson(njson::parse(json_text));  // ✅ Create heap object
register_json(varname, root);                       // ✅ Register it
// Later...
release_var(varname);                              // ✅ Cleanup when done
delete ptr;                                         // ✅ Only if not in registry
```

### 3. Bash Variable APIs

**For Associative Arrays (JSON objects):**
```cpp
SHELL_VAR *v = make_new_assoc_variable(varname);
if (!v) return EXECUTION_FAILURE;
HASH_TABLE *h = assoc_cell(v);
assoc_insert(h, cpp_savestring("key"), cpp_savestring("value"));
```

**For Indexed Arrays (JSON arrays):**
```cpp
SHELL_VAR *v = make_new_array_variable(varname);
if (!v) return EXECUTION_FAILURE;
ARRAY *a = array_cell(v);
array_insert(a, 0, cpp_savestring("value"));
```

**For Simple Variables (scalars):**
```cpp
bind_variable(varname, "value", 0);
```

**String Allocation:**
```cpp
// ✅ CORRECT: Use malloc and let bash manage it
static char *cpp_savestring(const char *s) {
  size_t len = strlen(s) + 1;
  char *p = (char *)malloc(len);
  if (!p) return nullptr;
  memcpy(p, s, len);
  return p;
}
assoc_insert(h, cpp_savestring(key), cpp_savestring(val));

// ❌ WRONG: Don't use bash's savestring
assoc_insert(h, savestring(key), savestring(val));  // xmalloc issues

// ❌ WRONG: Don't use stack strings
assoc_insert(h, (char *)"key", (char *)"value");  // Bash will free stack memory!
```

### 4. Option Parsing

**Current pattern in `json_builtin()`:**
```cpp
const char *selector = nullptr;
while ((opt = internal_getopt(list, const_cast<char *>("v:j:f:a:s:"))) != -1) {
  switch (opt) {
    case 's':
      selector = list_optarg;
      break;
    // ...
  }
}
```

**To add a new option:**
1. Add letter and `:` to option string if it takes an argument
2. Add `case 'x':` handler
3. Store in a variable (e.g., `const char *new_option = list_optarg;`)
4. Update `json_doc[]` array with new option description
5. Update usage string in `json_struct`
6. Write a test file to verify

### 5. Error Handling

**Return codes:**
- `EXECUTION_SUCCESS` — success
- `EXECUTION_FAILURE` — runtime error
- `EX_USAGE` — command line usage error

**Error reporting:**
```cpp
// ✅ CORRECT:
if (!varname) {
  builtin_error("variable name required: use -v VARNAME");
  return EX_USAGE;
}

// ✅ For runtime errors:
if (g_registry.find(addr) == g_registry.end()) {
  builtin_error("unknown json pointer: %s", addr_string);
  return EXECUTION_FAILURE;
}

// ❌ WRONG: Don't use printf or std::cerr
printf("error\n");      // Won't integrate with bash properly
std::cerr << "error";   // Wrong I/O stream
```

### 6. JSON Processing

**Parsing with error handling:**
```cpp
njson *root = nullptr;
try {
  root = new njson(njson::parse(json_text));
} catch (const njson::parse_error &e) {
  builtin_error("JSON parse error: %s", e.what());
  return EXECUTION_FAILURE;
}
```

**Select with JSON Pointer:**
```cpp
static njson *apply_selector(njson *root, const char *selector) {
  try {
    njson::json_pointer ptr(selector);
    njson *result = new njson(root->at(ptr));
    return result;
  } catch (const njson::out_of_range &e) {
    builtin_error("selector '%s': %s", selector, e.what());
    return nullptr;
  }
}
```

**Type checking:**
```cpp
if (root->is_object()) { /* ... */ }
else if (root->is_array()) { /* ... */ }
else { /* scalar */ }
```

### 7. Type Conversion

**JSON to display string:**
```cpp
static std::string json_to_display(const njson &j) {
  if (j.is_string())
    return j.get<std::string>();
  if (j.is_object() || j.is_array())
    return j.dump(2);  // Pretty-print
  return j.dump();     // Numbers, bools, null
}
```

**Pointer to hex string:**
```cpp
static std::string ptr_to_hex(const njson *p) {
  char buf[32];
  snprintf(buf, sizeof(buf), "0x%lx", (unsigned long)(uintptr_t)p);
  return std::string(buf);
}

// Reverse:
static uintptr_t hex_to_ptr(const char *s) {
  if (!s) return 0;
  char *end = nullptr;
  unsigned long val = strtoul(s, &end, 16);
  if (end == s || *end != '\0') return 0;
  return (uintptr_t)val;
}
```

## Code Style & Conventions

- **Sections:** Major functions are preceded by a `/* ================================================================ */` header comment describing the section
- **Function names:** lowercase with underscores (e.g., `populate_object`, `apply_selector`)
- **Variables:** lowercase with underscores; global statics prefixed with `g_` (e.g., `g_registry`)
- **Comments:** Explain *why*, not *what* — the code mostly explains what
- **Error messages:** Use `builtin_error(fmt, args)`, not `fprintf` or `std::cerr`
- **Line length:** Keep ~100 characters; break long statements

## Testing Requirements

**Test File Structure:**
```bash
#!/bin/bash
# Test: [descriptive title]
SO_PATH="$1"
enable -f "$SO_PATH" json

# Actual test
json -v var -j '{...}'
[[ "${var[key]}" == "expected" ]] || { echo "FAIL: description"; exit 1; }

exit 0
```

**Testing Practices:**
- Test both the display variable and the pointer variable
- Test error cases (invalid JSON, missing keys, bad selectors)
- Test integration with all input methods (`-j`, `-f`, `-a`, stdin)
- Test iteration with `${var[@]}` and `${var_[@]}`
- Run full suite with `bash test.sh` — all must pass

**When Creating a Test:**
- Use bash's `[[ ]]` syntax for comparisons
- Exit `1` on failure with a clear message
- Cover both happy path and edge cases
- Name file `test_<feature>.sh` and place in `tests/` directory

## What Copilot Should NOT Do

❌ **Never:**
- Reorder includes without understanding the C/C++ interop issues
- Use bash macros like `savestring()` directly in C++ code
- Call undefined bash symbols without testing they're exported
- Directly `free()` pointers allocated by `assoc_insert()` or `array_insert()`
- Use C++ exceptions for bash error cases (use return codes instead)
- Add features that break existing tests
- Assume memory layout or bash internals
- Use printf/fprintf for builtin output (use `builtin_error()`)

❌ **New Features That Require Extra Caution:**
- Adding options that change how variables are created (might break scripts relying on current behavior)
- Changing the registry/pointer system (affects all navigation)
- Adding new bash API calls (must verify symbol is exported)
- Modifying population functions (might change variable types unexpectedly)

## Enhancement Ideas (If You Need Guidance)

If Copilot suggests a feature and you're unsure, consider:

1. **Small & Self-Contained** → Likely safe
   - Adding a new selector variant (e.g., JSONPath)
   - New test file for edge cases
   - Better error messages

2. **Medium & Requires Care** → Ask for incremental approach
   - New input format (e.g., YAML)
   - Variable naming scheme change
   - New option that affects variable creation

3. **Large & High Risk** → Should be done manually
   - Changing the registry system
   - Supporting arrays at top-level (fundamentally changes variable types)
   - Major refactoring of population logic

## References & Resources

**For Bash Builtin APIs:**
- Grep `bash/variables.h` for `SHELL_VAR*` and variable functions
- Grep `bash/arrayfunc.h` for `bind_array_variable()`, `array_insert()`, etc.
- Grep `bash/assoc.h` for associative array functions
- Check `bash/array.h` for indexed array element management

**For nlohmann/json:**
- https://github.com/nlohmann/json — full documentation
- `njson::json_pointer` for RFC 6901 selector support
- `.at()` for safe access; `.operator[]` for non-throwing access

**For Bash Integration:**
- Bash source: `loadables/` directory has examples
- `src/builtin.c` shows the standard pattern for builtins

## Quick Checklist for New Features

When implementing a feature with Copilot assistance:

- [ ] Code compiles without warnings
- [ ] All existing tests pass (`bash test.sh`)
- [ ] New test file created and passes
- [ ] No memory leaks (manually check if complex)
- [ ] Error cases handled with appropriate return codes
- [ ] Help text in `json_doc[]` updated
- [ ] Usage string in `json_struct` updated
- [ ] Documented in README.md with examples
- [ ] No bash symbol assumptions (test before relying)
- [ ] No C/C++ interop violations (header order, etc.)

---

**Last Updated:** 2026-03-03
**Maintained By:** Development Team
