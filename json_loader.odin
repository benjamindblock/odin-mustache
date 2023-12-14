package mustache

import "core:encoding/json"
import "core:fmt"

// All data provided will either be:
// 1. A string
// 2. A mapping from string => string
// 3. A mapping from string => more Data
// 4. An array of Data?
Map :: distinct map[string]Data
List :: distinct [dynamic]Data
Data :: union {
  Map,
  List,
  string
}

load_json :: proc(val: json.Value) -> (loaded: Data) {
  switch _val in val {
  case bool, string:
    loaded = fmt.aprintf("%v", _val)
  case i64, f64:
    decimal_str := fmt.aprintf("%v", _val)
    loaded = trim_decimal_string(decimal_str)
  case json.Object:
    data := Map{}
    for key, val in _val {
      new_k := fmt.aprintf("%v", key)
      data[new_k] = load_json(val)
    }
    loaded = data
  case json.Array:
    data := List{}
    for v in _val {
      append(&data, load_json(v))
    }
    loaded = data
  case json.Null:
  }

  return loaded
}

trim_decimal_string :: proc(s: string) -> string {
  if len(s) == 0 || s[len(s)-1] != '0' {
    return s
  }

  // We have at least one trailing zero. Search backwards and find the rest.
  trailing_start_idx := len(s)-1
  for i := len(s) - 2; i >= 0 ; i -= 1 {
    switch s[i] {
    case '0':
      if trailing_start_idx == i + 1 {
        trailing_start_idx = i
      }
    case '.':
      if trailing_start_idx == i + 1 {
        // Removes point completely for numbers like 0.000
        trailing_start_idx = i
      }
      return s[:trailing_start_idx]
    }
  }

  return s
}
