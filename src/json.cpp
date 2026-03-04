/* json builtin - Parse JSON and create bash associative array variables */

/* We must include the bash C headers inside extern "C" but handle the
   strchrnul conflict: bash's externs.h declares strchrnul() with C linkage
   when HAVE_STRCHRNUL is not defined, but glibc's <string.h> in C++ mode
   provides a conflicting C++ overload.  We force HAVE_STRCHRNUL=1 to skip
   bash's declaration since we have the system version available. */

#include <config.h>

/* Force bash to skip its strchrnul/strcasestr declarations —
   glibc provides them and the C++ overloads conflict. */
#ifndef HAVE_STRCHRNUL
#define HAVE_STRCHRNUL 1
#endif
#ifndef HAVE_STRCASESTR
#define HAVE_STRCASESTR 1
#endif

#if defined(HAVE_UNISTD_H)
#include <unistd.h>
#endif

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern "C" {
#include "builtins.h"
#include "shell.h"
#include "bashgetopt.h"
#include "common.h"
#include "arrayfunc.h"
#include "assoc.h"
#include "array.h"
}

/* Bash's xmalloc.h redefines malloc/free/realloc to sh_malloc/sh_xfree etc.
   These symbols are not exported by all bash builds, and we want to use
   standard libc allocation for our own data.  Undo the redefinitions. */
#undef malloc
#undef free
#undef realloc

#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#include <nlohmann/json.hpp>

using njson = nlohmann::json;

/* ================================================================
   Global JSON object registry.

   Every njson object we hand out to bash (via var_[key]) is heap-
   allocated and tracked here so we can look it up by address and
   free it when the variable is overwritten or the builtin unloaded.

   g_registry    : address -> heap njson*
   g_var_objects : varname -> list of addresses owned by that var
   g_var_root    : varname -> the root njson* for that variable
                   (the object whose elements fill var[key] / var[idx])

   g_updating    : re-entrancy guard — set while we are propagating an
                   assign-callback change back into bash variables so we
                   do not recurse infinitely.
   ================================================================ */

static std::unordered_map<uintptr_t, njson *> g_registry;
static std::unordered_map<std::string, std::vector<uintptr_t>> g_var_objects;
static std::unordered_map<std::string, njson *> g_var_root;
static bool g_updating = false;

/* ================================================================
   Pretty-printing configuration via JSON_BASH_XXX shell variables.

   JSON_BASH_INDENT        integer   indentation width (default 2, -1 = compact)
   JSON_BASH_ENSURE_ASCII  0|1       escape all non-ASCII chars  (default 0)

   These are read from the shell environment every time json_to_display()
   is called, so changing them in the current shell session takes effect
   immediately without reloading the builtin.
   ================================================================ */

/* Return an integer shell variable value, or default_val if unset/invalid. */
static int get_int_shvar(const char *name, int default_val) {
  SHELL_VAR *v = find_variable(name);
  if (v && var_isset(v) && !array_p(v) && !assoc_p(v)) {
    char *s = value_cell(v);
    if (s && *s) {
      char *end = nullptr;
      long n = strtol(s, &end, 10);
      if (end != s && *end == '\0')
        return (int)n;
    }
  }
  return default_val;
}

/* Return a boolean shell variable value (1 == true): "1" or "true". */
static bool get_bool_shvar(const char *name, bool default_val) {
  SHELL_VAR *v = find_variable(name);
  if (v && var_isset(v) && !array_p(v) && !assoc_p(v)) {
    char *s = value_cell(v);
    if (s) {
      if (strcmp(s, "1") == 0 || strcmp(s, "true") == 0)
        return true;
      if (strcmp(s, "0") == 0 || strcmp(s, "false") == 0)
        return false;
    }
  }
  return default_val;
}

/* Format a pointer as a hex string: "0x7f..." */
static std::string ptr_to_hex(const njson *p) {
  char buf[32];
  snprintf(buf, sizeof(buf), "0x%lx", (unsigned long)(uintptr_t)p);
  return std::string(buf);
}

