package mustache

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:runtime"
import "core:testing"

INTERPOLATION_SPEC :: "spec/interpolation.json"
COMMENTS_SPEC :: "spec/comments.json"
SECTIONS_SPEC :: "spec/sections.json"

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

convert :: proc(val: json.Value) -> (Data) {
  input: Data
  #partial switch v in val {
    case json.Null:
      input = ""
    case i64:
      decimal_str := fmt.aprintf("%v", v)
      input = trim_decimal_string(decimal_str)
    case f64:
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
        new_v := convert(val)
        data[new_k] = new_v
      }
      input = data
    case json.Array:
      data := make(List, allocator=context.temp_allocator)
      for val in v {
        new_v := convert(val)
        append(&data, new_v)
      }
      input = data
  }

  return input
}

// TODO: Better printing and logging if .expect() fails.
assert_mustache :: proc(t: ^testing.T,
                        input: string,
                        data: Data,
                        exp_output: string,
                        loc := #caller_location) {
  output, _ := render(input, data)
  fmt.println("Input   :", input)
  fmt.println("Expected:", exp_output)
  fmt.println("Output  :", output)
  testing.expect_value(t, output, exp_output, loc)
}

@(test)
test_basic :: proc(t: ^testing.T) {
  template := "Hello, {{x}}, nice to meet you. My name is {{y}}."
  data := Map {
    "x" = "Ben",
    "y" = "R2D2"
  }
  exp_output := "Hello, Ben, nice to meet you. My name is R2D2."
  assert_mustache(t, template, data, exp_output)
}

@(test)
test_no_interpolation :: proc(t: ^testing.T) {
  template := "Hello, {Mustache}!"
  data := ""
  exp_output := "Hello, {Mustache}!"
  assert_mustache(t, template, data, exp_output)
}

@(test)
test_literal_tag :: proc(t: ^testing.T) {
  template := "Hello, {{{verb1}}}."
  data := Map {
    "verb1" = "I like < >",
  }
  exp_output := "Hello, I like < >."
  assert_mustache(t, template, data, exp_output)
}

@(test)
test_interpolation_spec :: proc(t: ^testing.T) {
  spec := load_spec(INTERPOLATION_SPEC)
  defer json.destroy_value(spec)

  root := spec.(json.Object)
  tests := root["tests"].(json.Array)

  for test, i in tests {
    test_obj := test.(json.Object)
    test_name := test_obj["name"].(string)
    test_desc := test_obj["desc"].(string)
    template := test_obj["template"].(string)
    exp_output := test_obj["expected"].(string)
    data := test_obj["data"]
    input := convert(data)

    fmt.println("TEST", test_name)
    assert_mustache(t, template, input, exp_output)
  }
}

@(test)
test_comments_spec :: proc(t: ^testing.T) {
  spec := load_spec(COMMENTS_SPEC)
  defer json.destroy_value(spec)

  root := spec.(json.Object)
  tests := root["tests"].(json.Array)

  for test, i in tests {
    test_obj := test.(json.Object)
    test_name := test_obj["name"].(string)
    test_desc := test_obj["desc"].(string)
    template := test_obj["template"].(string)
    exp_output := test_obj["expected"].(string)
    data := test_obj["data"]
    input := convert(data)

    // TODO: Only print the name & desc if the test FAILS.
    // fmt.println("*************************")
    // fmt.println(test_name, "-", test_desc)
    // fmt.println("Input:", template)
    // fmt.println("Expected:", exp_output)
    assert_mustache(t, template, input, exp_output)
  }
}

@(test)
test_sections_spec :: proc(t: ^testing.T) {
  spec := load_spec(SECTIONS_SPEC)
  defer json.destroy_value(spec)

  root := spec.(json.Object)
  tests := root["tests"].(json.Array)

  for test, i in tests {
    if i > 12 do break
    test_obj := test.(json.Object)
    test_name := test_obj["name"].(string)
    test_desc := test_obj["desc"].(string)
    template := test_obj["template"].(string)
    exp_output := test_obj["expected"].(string)
    data := test_obj["data"]
    input := convert(data)

    // TODO: Only print the name & desc if the test FAILS.
    fmt.println("*************************")
    fmt.println(test_name, "-", test_desc)
    fmt.println(data)
    // fmt.println("Input:", template)
    // fmt.println("Expected:", exp_output)
    assert_mustache(t, template, input, exp_output)
  }
}
