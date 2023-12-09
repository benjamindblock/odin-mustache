package mustache

import "core:encoding/json"
import "core:fmt"

load_json :: proc(val: json.Value) -> (Data) {
  input: Data

  switch v in val {
  case json.Null:
    input = ""
  case i64, f64:
    decimal_str := fmt.aprintf("%v", v)
    input = trim_decimal_string(decimal_str)
  case bool:
    input = fmt.aprintf("%v", v)
  case string:
    input = v
  case json.Object:
    data := make(Map, allocator=context.temp_allocator)
    for key, val in v {
      new_k := string(key)
      new_v := load_json(val)
      data[new_k] = new_v
    }
    input = data
  case json.Array:
    data := make(List, allocator=context.temp_allocator)
    for val in v {
      new_v := load_json(val)
      append(&data, new_v)
    }
    input = data
  }

  return input
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