/* Parse a hex pointer string back to uintptr_t.  Returns 0 on failure. */
static uintptr_t hex_to_ptr(const char *s) {
  if (!s)
    return 0;
  char *end = nullptr;
  unsigned long val = strtoul(s, &end, 16);
  if (end == s || *end != '\0')
    return 0;
  return (uintptr_t)val;
}

/* Register a heap-allocated njson* and associate it with varname. */
static uintptr_t register_json(const std::string &varname, njson *p) {
  uintptr_t addr = (uintptr_t)p;
  g_registry[addr] = p;
  g_var_objects[varname].push_back(addr);
  return addr;
}

/* Release all njson objects owned by varname.
   Also clears the root entry so the variable is no longer "live". */
static void release_var(const std::string &varname) {
  auto it = g_var_objects.find(varname);
  if (it == g_var_objects.end())
    return;
  for (auto addr : it->second) {
    auto rit = g_registry.find(addr);
    if (rit != g_registry.end()) {
      delete rit->second;
      g_registry.erase(rit);
    }
  }
  g_var_objects.erase(it);
  g_var_root.erase(varname);
}

/* Release everything (called on unload). */
static void release_all() {
  for (auto &kv : g_registry)
    delete kv.second;
  g_registry.clear();
  g_var_objects.clear();
  g_var_root.clear();
}

/* ================================================================
   Helpers to create / populate bash variables
   ================================================================ */

/* Unbind a variable if it exists. */
static void remove_var(const char *name) {
  SHELL_VAR *v = find_variable(name);
  if (v)
    unbind_variable(name);
}

/* Create (or recreate) an associative array variable. */
static SHELL_VAR *make_assoc_var(const char *name) {
  remove_var(name);
  SHELL_VAR *v = make_new_assoc_variable(name);
  if (!v) {
    builtin_error("cannot create associative array %s", name);
    return nullptr;
  }
  return v;
}

/* Create (or recreate) an indexed array variable. */
static SHELL_VAR *make_indexed_var(const char *name) {
  remove_var(name);
  SHELL_VAR *v = make_new_array_variable(name);
  if (!v) {
    builtin_error("cannot create indexed array %s", name);
    return nullptr;
  }
  return v;
}

/* C++-safe version of savestring.
   We use malloc instead of bash's xmalloc because sh_xmalloc may not be
   exported by all bash builds.  The memory is passed to bash's assoc_insert
   / array_insert which will free it with the standard free(). */
static char *cpp_savestring(const char *s) {
  size_t len = strlen(s) + 1;
  char *p = (char *)malloc(len);
  if (!p) return nullptr;
  memcpy(p, s, len);
  return p;
}

/* Insert a key/value pair into an associative array variable. */
static void assoc_put(SHELL_VAR *v, const char *key, const std::string &val) {
  HASH_TABLE *h = assoc_cell(v);
  assoc_insert(h, cpp_savestring(key), cpp_savestring(val.c_str()));
}

/* Insert an element into an indexed array variable. */
static void array_put(SHELL_VAR *v, arrayind_t idx, const std::string &val) {
  ARRAY *a = array_cell(v);
  array_insert(a, idx, cpp_savestring(val.c_str()));
}

/* Convert a json value to its string representation for the display var.
   - strings    : unquoted (just the string content)
   - objects/arrays : indented JSON (depth controlled by JSON_BASH_INDENT)
   - primitives : compact dump()

   Formatting is driven by shell variables:
     JSON_BASH_INDENT       indentation depth  (default 2; -1 = compact)
     JSON_BASH_ENSURE_ASCII escape non-ASCII   (default 0) */
static std::string json_to_display(const njson &j) {
  int    indent       = get_int_shvar("JSON_BASH_INDENT", 2);
  bool   ensure_ascii = get_bool_shvar("JSON_BASH_ENSURE_ASCII", false);

  if (j.is_string()) {
    if (!ensure_ascii)
      return j.get<std::string>(); /* fast path: return raw string content */
    /* ensure_ascii=true: use dump() for escaping, then strip the surrounding
       double-quotes that dump() wraps string values in. */
    std::string dumped = j.dump(-1, ' ', ensure_ascii);
    if (dumped.size() >= 2 && dumped.front() == '"' && dumped.back() == '"')
      return dumped.substr(1, dumped.size() - 2);
    return dumped;
  }

  if (j.is_object() || j.is_array())
    return j.dump(indent, ' ', ensure_ascii);

  /* Scalars are always compact — indent flag would add no value. */
  return j.dump(-1, ' ', ensure_ascii);
}

