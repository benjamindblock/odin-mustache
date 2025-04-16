#+feature dynamic-literals

package mustache

import "base:runtime"

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:testing"

COMMENTS_SPEC :: "spec/specs/comments.json"
DELIMITERS_SPEC :: "spec/specs/delimiters.json"
INTERPOLATION_SPEC :: "spec/specs/interpolation.json"
INVERTED_SPEC :: "spec/specs/inverted.json"
PARTIALS_SPEC :: "spec/specs/partials.json"
SECTIONS_SPEC :: "spec/specs/sections.json"

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

// 1. A map from string => JSON_Data
// 2. A list of JSON_Data
// 3. A value of some kind (string, int, etc.)
JSON_Map :: distinct map[string]JSON_Data
JSON_List :: distinct [dynamic]JSON_Data
JSON_Data :: union {
	JSON_Map,
	JSON_List,
	string,
}

load_json :: proc(val: json.Value) -> (loaded: JSON_Data) {
	context.allocator = context.temp_allocator

	switch _val in val {
	case bool, string:
		v := fmt.tprintf("%v", _val)
		loaded = v
	case i64, f64:
		str := fmt.tprintf("%.2f", val)
		decimal_str := trim_decimal_string(str)
		loaded = decimal_str
	case json.Object:
		data := make(JSON_Map)
		for k, v in _val {
			new_k := fmt.tprintf("%v", k)
			data[new_k] = load_json(v)
		}
		loaded = data
	case json.Array:
		data := make(JSON_List)
		for v in _val {
			append(&data, load_json(v))
		}
		loaded = data
	case json.Null:
	}

	return loaded
}

load_spec :: proc(filename: string) -> (json.Value) {
	context.allocator = context.temp_allocator

	data, ok := os.read_entire_file_from_filename(filename)
	if !ok {
		fmt.println("Failed to load the file!")
		os.exit(1)
	}

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
	exp := #caller_expression(actual),
	loc := #caller_location,
) {
	testing.expect(t, actual, msg, exp, loc)
}

assert_not :: proc(
	t: ^testing.T,
	actual: bool,
	msg: string,
	exp := #caller_expression(actual),
	loc := #caller_location,
) {
	testing.expect(t, !actual, msg, exp, loc)
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

	delete(output)
}

@(test)
test_render :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "Hello, {{x}}, nice to meet you. My name is {{y}}."

	data := make(Test_Map, 2)
	data["x"] = "Vincent"
	data["y"] = "R2D2"

	exp_output := "Hello, Vincent, nice to meet you. My name is R2D2."
	output, _ := render(template, data)
	testing.expect_value(t, output, exp_output)

	delete(output)
}

@(test)
test_render_in_layout :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "Hello, {{x}}, nice to meet you. My name is {{y}}."

	data := make(Test_Map, 2)
	data["x"] = "Vincent"
	data["y"] = "R2D2"

	layout := "\nAbove.\n{{content}}\nBelow."

	exp_output := "\nAbove.\nHello, Vincent, nice to meet you. My name is R2D2.\nBelow."
	output, _ := render_in_layout(template, data, layout)
	testing.expect_value(t, output, exp_output)

	delete(output)
}

@(test)
test_render_in_layout_with_data_for_layout :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "Hello"

	data := make(Test_Map, 1, context.temp_allocator)
	data["x"] = "42"

	layout := "\n{{x}}\n{{content}}\n"

	exp_output := "\n42\nHello\n"
	output, _ := render_in_layout(template, data, layout)
	testing.expect_value(t, output, exp_output)

	delete(output)
}

@(test)
test_render_in_layout_file :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "Hello, {{name}}."
	data := make(Test_Map, 1, context.temp_allocator)
	data["name"] = "Vincent"
	layout := "test/layout.txt"

	exp_output := "Begin layout >>\nHello, Vincent.\n<< End layout\n"
	output, _ := render_in_layout_file(template, data, layout)
	testing.expect_value(t, output, exp_output)

	delete(output)
}

