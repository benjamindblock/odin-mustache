package mustache

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:testing"

COMMENTS_SPEC :: "spec/comments.json"
DELIMITERS_SPEC :: "spec/delimiters.json"
INTERPOLATION_SPEC :: "spec/interpolation.json"
INVERTED_SPEC :: "spec/inverted.json"
PARTIALS_SPEC :: "spec/partials.json"
SECTIONS_SPEC :: "spec/sections.json"

Test_Struct :: struct {
	name: string,
	email: string,
}
Test_Map :: map[string]string
Test_List :: [dynamic]string
Test_Data :: union {
	Test_Struct,
	Test_Map,
	Test_List,
	string,
}

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

assert :: proc(
	t: ^testing.T,
	actual: bool,
	msg: string,
	loc := #caller_location,
) {
	testing.expect(t, actual, msg, loc)
}

assert_not :: proc(
	t: ^testing.T,
	actual: bool,
	msg: string,
	loc := #caller_location,
) {
	testing.expect(t, !actual, msg, loc)
}

assert_mustache :: proc(
	t: ^testing.T,
	input: string,
	data: any,
	exp_output: string,
	partials: any = map[string]string{},
	loc := #caller_location,
) {
	output, _ := render(input, data, partials)
	testing.expect_value(t, output, exp_output, loc)
}

@(test)
test_basic :: proc(t: ^testing.T) {
	template := "Hello, {{x}}, nice to meet you. My name is {{y}}."
	data := Test_Map {
		"x" = "Vincent",
		"y" = "R2D2",
	}
	exp_output := "Hello, Vincent, nice to meet you. My name is R2D2."
	assert_mustache(t, template, data, exp_output)
}

@(test)
test_layout :: proc(t: ^testing.T) {
	template := "Hello, {{x}}, nice to meet you. My name is {{y}}."
	data := Test_Map {
		"x" = "Vincent",
		"y" = "R2D2",
	}
	partials: any = map[string]string{}
	layout := "\nAbove.\n{{content}}\nBelow."

	exp_output := "\nAbove.\nHello, Vincent, nice to meet you. My name is R2D2.\nBelow."
	output, _ := render_in_layout(template, data, partials, layout)
	testing.expect_value(t, output, exp_output)
}

@(test)
test_struct :: proc(t: ^testing.T) {
	template := "Hello, {{name}}. Send an email to {{email}}."
	data := Test_Struct {"Vincent", "foo@example.com"}
	exp_output := "Hello, Vincent. Send an email to foo@example.com."
	assert_mustache(t, template, data, exp_output)
}

@(test)
test_struct_union :: proc(t: ^testing.T) {
	template := "Hello, {{name}}. Send an email to {{email}}."
	data: Test_Data
	data = Test_Struct {"Vincent", "foo@example.com"}
	exp_output := "Hello, Vincent. Send an email to foo@example.com."
	assert_mustache(t, template, data, exp_output)
}

@(test)
test_struct_inside_map :: proc(t: ^testing.T) {
	template := "Hello, {{name}}. Send an email to {{#email}}{{address}}{{/email}}."

	data: map[string]Test_Data = {
		"name" = "Vincent",
		"email" = Test_Map {
			"address" = "foo@example.com",
		},
	}

	exp_output := "Hello, Vincent. Send an email to foo@example.com."
	assert_mustache(t, template, data, exp_output)
}