/* ================================================================
   json_try_parse  —  parse text as JSON with JSON5 comment support.

   We pass ignore_comments=true to nlohmann/json so that single-line
   (// …) and block (/* … * /) comments are silently stripped before
   tokenisation.  This provides "just enough" JSON5 compatibility for
   the most common real-world use-case (config files with comments).

   Trailing commas and other JSON5 extensions are NOT supported.
   Throws njson::parse_error on failure (caller must catch).
   ================================================================ */
static njson json_try_parse(const std::string &text) {
  /* allow_exceptions=true (default), ignore_comments=true */
  return njson::parse(text,
                      /*callback=*/nullptr,
                      /*allow_exceptions=*/true,
                      /*ignore_comments=*/true);
}

/* ================================================================
   Assign-function callbacks.

   These are installed on the bash SHELL_VAR objects so that direct
   bash assignment (var[key]=value  or  var_[key]=ptr) propagates
   the change back into the underlying njson tree and keeps both the
   display and pointer variables consistent.

   Bash calls these with the signature:
       SHELL_VAR *fn(SHELL_VAR *var, char *value, arrayind_t ind, char *key)

   For associative arrays  key  is the string key and  ind  is -1.
   For indexed arrays       ind  is the numeric index and  key  is nullptr.

   After the callback returns, bash performs its own storage of
   (key, value) into the array cell, so we do NOT need to call
   assoc_insert/array_insert for the variable that triggered the
   callback.  We DO need to update the *other* variable (display ↔
   pointer) ourselves.

   The g_updating flag prevents re-entrant calls when we write the
   companion variable from within the callback.
   ================================================================ */

/* Forward declarations so callbacks can call populate helpers. */
static int populate_var(const char *varname, njson *root);

/* ----------------------------------------------------------------
   json_display_assign  —  called when  var[key]=value  or  var[idx]=value
   ----------------------------------------------------------------
   Parses `value` as JSON (strings stay as JSON strings if parse fails),
   updates the root JSON object at the given key/index, and refreshes
   the companion pointer variable (var_[key] / var_[idx]).
   ---------------------------------------------------------------- */
static SHELL_VAR *json_display_assign(SHELL_VAR *var,
                                      char *value,
                                      arrayind_t ind,
                                      char *key) {
  if (g_updating)
    return var; /* prevent recursion */

  if (!value)
    value = const_cast<char *>("");

  std::string sname(var->name);
  auto root_it = g_var_root.find(sname);
  if (root_it == g_var_root.end())
    return var; /* variable no longer tracked — let bash handle it */

  njson *root = root_it->second;

  /* Parse value as JSON; fall back to plain string on parse error. */
  njson new_val;
  try {
    new_val = json_try_parse(value);
  } catch (...) {
    new_val = std::string(value);
  }

  /* Update the root JSON in-place. */
  try {
    if (root->is_object() && key) {
      (*root)[key] = new_val;
    } else if (root->is_array()) {
      if (ind >= 0 && (size_t)ind < root->size())
        (*root)[(size_t)ind] = new_val;
      else if (ind >= 0)
        root->push_back(new_val); /* extend array */
    }
  } catch (...) {
    return var; /* silently ignore type mismatches */
  }

  /* Bash does NOT call assoc_insert / array_insert when assign_func is set —
     the callback is fully responsible for storage.  Store the display value. */
  if (assoc_p(var) && key)
    assoc_put(var, key, std::string(value));
  else if (array_p(var) && ind >= 0)
    array_put(var, ind, std::string(value));

  /* Refresh the companion pointer variable (var_). */
  g_updating = true;
  std::string pname = sname + "_";
  SHELL_VAR *pvar = find_variable(pname.c_str());
  if (pvar) {
    /* Allocate a new sub-object registered under sname. */
    njson *sub = new njson(new_val);
    register_json(sname, sub);
    std::string hex = ptr_to_hex(sub);
    if (assoc_p(pvar) && key)
      assoc_put(pvar, key, hex);
    else if (array_p(pvar) && ind >= 0)
      array_put(pvar, ind, hex);
  }
  g_updating = false;

  return var;
}