@(test)
test_render_from_filename :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "test/template.txt"
	data := make(Test_Map, 1, context.temp_allocator)
	data["name"] = "Vincent"

	exp_output := "Hello, this is Vincent.\n"
	output, _ := render_from_filename(template, data)
	testing.expect_value(t, output, exp_output)

	delete(output)
}

@(test)
test_render_from_filename_in_layout :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "test/template.txt"
	data := make(Test_Map, 1, context.temp_allocator)
	data["name"] = "Vincent"
	layout := "\nAbove.\n{{content}}\nBelow."

	exp_output := "\nAbove.\nHello, this is Vincent.\nBelow."
	output, _ := render_from_filename_in_layout(template, data, layout)
	testing.expect_value(t, output, exp_output)

	delete(output)
}

@(test)
test_render_from_filename_in_layout_file :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "test/template.txt"
	data := make(Test_Map, 1, context.temp_allocator)
	data["name"] = "Vincent"
	layout := "test/layout.txt"

	exp_output := "Begin layout >>\nHello, this is Vincent.\n<< End layout\n"
	output, _ := render_from_filename_in_layout_file(template, data, layout)
	testing.expect_value(t, output, exp_output)

	delete(output)
}

@(test)
test_render_with_json :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "Hello, {{name}}."
	json := "test/data.json"

	exp_output := "Hello, Kilgarvan."
	output, _ := render_with_json(template, json)
	testing.expect_value(t, output, exp_output)

	defer(delete(output))
}

@(test)
test_render_with_json_in_layout :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "Hello, {{name}}."
	json := "test/data.json"
	layout := "\nAbove.\n{{content}}\nBelow."

	exp_output := "\nAbove.\nHello, Kilgarvan.\nBelow."
	output, _ := render_with_json_in_layout(template, json, layout)
	testing.expect_value(t, output, exp_output)

	delete(output)
}

@(test)
test_render_with_json_in_layout_file :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "Hello, {{name}}."
	json := "test/data.json"
	layout := "test/layout.txt"

	exp_output := "Begin layout >>\nHello, Kilgarvan.\n<< End layout\n"
	output, _ := render_with_json_in_layout_file(template, json, layout)
	testing.expect_value(t, output, exp_output)

	delete(output)
}

@(test)
test_render_from_filename_with_json_in_layout :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "test/template.txt"
	json := "test/data.json"
	layout := "\nAbove.\n{{content}}\nBelow."

	exp_output := "\nAbove.\nHello, this is Kilgarvan.\nBelow."
	output, _ := render_from_filename_with_json_in_layout(template, json, layout)
	testing.expect_value(t, output, exp_output)

	delete(output)
}

@(test)
test_render_from_filename_with_json_in_layout_file :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "test/template.txt"
	json := "test/data.json"
	layout := "test/layout.txt"

	exp_output := "Begin layout >>\nHello, this is Kilgarvan.\n<< End layout\n"
	output, _ := render_from_filename_with_json_in_layout_file(template, json, layout)
	testing.expect_value(t, output, exp_output)

	delete(output)
}

@(test)
test_struct :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "Hello, {{name}}. Send an email to {{email}}."
	data := Test_Struct {"Vincent", "foo@example.com"}
	exp_output := "Hello, Vincent. Send an email to foo@example.com."
	assert_mustache(t, template, data, exp_output)
}

@(test)
test_struct_union :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "Hello, {{name}}. Send an email to {{email}}."
	data: Test_Data
	data = Test_Struct {"Vincent", "foo@example.com"}
	exp_output := "Hello, Vincent. Send an email to foo@example.com."
	assert_mustache(t, template, data, exp_output)
}