@(test)
test_list :: proc(t: ^testing.T) {
	template := "{{#names}}{{.}}{{/names}}"
	data := map[string][dynamic]string {
		"names" = [dynamic]string{"Helena", " Bloomington"},
	}

	exp_output := "Helena Bloomington"
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
	data := Test_Map {
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

	for test in tests {
		test_obj := test.(json.Object)
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

	for test in tests {
		test_obj := test.(json.Object)
		template := test_obj["template"].(string)
		exp_output := test_obj["expected"].(string)
		data := test_obj["data"]
		input := load_json(data)

		assert_mustache(t, template, input, exp_output)
	}
}

@(test)
test_sections_spec :: proc(t: ^testing.T) {
	spec := load_spec(SECTIONS_SPEC)
	defer json.destroy_value(spec)

	root := spec.(json.Object)
	tests := root["tests"].(json.Array)

	for test in tests {
		test_obj := test.(json.Object)
		template := test_obj["template"].(string)
		exp_output := test_obj["expected"].(string)
		data := test_obj["data"]
		input := load_json(data)

		assert_mustache(t, template, input, exp_output)
	}
}

@(test)
test_inverted_spec :: proc(t: ^testing.T) {
	spec := load_spec(INVERTED_SPEC)
	defer json.destroy_value(spec)

	root := spec.(json.Object)
	tests := root["tests"].(json.Array)

	for test in tests {
		test_obj := test.(json.Object)
		template := test_obj["template"].(string)
		exp_output := test_obj["expected"].(string)
		data := test_obj["data"]
		input := load_json(data)

		assert_mustache(t, template, input, exp_output)
	}
}

@(test)
test_partials_spec :: proc(t: ^testing.T) {
	spec := load_spec(PARTIALS_SPEC)
	defer json.destroy_value(spec)

	root := spec.(json.Object)
	tests := root["tests"].(json.Array)

	for test in tests {
		test_obj := test.(json.Object)
		template := test_obj["template"].(string)
		exp_output := test_obj["expected"].(string)
		data := test_obj["data"]
		input := load_json(data)
		partials := test_obj["partials"]
		partials_input := load_json(partials).(JSON_Map)
		assert_mustache(t, template, input, exp_output, partials_input)
	}
}

// TODO: Someday.
// @(test)
// test_delimiters_spec :: proc(t: ^testing.T) {
//   spec := load_spec(DELIMITERS_SPEC)
//   defer json.destroy_value(spec)

//   root := spec.(json.Object)
//   tests := root["tests"].(json.Array)

//   for test, i in tests {
//     if i > 0 do break

//     test_obj := test.(json.Object)
//     test_name := test_obj["name"].(string)
//     test_desc := test_obj["desc"].(string)
//     template := test_obj["template"].(string)
//     exp_output := test_obj["expected"].(string)
//     data := test_obj["data"]
//     input := load_json(data)

//     // Not all the test cases have partials.
//     partials := test_obj["partials"]
//     partials_input, ok := load_json(partials).(Map)
//     if !ok {
//       partials_input = Map{}
//     }

//     assert_mustache(t, template, input, exp_output, partials_input)
//   }
// }

@(test)
test_map_get :: proc(t: ^testing.T) {
	// Get the value in a map with one key.
	output: any
	output, _ = map_get(
		map[string]string{"name" = "George"},
		"name",
	)
	testing.expect_value(t, output.(string), "George")

	// Get the value in a map with one key when key is cstring.
	output, _ = map_get(
		map[cstring]string{"name" = "George"},
		"name",
	)
	testing.expect_value(t, output.(string), "George")

	// Get the first value in a map with multiple keys.
	output, _ = map_get(
		map[string]string{
			"name" = "George",
			"hometown" = "Helena",
		},
		"name",
	)
	testing.expect_value(t, output.(string), "George")

	// Get the second value in a map with multiple keys.
	output, _ = map_get(
		map[string]string{
			"name" = "George",
			"hometown" = "Helena",
		},
		"hometown",
	)
	testing.expect_value(t, output.(string), "Helena")

	// Get an int
	output, _ = map_get(
		map[string]int{"phone_number" = 5555555555},
		"phone_number",
	)
	testing.expect_value(t, output.(int), 5555555555)

	// Nested, named map.
	data := Test_Map{"name" = "Lee"}
	output, _ = map_get(
		map[string]Test_Map{"person" = data},
		"person",
	)
	testing.expect_value(t, output.(Test_Map)["name"], data["name"])

	// Extract from a map type inside a union.
	u_map: Test_Data
	u_map = Test_Map{"name" = "St. Charles"}
	output, _ = map_get(u_map, "name")
	testing.expect_value(t, output.(string), u_map.(Test_Map)["name"])

	// Return nil when the map is NOT keyed by string, cstring
	output, _ = map_get(map[int]string{1 = "Customer 1"}, "1")
	testing.expect(t, reflect.is_nil(output))
}

@(test)
test_struct_get :: proc(t: ^testing.T) {
	output: any

	data := Test_Struct{"Vincent", "foo@example.com"}
	output = struct_get(data, "name")
	testing.expect_value(t, output.(string), "Vincent")

	output = struct_get(data, "email")
	testing.expect_value(t, output.(string), "foo@example.com")

	output = struct_get("foo", "email")
	testing.expect(
		t,
		reflect.is_nil(output),
		"String argument that is NOT a Struct returns nil",
	)

	output = struct_get(Test_Map{"name" = "Lee"}, "name")
	testing.expect(
		t,
		reflect.is_nil(output),
		"Map argument that is NOT a Struct returns nil",
	)

	// Extract from a map type inside a union.
	u_struct: Test_Data
	u_struct = Test_Struct{"St. Charles", "foo@example.com"}
	output = struct_get(u_struct, "name")
	testing.expect_value(t, output.(string), u_struct.(Test_Struct).name)
}

@(test)
test_is_map :: proc(t: ^testing.T) {
	assert(
		t,
		is_map(map[string]string{"Vincent" = "Edgar"}),
		"Regular map should return true",
	)

	assert(
		t,
		is_map(Test_Map{"name" = "Lee"}),
		"Named map should return true",
	)

	data: Test_Data
	data = Test_Map{ "name" = "Vincent" }
	assert(
		t,
		is_map(data),
		"Union with Map variant should be considered a Map",
	)

	data = Test_List{ "foo", "bar", "baz" }
	assert_not(
		t,
		is_map(data),
		"Union with list variant should not be considered a Map",
	)

	assert_not(
		t,
		is_map(Test_Struct{"Vincent", "foo@example.com"}),
		"Struct should not be a map",
	)

	u: Test_Data
	u = Test_Struct{"Vincent", "foo@example.com"}
	assert_not(
		t,
		is_map(u),
		"Struct variant of a Union should not be considered a Map",
	)
}

@(test)
test_is_list :: proc(t: ^testing.T) {
	arr := [1]string{"element1"}
	assert(t, is_list(arr), "Array should be considered a list")
	assert(t, is_list(arr[:]), "Slice should be considered a list")

	dyn_arr := [dynamic]string{"element1"}
	assert(t, is_list(dyn_arr), "Dynamic array should be considered a list")

	u_arr: Test_Data
	u_arr = Test_List{"element1"}
	assert(t, is_list(u_arr), "Dynamic array in a union should be considered a list")

	assert_not(t, is_list("foo"), "string should not be considered a list")
	assert_not(t, is_list(1), "int should not be considered a list")

	u_map: Test_Data
	u_map = Test_Map{"name" = "Sal"}
	assert_not(
		t,
		is_list(u_map),
		"Map in union that has list type should not be considered a list",
	)
}

@(test)
test_is_struct :: proc(t: ^testing.T) {
	assert(
		t,
		is_struct(Test_Struct{"Vincent", "foo@example.com"}),
		"Struct should be considered a Struct",
	)

	u: Test_Data
	u = Test_Struct{"Vincent", "foo@example.com"}
	assert(
		t,
		is_struct(u),
		"Struct variant of a union should be considered a Struct",
	)

	data: Test_Data
	data = Test_Map{"name" = "Vincent"}
	assert_not(
		t,
		is_struct(data),
		"Union with map variant should not be considered a Struct",
	)

	data = Test_List{"foo", "bar", "baz"}
	assert_not(
		t,
		is_struct(data),
		"Union with list variant should not be considered a Struct",
	)
}

@(test)
test_is_union :: proc(t: ^testing.T) {
	data: Test_Data
	data = Test_Map{ "name" = "Vincent" }
	assert(
		t,
		is_union(data),
		"Union is union",
	)

	assert_not(
		t,
		is_union(Test_Map{"name" = "Vincent"}),
		"Union member with a type is not a union",
	)

	assert_not(
		t,
		is_union(Test_List{"foo", "bar", "baz"}),
		"Union member with a type is not a union",
	)

	assert_not(
		t,
		is_union(map[string]string{"Vincent" = "Edgar"}),
		"Map should not be a union",
	)

	assert_not(
		t,
		is_union(Test_Struct{"Vincent", "foo@example.com"}),
		"Struct should not be a union",
	)

	assert_not(
		t,
		is_union(Test_Map{"name" = "Lee"}),
		"Named map should not be a union",
	)
}

@(test)
test_data_len :: proc(t: ^testing.T) {
	data: any

	data = [dynamic]string{}
	testing.expect_value(t, data_len(data), 0)

	data = [dynamic]string{"Vincent"}
	testing.expect_value(t, data_len(data), 1)

	data = "FooBar"
	testing.expect_value(t, data_len(data), 6)

	data = Test_Struct{"Vincent", "foo@example.com"}
	testing.expect_value(t, data_len(data), 2)

	u: Test_Data
	u = Test_Struct{"Vincent", "foo@example.com"}
	testing.expect_value(t, data_len(u), 2)

	u = Test_Map{"name" = "St. Charles"}
	testing.expect_value(t, data_len(u), 1)
}

@(test)
test_has_key :: proc(t: ^testing.T) {
	data: any

	data = Test_Struct{"St. Charles", "foo@example.com"}
	assert(t, has_key(data, "name"), "Should return true if stuct has field")

	data = map[string]int{"A1" = 1}
	assert(t, has_key(data, "A1"), "Should return true if map has key")
	assert_not(t, has_key(data, "B2"), "Should return false if map does not have key")

	u: Test_Data
	u = Test_Map{"name" = "St. Charles"}
	assert(t, has_key(u, "name"), "Should return true if union-map has key")
	assert_not(t, has_key(u, "email"), "Should return false if union-map does not have key")

	u = Test_Struct{"St. Charles", "foo@example.com"}
	assert(t, has_key(u, "name"), "Should return true if union-struct has key")
	assert_not(t, has_key(u, "XXX"), "Should return false if union-struct does not have key")
}

@(test)
test_list_at :: proc(t: ^testing.T) {
	arr := [2]string{"foo", "bar"}
	testing.expect_value(t, list_at(arr, 0).(string), "foo")
	testing.expect_value(t, list_at(arr, 1).(string), "bar")

	testing.expect_value(t, list_at(arr[:], 0).(string), "foo")
	testing.expect_value(t, list_at(arr[:], 1).(string), "bar")

	dyn := slice.clone_to_dynamic(arr[:])
	testing.expect_value(t, list_at(dyn, 0).(string), "foo")
	testing.expect_value(t, list_at(dyn, 1).(string), "bar")
}

@(test)
test_dig :: proc(t: ^testing.T) {
	output: any
	data: any
	keys: [dynamic]string

	// Pull out a struct value
	data = Test_Struct{"Vincent", "foo@example.com"}
	keys = {"name"}
	output = dig(data, keys[:])
	testing.expect_value(t, output.(string), "Vincent")

	// Pull out a map value
	data = map[string]string {
		"name" = "Edgar",
	}
	keys = {"name"}
	output = dig(data, keys[:])
	testing.expect_value(t, output.(string), "Edgar")

	// Pull out a nested map value
	data = map[string]map[string]string {
		"customer1" = map[string]string {
			"name" = "Kurt",
			"email" = "test@example.com",
		},
	}
	keys = {"customer1", "email"}
	output = dig(data, keys[:])
	testing.expect_value(t, output.(string), "test@example.com")

	// Pull out a nested map
	nested := map[string]string {
		"name" = "Kurt",
		"email" = "test@example.com",
	}
	data = map[string]map[string]string {
		"customer1" = nested,
	}
	keys = {"customer1"}
	output = dig(data, keys[:])
	testing.expect_value(t, output.(map[string]string)["name"], nested["name"])
	testing.expect_value(t, output.(map[string]string)["email"], nested["email"])

	// Pull out a list
	data = Test_List{"El1", "El2"}
	keys = {"key1"}
	output = dig(data, keys[:])
	testing.expect_value(t, output.(Test_List)[0], data.(Test_List)[0])
	testing.expect_value(t, output.(Test_List)[1], data.(Test_List)[1])

	// Pull out a struct inside a map
	data = map[string]Test_Struct {
		"customer1" = Test_Struct{"Vincent", "foo@example.com"},
	}
	keys = {"customer1", "email"}
	output = dig(data, keys[:])
	testing.expect_value(t, output.(string), "foo@example.com")

	// Pull out a string with dot notation
	data = "Hello, world!"
	keys = {"."}
	output = dig(data, keys[:])
	testing.expect_value(t, output.(string), "Hello, world!")

	// Return nil when string and not dot notation.
	data = "Hello, world!"
	keys = {"XXX"}
	output = dig(data, keys[:])
	assert(t, reflect.is_nil(output), "Nil string when a key that is not '.' is provided.")

	// Pull out a nil struct value
	data = Test_Struct{"Vincent", "foo@example.com"}
	keys = {"XXX"}
	output = dig(data, keys[:])
	assert(t, reflect.is_nil(output), "Struct without a matching field should be nil")

	// Pull out a nil struct value with multiple keys
	data = Test_Struct{"Vincent", "foo@example.com"}
	keys = {"XXX", "YYY"}
	output = dig(data, keys[:])
	assert(t, reflect.is_nil(output), "Struct without a matching field should be nil")

	// Pull out a nil struct value
	data = map[string]string {
		"name" = "Vincent",
	}
	keys = {"XXX"}
	output = dig(data, keys[:])
	assert(t, reflect.is_nil(output), "Map without a matching field should be nil")
}