/* ----------------------------------------------------------------
   json_ptr_assign  —  called when  var_[key]=ptr  or  var_[idx]=ptr
   ----------------------------------------------------------------
   Validates that `value` is a known JSON pointer in the registry,
   makes a deep copy of the pointed-to object, updates the root JSON
   at the given key/index with the copy, and refreshes the display
   variable (var[key] / var[idx]).

   Assignment of something that is NOT a valid hex pointer is rejected
   with a builtin_error message and the variable is left unchanged.
   ---------------------------------------------------------------- */
static SHELL_VAR *json_ptr_assign(SHELL_VAR *var,
                                  char *value,
                                  arrayind_t ind,
                                  char *key) {
  if (g_updating)
    return var;

  if (!value || *value == '\0')
    return var;

  /* Derive the display variable name: strip trailing '_'. */
  std::string pname(var->name);
  if (pname.empty() || pname.back() != '_')
    return var;
  std::string sname = pname.substr(0, pname.size() - 1);

  auto root_it = g_var_root.find(sname);
  if (root_it == g_var_root.end())
    return var;
  njson *root = root_it->second;

  /* Resolve the pointer. */
  uintptr_t addr = hex_to_ptr(value);
  if (addr == 0) {
    builtin_error("%s: invalid JSON pointer: %s", pname.c_str(), value);
    return var;
  }
  auto reg_it = g_registry.find(addr);
  if (reg_it == g_registry.end()) {
    builtin_error("%s: unknown JSON pointer (freed?): %s", pname.c_str(), value);
    return var;
  }

  /* Deep-copy the pointed-to object. */
  njson new_val = *(reg_it->second);
  njson *sub = new njson(new_val);
  register_json(sname, sub);

  /* Update the root JSON in-place. */
  try {
    if (root->is_object() && key) {
      (*root)[key] = new_val;
    } else if (root->is_array()) {
      if (ind >= 0 && (size_t)ind < root->size())
        (*root)[(size_t)ind] = new_val;
      else if (ind >= 0)
        root->push_back(new_val);
    }
  } catch (...) {
    delete sub;
    return var;
  }

  /* Refresh the companion display variable (var). */
  g_updating = true;
  SHELL_VAR *dvar = find_variable(sname.c_str());
  if (dvar) {
    if (assoc_p(dvar) && key)
      assoc_put(dvar, key, json_to_display(new_val));
    else if (array_p(dvar) && ind >= 0)
      array_put(dvar, ind, json_to_display(new_val));
  }
  g_updating = false;

  /* Tell the caller the value to actually store in the pointer slot. */
  /* We return var; bash will store the original hex string the user
     provided (which is fine — sub has that same address). */
  /* However, sub is a NEW allocation, so its address differs from
     value.  Overwrite the pointer slot ourselves and return the var.
     We have to write the new hex address; bash will then also write
     the old value — we suppress that by storing into the cell here
     before bash does so its write is idempotent for an assoc/array. */
  std::string new_hex = ptr_to_hex(sub);
  if (assoc_p(var) && key)
    assoc_put(var, key, new_hex);
  else if (array_p(var) && ind >= 0)
    array_put(var, ind, new_hex);

  return var;
}

/* ================================================================
   populate_vars  —  the core logic for JSON objects

   Given a varname and a parsed njson object, create two associative arrays:
     varname       : key -> display string
     varname_      : key -> hex pointer to njson*

   After population the bash variables have their assign_func hooks
   installed so that element assignment propagates back into the JSON.
   ================================================================ */

