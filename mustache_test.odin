package mustache

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:runtime"
import "core:testing"

INTERPOLATION :: "spec/interpolation.json"

load_spec :: proc(filename: string) -> (json.Value) {
  data, ok := os.read_entire_file_from_filename(filename)
  if !ok {
    fmt.println("Failed to load the file!")
    os.exit(1)
  }
  defer delete(data)

  json_data, err := json.parse(data)
  if err != .None {
    fmt.println("Failed to parse the .json file")
    fmt.println("Error:", err)
    os.exit(1)
  }

  return json_data
}

convert :: proc(val: json.Value) -> (Input) {
  input: Input
  #partial switch v in val {
    case json.Null:
      input = ""
    case i64:
      input = fmt.aprintf("%v", v)
    case f64:
      input = fmt.aprintf("%v", v)
    case bool:
      input = fmt.aprintf("%v", v)
    case string:
      input = v
    case:
      input = ""
    case json.Object:
      data: Data
      for key, val in v {
        fmt.printf("key: %v, val: %v\n", key, val)
        new_k := string(key)
        new_v := convert(val)
        data[new_k] = new_v
      }
      input = data
    // TODO: Handle arrays.
    case json.Array:
      input = ""
  }

  return input
}

assert_mustache :: proc(t: ^testing.T,
                        input: string,
                        data: Input,
                        exp_output: string,
                        loc := #caller_location) {
  output, _ := process_template(input, data)
  testing.expect(t, exp_output == output)
}

@(test)
test_basic :: proc(t: ^testing.T) {
  template := "Hello, {{x}}, nice to meet you. My name is {{y}}."
  data := Data {
    "x" = "Ben",
    "y" = "R2D2"
  }
  exp_output := "Hello, Ben, nice to meet you. My name is R2D2."
  assert_mustache(t, template, data, exp_output)
}

@(test)
test_interpolation :: proc(t: ^testing.T) {
  when ODIN_DEBUG {
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    context.allocator = mem.tracking_allocator(&track)
    defer {
      if len(track.allocation_map) > 0 {
        fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
        for _, entry in track.allocation_map {
          fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
        }
      }
      if len(track.bad_free_array) > 0 {
        fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
        for entry in track.bad_free_array {
          fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
        }
      }
      mem.tracking_allocator_destroy(&track)
    }
  }

  spec := load_spec(INTERPOLATION)
  defer json.destroy_value(spec)

  root := spec.(json.Object)
  tests := root["tests"].(json.Array)

  for test, i in tests {
    if i > 1 {
      break
    }

    fmt.println("*************************")
    fmt.println(test)
    test_obj := test.(json.Object)
    test_name := test_obj["name"].(string)
    test_desc := test_obj["desc"].(string)
    template := test_obj["template"].(string)
    exp_output := test_obj["expected"].(string)

    // Object is map[string]Value
    // Value is a union type containing:
    // Null, 
	  // i64, 
	  // f64, 
	  // bool, 
	  // string, 
	  // Array, 
	  // Object, 

    data := test_obj["data"]
    input := convert(data)
    assert_mustache(t, template, input, exp_output)
  }
}