@(test)
test_struct_inside_map :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "Hello, {{name}}. Send an email to {{#email}}{{address}}{{/email}}."

	data := make(map[string]Test_Data, 2, context.temp_allocator)
	data["name"] = "Vincent"
	data["email"] = make(Test_Map, 1, context.temp_allocator)
	email := data["email"].(Test_Map)
	email["address"] = "foo@example.com"
	data["email"] = email

	exp_output := "Hello, Vincent. Send an email to foo@example.com."
	assert_mustache(t, template, data, exp_output)
}

@(test)
test_list :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "{{#names}}{{.}}{{/names}}"

	data := make(map[string][dynamic]string, 1, context.temp_allocator)
	names := make([dynamic]string, 2, context.temp_allocator)
	append(&names, "Helena", " Bloomington")
	data["names"] = names

	exp_output := "Helena Bloomington"
	assert_mustache(t, template, data, exp_output)
}

@(test)
test_no_interpolation :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "Hello, {Mustache}!"
	data := ""
	exp_output := "Hello, {Mustache}!"
	assert_mustache(t, template, data, exp_output)
}

@(test)
test_literal_tag :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	template := "Hello, {{{verb1}}}."
	data := Test_Map {
		"verb1" = "I like < >",
	}
	defer(delete(data))

	exp_output := "Hello, I like < >."
	assert_mustache(t, template, data, exp_output)
}

@(test)
test_interpolation_spec :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

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
	context.allocator = context.temp_allocator

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
	context.allocator = context.temp_allocator

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
	context.allocator = context.temp_allocator

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
	context.allocator = context.temp_allocator

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
	context.allocator = context.temp_allocator

	// Get the value in a map with one key.
	output: any
	mss := make(map[string]string)
	mcs := make(map[cstring]string)
	msi := make(map[string]int)
	mis := make(map[int]string)

	tm := make(Test_Map)
	mtm := make(map[string]Test_Map)

	u: Test_Data
	u = make(Test_Map)

	// Simple map
	delete(mss)
	mss["name"] = "George"
	output, _ = map_get(mss, "name")
	testing.expect_value(t, output.(string), "George")

	// Get the value in a map with one key when key is cstring.
	delete(mcs)
	mcs["name"] = "George"
	output, _ = map_get(mcs, "name")
	testing.expect_value(t, output.(string), "George")

	// Get the first value in a map with multiple keys.
	delete(mss)
	mss["name"] = "George"
	mss["hometown"] = "Helena"
	output, _ = map_get(mss, "name")
	testing.expect_value(t, output.(string), "George")

	// Get the second value in a map with multiple keys.
	delete(mss)
	mss["name"] = "George"
	mss["hometown"] = "Helena"
	output, _ = map_get(mss, "hometown")
	testing.expect_value(t, output.(string), "Helena")

	// Get an int
	delete(msi)
	msi["phone_number"] = 5555555555
	output, _ = map_get(msi, "phone_number")
	testing.expect_value(t, output.(int), 5555555555)

	// Nested, named map.
	delete(tm)
	delete(mtm)
	tm["name"] = "Lee"
	mtm["person"] = tm
	output, _ = map_get(mtm, "person")
	testing.expect_value(t, output.(Test_Map)["name"], tm["name"])

	// Extract from a map type inside a union.
	delete(u.(Test_Map))
	(&u.(Test_Map))["name"] = "St. Charles"
	output, _ = map_get(u, "name")
	testing.expect_value(t, output.(string), u.(Test_Map)["name"])

	// Return nil when the map is NOT keyed by string, cstring
	delete(mis)
	mis[1] = "Customer 1"
	output, _ = map_get(mis, "1")
	testing.expect(t, reflect.is_nil(output))
}