static int populate_object(const char *varname, njson *root) {
  std::string sname(varname);
  std::string pname = sname + "_"; /* pointer variable name */

  /* Release any prior objects for this varname (also clears g_var_root). */
  release_var(sname);

  /* Register the root object and record it as the variable's root. */
  register_json(sname, root);
  g_var_root[sname] = root;

  /* Create the two associative arrays. */
  SHELL_VAR *v_display = make_assoc_var(varname);
  SHELL_VAR *v_ptr     = make_assoc_var(pname.c_str());
  if (!v_display || !v_ptr)
    return EXECUTION_FAILURE;

  /* Iterate over object keys. */
  for (auto &el : root->items()) {
    const std::string &key = el.key();
    const njson &val = el.value();

    /* Display var: pretty value. */
    assoc_put(v_display, key.c_str(), json_to_display(val));

    /* Pointer var: heap-allocated copy, registered. */
    njson *sub = new njson(val);
    register_json(sname, sub);
    assoc_put(v_ptr, key.c_str(), ptr_to_hex(sub));
  }

  /* Install assign-function hooks so bash assignment propagates. */
  v_display->assign_func = json_display_assign;
  v_ptr->assign_func     = json_ptr_assign;

  return EXECUTION_SUCCESS;
}

/* ================================================================
   populate_array  —  core logic for JSON arrays

   Given a varname and a parsed njson array, create two indexed arrays:
     varname       : index -> display string
     varname_      : index -> hex pointer to njson*
   ================================================================ */

static int populate_array(const char *varname, njson *root) {
  std::string sname(varname);
  std::string pname = sname + "_";

  /* Release any prior objects (also clears g_var_root). */
  release_var(sname);

  /* Register the root and record it. */
  register_json(sname, root);
  g_var_root[sname] = root;

  /* Create two indexed arrays. */
  SHELL_VAR *v_display = make_indexed_var(varname);
  SHELL_VAR *v_ptr     = make_indexed_var(pname.c_str());
  if (!v_display || !v_ptr)
    return EXECUTION_FAILURE;

  /* Iterate over array elements. */
  arrayind_t idx = 0;
  for (auto &el : *root) {
    /* Display var. */
    array_put(v_display, idx, json_to_display(el));

    /* Pointer var: heap-allocated copy, registered. */
    njson *sub = new njson(el);
    register_json(sname, sub);
    array_put(v_ptr, idx, ptr_to_hex(sub));

    idx++;
  }

  /* Install assign-function hooks. */
  v_display->assign_func = json_display_assign;
  v_ptr->assign_func     = json_ptr_assign;

  return EXECUTION_SUCCESS;
}

/* ================================================================
   Populate a simple scalar variable (for non-object, non-array JSON).
   ================================================================ */

static int populate_scalar(const char *varname, njson *root) {
  std::string sname(varname);
  std::string pname = sname + "_";

  release_var(sname);
  register_json(sname, root);
  /* Scalars have no element-level assignment to intercept, but we still
     record g_var_root so that re-assignment of the whole scalar via the
     builtin works correctly. */
  g_var_root[sname] = root;

  /* Remove any prior array variables with these names. */
  remove_var(varname);
  remove_var(pname.c_str());

  /* Bind a simple string variable. */
  std::string display = json_to_display(*root);
  bind_variable(varname, display.c_str(), 0);

  /* Bind the pointer variable as a simple string too. */
  bind_variable(pname.c_str(), ptr_to_hex(root).c_str(), 0);

  return EXECUTION_SUCCESS;
}

/* Dispatch to the right populate function based on JSON type. */
static int populate_var(const char *varname, njson *root) {
  if (root->is_object())
    return populate_object(varname, root);
  else if (root->is_array())
    return populate_array(varname, root);
  else
    return populate_scalar(varname, root);
}

/* ================================================================
   Read JSON from various sources.
   ================================================================ */

/* Read all of stdin into a string. */
static std::string read_stdin() {
  std::ostringstream ss;
  ss << std::cin.rdbuf();
  return ss.str();
}

/* Read a file into a string. Returns empty string on error (and sets errno). */
static std::string read_file_contents(const char *path) {
  std::ifstream ifs(path);
  if (!ifs) {
    return std::string();
  }
  std::ostringstream ss;
  ss << ifs.rdbuf();
  return ss.str();
}

/* ================================================================
   json_builtin  —  the main entry point

   Usage:
     json -v VARNAME -j JSON_STRING     # from argument
     json -v VARNAME -f FILE            # from file
     json -v VARNAME -a POINTER_HEX     # from existing pointer
     json -v VARNAME                    # from stdin
     json -v VARNAME <<< '{"key":"val"}'
   ================================================================ */

