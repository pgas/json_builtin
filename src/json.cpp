/* json builtin - Parse JSON and create bash associative array variables */

/*
   Copyright (C) 2024-2026 Free Software Foundation, Inc.

   This file is part of GNU Bash.
   Bash is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   Bash is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with Bash.  If not, see <http://www.gnu.org/licenses/>.
*/

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

   g_registry   : address -> heap njson*
   g_var_objects : varname -> list of addresses owned by that var
   ================================================================ */

static std::unordered_map<uintptr_t, njson *> g_registry;
static std::unordered_map<std::string, std::vector<uintptr_t>> g_var_objects;

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

/* Release all njson objects owned by varname. */
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
}

/* Release everything (called on unload). */
static void release_all() {
  for (auto &kv : g_registry)
    delete kv.second;
  g_registry.clear();
  g_var_objects.clear();
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
   - strings: unquoted (just the string content)
   - objects/arrays: pretty-printed JSON
   - primitives (number, bool, null): dump() */
static std::string json_to_display(const njson &j) {
  if (j.is_string())
    return j.get<std::string>();
  if (j.is_object() || j.is_array())
    return j.dump(2);
  return j.dump();
}

/* ================================================================
   populate_vars  —  the core logic for JSON objects

   Given a varname and a parsed njson object, create two associative arrays:
     varname       : key -> display string
     varname_      : key -> hex pointer to njson*
   ================================================================ */

static int populate_object(const char *varname, njson *root) {
  std::string sname(varname);
  std::string pname = sname + "_"; /* pointer variable name */

  /* Release any prior objects for this varname. */
  release_var(sname);

  /* Register the root object. */
  register_json(sname, root);

  /* Create the two associative arrays. */
  SHELL_VAR *v_display = make_assoc_var(varname);
  SHELL_VAR *v_ptr = make_assoc_var(pname.c_str());
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

  /* Release any prior objects for this varname. */
  release_var(sname);

  /* Register the root object. */
  register_json(sname, root);

  /* Create two indexed arrays. */
  SHELL_VAR *v_display = make_indexed_var(varname);
  SHELL_VAR *v_ptr = make_indexed_var(pname.c_str());
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

extern "C" int json_builtin(WORD_LIST *list) {
  const char *varname = nullptr;
  const char *json_string = nullptr;
  const char *filename = nullptr;
  const char *addr_string = nullptr;
  int opt;

  reset_internal_getopt();
  while ((opt = internal_getopt(list, const_cast<char *>("v:j:f:a:"))) != -1) {
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
    return populate_var(varname, copy);
  }

  /* Obtain JSON text. */
  std::string json_text;
  if (json_string) {
    json_text = json_string;
  } else if (filename) {
    json_text = read_file_contents(filename);
    if (json_text.empty()) {
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

  /* Parse. */
  njson *root = nullptr;
  try {
    root = new njson(njson::parse(json_text));
  } catch (const njson::parse_error &e) {
    builtin_error("JSON parse error: %s", e.what());
    return EXECUTION_FAILURE;
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
    "Usage: json -v VARNAME [-j JSON_STRING | -f FILE | -a POINTER]",
    "",
    "Options:",
    "  -v VARNAME    Name of the variable to create (required)",
    "  -j STRING     Parse JSON from a string argument",
    "  -f FILE       Parse JSON from a file",
    "  -a POINTER    Use an existing JSON pointer (from VARNAME_[key])",
    "",
    "If no -j, -f, or -a is given, JSON is read from stdin.",
    "",
    "Variable types created depend on the JSON type:",
    "  JSON object  -> associative arrays VARNAME and VARNAME_",
    "  JSON array   -> indexed arrays VARNAME and VARNAME_",
    "  JSON scalar  -> simple variables VARNAME and VARNAME_",
    "",
    "VARNAME maps keys/indices to display values.",
    "VARNAME_ maps keys/indices to internal JSON pointers (for -a).",
    "",
    "Examples:",
    "  json -v data -j '{\"name\": \"John\", \"age\": 30}'",
    "  echo ${data[name]}              # John",
    "  for e in \"${data[@]}\"; do echo \"$e\"; done",
    "",
    "  json -v arr -j '[\"foo\", \"bar\"]'",
    "  echo ${arr[0]}                  # foo",
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
    const_cast<char *>("json -v VAR [-j JSON | -f FILE | -a PTR]"), /* usage synopsis */
    0                                        /* reserved for internal use */
};

} /* extern "C" */