@(test)
test_struct_get :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

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

	test_map := make(Test_Map)
	test_map["name"] = "Lee"
	output = struct_get(test_map, "name")
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
	context.allocator = context.temp_allocator

	m := map[string]string{"Vincent" = "Edgar"}
	assert(t, is_map(m), "Regular map should return true")
	delete(m)

	m = Test_Map{"name" = "Lee"}
	assert(t, is_map(m), "Named map should return true")
	delete(m)

	data: Test_Data
	data = Test_Map{ "name" = "Vincent" }
	assert(
		t,
		is_map(data),
		"Union with Map variant should be considered a Map",
	)
	delete(data.(Test_Map))

	data = Test_List{ "foo", "bar", "baz" }
	assert_not(
		t,
		is_map(data),
		"Union with list variant should not be considered a Map",
	)
	delete(data.(Test_List))

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
	context.allocator = context.temp_allocator

	arr := [1]string{"element1"}
	assert(t, is_list(arr), "Array should be considered a list")
	assert(t, is_list(arr[:]), "Slice should be considered a list")

	dyn_arr := make([dynamic]string, 1, 1)
	append(&dyn_arr, "element1")
	assert(t, is_list(dyn_arr), "Dynamic array should be considered a list")

	u_arr: Test_Data
	u_arr = make(Test_List, 1, 1)
	append(&u_arr.(Test_List), "element1")
	assert(t, is_list(u_arr), "Dynamic array in a union should be considered a list")

	assert_not(t, is_list("foo"), "string should not be considered a list")
	assert_not(t, is_list(1), "int should not be considered a list")

	u_map: Test_Data
	u_map = make(Test_Map, 1)
	assert_not(
		t,
		is_list(u_map),
		"Map in union that has list type should not be considered a list",
	)
}

@(test)
test_is_struct :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

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
	data = make(Test_Map)
	assert_not(
		t,
		is_struct(data),
		"Union with map variant should not be considered a Struct",
	)

	data = make(Test_List)
	append(&data.(Test_List), "foo", "bar", "baz")
	assert_not(
		t,
		is_struct(data),
		"Union with list variant should not be considered a Struct",
	)
}

@(test)
test_is_union :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	u: Test_Data
	u = make(Test_Map)
	assert(
		t,
		is_union(u),
		"Union is union",
	)


	tm := make(Test_Map)
	assert_not(
		t,
		is_union(tm),
		"Union member with a type is not a union",
	)

	tl := make(Test_List)
	assert_not(
		t,
		is_union(tl),
		"Union member with a type is not a union",
	)

	m := make(map[string]string)
	assert_not(
		t,
		is_union(m),
		"Map should not be a union",
	)

	ts := Test_Struct{"Vincent", "foo@example.com"}
	assert_not(
		t,
		is_union(ts),
		"Struct should not be a union",
	)
}

@(test)
test_data_len :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	data: any

	data = make([dynamic]string)
	testing.expect_value(t, data_len(data), 0)

	data = make([dynamic]string)
	append(&data.([dynamic]string), "Vincent")
	testing.expect_value(t, data_len(data), 1)

	data = "FooBar"
	testing.expect_value(t, data_len(data), 6)

	data = Test_Struct{"Vincent", "foo@example.com"}
	testing.expect_value(t, data_len(data), 2)

	u: Test_Data
	u = Test_Struct{"Vincent", "foo@example.com"}
	testing.expect_value(t, data_len(u), 2)

	u = make(Test_Map)
	(&u.(Test_Map))["name"] = "St. Charles"
	testing.expect_value(t, data_len(u), 1)
}

@(test)
test_has_key :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

	data: any

	data = Test_Struct{"St. Charles", "foo@example.com"}
	assert(t, has_key(data, "name"), "Should return true if stuct has field")

	data = make(map[string]int)
	(&data.(map[string]int))["A1"] = 1
	assert(t, has_key(data, "A1"), "Should return true if map has key")
	assert_not(t, has_key(data, "B2"), "Should return false if map does not have key")

	u: Test_Data
	u = make(Test_Map)
	(&u.(Test_Map))["name"] = "St. Charles"
	assert(t, has_key(u, "name"), "Should return true if union-map has key")
	assert_not(t, has_key(u, "email"), "Should return false if union-map does not have key")

	u = Test_Struct{"St. Charles", "foo@example.com"}
	assert(t, has_key(u, "name"), "Should return true if union-struct has key")
	assert_not(t, has_key(u, "XXX"), "Should return false if union-struct does not have key")
}

