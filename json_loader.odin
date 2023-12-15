package mustache

import "core:encoding/json"
import "core:fmt"
import "core:runtime"

load_json :: proc(val: json.Value) -> (loaded: JSON_Data) {
  switch _val in val {
  case bool, string:
    v: any = runtime.new_clone(fmt.tprintf("%v", _val))^
    loaded = v
  case i64, f64:
    str := fmt.tprintf("%v", _val)
    decimal_str: any = runtime.new_clone(trim_decimal_string(str))^
    loaded = decimal_str
  case json.Object:
    data := JSON_Map{}
    for key, val in _val {
      new_k := fmt.tprintf("%v", key)
      data[new_k] = load_json(val)
    }
    loaded = data
  case json.Array:
    data := JSON_List{}
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