/* Apply a JSON Pointer selector to a JSON value.
   Returns a new heap-allocated njson* with the selected sub-value,
   or nullptr on error (after printing a message). */
static njson *apply_selector(njson *root, const char *selector) {
  try {
    njson::json_pointer ptr(selector);
    njson *result = new njson(root->at(ptr));
    return result;
  } catch (const njson::out_of_range &e) {
    builtin_error("selector '%s': %s", selector, e.what());
    return nullptr;
  } catch (const njson::parse_error &e) {
    builtin_error("invalid JSON Pointer '%s': %s", selector, e.what());
    return nullptr;
  }
}

extern "C" int json_builtin(WORD_LIST *list) {
  const char *varname = nullptr;
  const char *json_string = nullptr;
  const char *filename = nullptr;
  const char *addr_string = nullptr;
  const char *selector = nullptr;
  int opt;

  reset_internal_getopt();
  while ((opt = internal_getopt(list, const_cast<char *>("v:j:f:a:s:"))) != -1) {
    switch (opt) {
      CASE_HELPOPT;
    case 'v':
      varname = list_optarg;
      break;
    case 'j':
      json_string = list_optarg;
      break;
    case 'f':
      filename = list_optarg;
      break;
    case 'a':
      addr_string = list_optarg;
      break;
    case 's':
      selector = list_optarg;
      break;
    default:
      builtin_usage();
      return EX_USAGE;
    }
  }

  /* -v is required. */
  if (!varname || *varname == '\0') {
    builtin_error("variable name required: use -v VARNAME");
    return EX_USAGE;
  }

  /* Determine the JSON source. */
  int source_count = (json_string ? 1 : 0) + (filename ? 1 : 0) + (addr_string ? 1 : 0);
  if (source_count > 1) {
    builtin_error("only one of -j, -f, or -a may be specified");
    return EX_USAGE;
  }

  /* -a: use an existing pointer from the registry. */
  if (addr_string) {
    uintptr_t addr = hex_to_ptr(addr_string);
    if (addr == 0) {
      builtin_error("invalid pointer: %s", addr_string);
      return EXECUTION_FAILURE;
    }
    auto it = g_registry.find(addr);
    if (it == g_registry.end()) {
      builtin_error("unknown json pointer: %s (object may have been freed)", addr_string);
      return EXECUTION_FAILURE;
    }
    /* Make a deep copy so the new variable owns its own objects. */
    njson *copy = new njson(*(it->second));

    /* Apply selector if given. */
    if (selector) {
      njson *selected = apply_selector(copy, selector);
      delete copy;
      if (!selected)
        return EXECUTION_FAILURE;
      copy = selected;
    }

    return populate_var(varname, copy);
  }

  /* Obtain JSON text. */
  std::string json_text;
  if (json_string) {
    json_text = json_string;
  } else if (filename) {
    json_text = read_file_contents(filename);
    if (json_text.empty() && errno != 0) {
      builtin_error("%s: %s", filename, strerror(errno));
      return EXECUTION_FAILURE;
    }
  } else {
    /* Read from stdin. */
    json_text = read_stdin();
    if (json_text.empty()) {
      builtin_error("no input on stdin");
      return EXECUTION_FAILURE;
    }
  }

  /* Parse — JSON5 comment stripping is enabled via ignore_comments=true. */
  njson *root = nullptr;
  try {
    root = new njson(json_try_parse(json_text));
  } catch (const njson::parse_error &e) {
    builtin_error("JSON parse error: %s", e.what());
    return EXECUTION_FAILURE;
  }

  /* Apply selector if given. */
  if (selector) {
    njson *selected = apply_selector(root, selector);
    delete root;
    if (!selected)
      return EXECUTION_FAILURE;
    root = selected;
  }

  /* Populate variables. */
  return populate_var(varname, root);
}

/* ================================================================
   Load / unload hooks
   ================================================================ */

extern "C" int json_builtin_load(char *s) {
  /* Nothing special to initialize. */
  return 1; /* success */
}

