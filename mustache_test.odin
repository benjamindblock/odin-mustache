package mustache

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:runtime"
import "core:testing"

COMMENTS_SPEC :: "spec/comments.json"
DELIMITERS_SPEC :: "spec/delimiters.json"
INTERPOLATION_SPEC :: "spec/interpolation.json"
INVERTED_SPEC :: "spec/inverted.json"
PARTIALS_SPEC :: "spec/partials.json"
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

// TODO: Better printing and logging if .expect() fails.
assert_mustache :: proc(t: ^testing.T,
                        input: string,
                        data: Data,
                        exp_output: string,
                        partials := Map{},
                        loc := #caller_location) {
  output, _ := render(input, data, partials)
  // fmt.println("Input   :", input)
  // fmt.println("Expected:", exp_output)
  // fmt.println("Output  :", output)
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
    input := load_json(data)

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
    input := load_json(data)

    assert_mustache(t, template, input, exp_output)
  }
}

// @(test)
// test_sections_spec :: proc(t: ^testing.T) {
//   spec := load_spec(SECTIONS_SPEC)
//   defer json.destroy_value(spec)

//   root := spec.(json.Object)
//   tests := root["tests"].(json.Array)

//   for test, i in tests {
//     test_obj := test.(json.Object)
//     test_name := test_obj["name"].(string)
//     test_desc := test_obj["desc"].(string)
//     template := test_obj["template"].(string)
//     exp_output := test_obj["expected"].(string)
//     data := test_obj["data"]
//     input := load_json(data)

//     // TODO: Only print the name & desc if the test FAILS.
//     // fmt.println("*************************")
//     // fmt.println(test_name, "-", test_desc)
//     // fmt.println(data)
//     // fmt.println("Input:", template)
//     // fmt.println("Expected:", exp_output)
//     assert_mustache(t, template, input, exp_output)
//   }
// }

// @(test)
// test_inverted_spec :: proc(t: ^testing.T) {
//   spec := load_spec(INVERTED_SPEC)
//   defer json.destroy_value(spec)

//   root := spec.(json.Object)
//   tests := root["tests"].(json.Array)

//   for test, i in tests {
//     test_obj := test.(json.Object)
//     test_name := test_obj["name"].(string)
//     test_desc := test_obj["desc"].(string)
//     template := test_obj["template"].(string)
//     exp_output := test_obj["expected"].(string)
//     data := test_obj["data"]
//     input := load_json(data)

//     assert_mustache(t, template, input, exp_output)
//   }
// }

// @(test)
// test_partials_spec :: proc(t: ^testing.T) {
//   spec := load_spec(PARTIALS_SPEC)
//   defer json.destroy_value(spec)

//   root := spec.(json.Object)
//   tests := root["tests"].(json.Array)

//   for test, i in tests {
//     test_obj := test.(json.Object)
//     template := test_obj["template"].(string)
//     exp_output := test_obj["expected"].(string)
//     data := test_obj["data"]
//     input := load_json(data)
//     partials := test_obj["partials"]
//     partials_input := load_json(partials).(Map)
//     assert_mustache(t, template, input, exp_output, partials_input)
//   }
// }

// // @(test)
// // test_delimiters_spec :: proc(t: ^testing.T) {
// //   spec := load_spec(DELIMITERS_SPEC)
// //   defer json.destroy_value(spec)

// //   root := spec.(json.Object)
// //   tests := root["tests"].(json.Array)

// //   for test, i in tests {
// //     if i > 0 do break

// //     test_obj := test.(json.Object)
// //     test_name := test_obj["name"].(string)
// //     test_desc := test_obj["desc"].(string)
// //     template := test_obj["template"].(string)
// //     exp_output := test_obj["expected"].(string)
// //     data := test_obj["data"]
// //     input := load_json(data)

// //     // Not all the test cases have partials.
// //     partials := test_obj["partials"]
// //     partials_input, ok := load_json(partials).(Map)
// //     if !ok {
// //       partials_input = Map{}
// //     }

// //     assert_mustache(t, template, input, exp_output, partials_input)
// //   }
// // }