@(test)
test_list_at :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator

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
	context.allocator = context.temp_allocator

	output: any
	keys := make([dynamic]string)

	// Pull out a struct value
	d1: any
	d1 = Test_Struct{"Vincent", "foo@example.com"}
	append(&keys, "name")
	output = dig(d1, keys[:])
	testing.expect_value(t, output.(string), "Vincent")
	delete(keys)

	// Pull out a map value
	d2: any
	d2 = make(map[string]string)
	(&d2.(map[string]string))["name"] = "Edgar"
	keys = {"name"}
	output = dig(d2, keys[:])
	testing.expect_value(t, output.(string), "Edgar")
	delete(keys)

	// Pull out a nested map value
	d3: any
	d3 = make(map[string]map[string]string)
	c1 := make(map[string]string)
	c1["name"] = "Kurt"
	c1["email"] = "test@example.com"
	(&d3.(map[string]map[string]string))["customer1"] = c1
	keys = {"customer1", "email"}
	output = dig(d3, keys[:])
	testing.expect_value(t, output.(string), "test@example.com")
	delete(keys)

	// Pull out a nested map
	d4 := make(map[string]map[string]string)
	c2 := make(map[string]string)
	c2["name"] = "Kurt"
	c2["email"] = "test@example.com"
	d4["customer1"] = c2
	keys = {"customer1"}
	output = dig(d4, keys[:])
	testing.expect_value(t, output.(map[string]string)["name"], "Kurt")
	testing.expect_value(t, output.(map[string]string)["email"], "test@example.com")
	delete(keys)

	// Pull out a list
	d5: any
	d5 = Test_List{"El1", "El2"}
	keys = {"key1"}
	output = dig(d5, keys[:])
	testing.expect_value(t, output.(Test_List)[0], d5.(Test_List)[0])
	testing.expect_value(t, output.(Test_List)[1], d5.(Test_List)[1])
	delete(d5.(Test_List))
	delete(keys)

	// Pull out a struct inside a map
	d6: any
	d6 = make(map[string]Test_Struct)
	c3 := Test_Struct{"Vincent", "foo@example.com"}
	(&d6.(map[string]Test_Struct))["customer1"] = c3
	keys = {"customer1", "email"}
	output = dig(d6, keys[:])
	testing.expect_value(t, output.(string), "foo@example.com")
	delete(keys)

	// Pull out a string with dot notation
	d7 := "Hello, world!"
	keys = {"."}
	output = dig(d7, keys[:])
	testing.expect_value(t, output.(string), "Hello, world!")
	delete(keys)

	// Return nil when string and not dot notation.
	d8 := "Hello, world!"
	keys = {"XXX"}
	output = dig(d8, keys[:])
	assert(t, reflect.is_nil(output), "Nil string when a key that is not '.' is provided.")
	delete(keys)

	// Pull out a nil struct value
	d9 := Test_Struct{"Vincent", "foo@example.com"}
	keys = {"XXX"}
	output = dig(d9, keys[:])
	assert(t, reflect.is_nil(output), "Struct without a matching field should be nil")
	delete(keys)

	// Pull out a nil struct value with multiple keys
	d10 := Test_Struct{"Vincent", "foo@example.com"}
	keys = {"XXX", "YYY"}
	output = dig(d10, keys[:])
	assert(t, reflect.is_nil(output), "Struct without a matching field should be nil")
	delete(keys)

	// Pull out a nil struct value
	d11 := make(map[string]string)
	d11["name"] = "Vincent"
	keys = {"XXX"}
	output = dig(d11, keys[:])
	assert(t, reflect.is_nil(output), "Map without a matching field should be nil")
	delete(keys)
}