extern "C" void json_builtin_unload(char *s) {
  release_all();
}

/* ================================================================
   Documentation and struct builtin definition
   ================================================================ */

extern "C" {

const char *json_doc[] = {
    "Parse JSON and create bash variables from JSON data.",
    "",
    "Usage: json -v VARNAME [-j JSON | -f FILE | -a PTR] [-s POINTER]",
    "",
    "Options:",
    "  -v VARNAME    Name of the variable to create (required)",
    "  -j STRING     Parse JSON from a string argument (JSON5 comments allowed)",
    "  -f FILE       Parse JSON from a file          (JSON5 comments allowed)",
    "  -a POINTER    Use an existing JSON pointer (from VARNAME_[key])",
    "  -s POINTER    Select a sub-value using JSON Pointer (RFC 6901)",
    "",
    "If no -j, -f, or -a is given, JSON is read from stdin.",
    "",
    "Variable types created depend on the JSON type:",
    "  JSON object  -> associative arrays VARNAME and VARNAME_",
    "  JSON array   -> indexed arrays VARNAME and VARNAME_",
    "  JSON scalar  -> simple variables VARNAME and VARNAME_",
    "",
    "VARNAME   maps keys/indices to display values.",
    "VARNAME_  maps keys/indices to internal JSON pointers (for -a).",
    "",
    "Assignment callbacks (for object and array variables):",
    "  VARNAME[key]=value    Parse value as JSON, update VARNAME_[key].",
    "  VARNAME_[key]=ptr     Deep-copy the object at ptr, update VARNAME[key].",
    "  Array index assignment is handled the same way.",
    "",
    "Display-format configuration (shell variables):",
    "  JSON_BASH_INDENT        indent width for objects/arrays (default 2;",
    "                          set to -1 for compact / single-line output)",
    "  JSON_BASH_ENSURE_ASCII  set to 1 to escape all non-ASCII characters",
    "                          in display output (default 0)",
    "",
    "JSON5 comment support:",
    "  Single-line (//) and block (/* */) comments are silently stripped",
    "  before parsing when using -j or -f.  Other JSON5 extensions such as",
    "  trailing commas are NOT supported.",
    "",
    "JSON Pointer syntax (RFC 6901):",
    "  /key           select object member 'key'",
    "  /0             select array element at index 0",
    "  /a/b/c         select nested path a -> b -> c",
    "  /users/0/name  mixed object/array traversal",
    "",
    "Examples:",
    "  json -v data -j '{\"name\": \"John\", \"age\": 30}'",
    "  echo ${data[name]}              # John",
    "  data[name]=\"Jane\"               # updates JSON in-place",
    "  for e in \"${data[@]}\"; do echo \"$e\"; done",
    "",
    "  json -v arr -j '[\"foo\", \"bar\"]'",
    "  echo ${arr[0]}                  # foo",
    "  arr[0]=\"baz\"                    # updates first element",
    "",
    "  # JSON5: file with comments",
    "  json -v cfg -f config.json5",
    "",
    "  # Compact output:",
    "  JSON_BASH_INDENT=-1 json -v data -j '{\"a\":1}'",
    "",
    "  # Select a nested value directly:",
    "  json -v l3 -j '{\"a\":{\"b\":{\"c\":\"deep\"}}}' -s '/a/b'",
    "  echo ${l3[c]}                   # deep",
    "",
    "  # Navigate into nested objects:",
    "  json -v addr -a \"${data_[address]}\"",
    "  echo ${addr[line1]}             # red street",
    "",
    "  # Iterate over pointers:",
    "  for a in \"${data_[@]}\"; do json -v e -a \"$a\"; echo \"$e\"; done",
    (char *)NULL};

struct builtin json_struct = {
    const_cast<char *>("json"),              /* builtin name */
    json_builtin,                            /* function implementing the builtin */
    BUILTIN_ENABLED,                         /* initial flags for builtin */
    const_cast<char *const *>(json_doc),     /* array of long documentation strings */
    const_cast<char *>("json -v VAR [-j JSON | -f FILE | -a PTR] [-s POINTER]"), /* usage synopsis */
    0                                        /* reserved for internal use */
};

} /* extern "C" */
