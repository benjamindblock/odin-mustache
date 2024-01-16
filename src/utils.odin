package mustache

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:reflect"
import "core:runtime"
import "core:strings"

// Special characters that will receive HTML-escaping
// treatment, if necessary.
HTML_LESS_THAN :: "&lt;"
HTML_GREATER_THAN :: "&gt;"
HTML_QUOTE :: "&quot;"
HTML_AMPERSAND :: "&amp;"

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
escape_html_string :: proc(s: string, allocator := context.allocator) -> string {
	context.allocator = allocator

	escaped := s
	// Ampersand escaping goes first.
	escaped, _ = strings.replace_all(escaped, "&", HTML_AMPERSAND)
	escaped, _ = strings.replace_all(escaped, "<", HTML_LESS_THAN)
	escaped, _ = strings.replace_all(escaped, ">", HTML_GREATER_THAN)
	escaped, _ = strings.replace_all(escaped, "\"", HTML_QUOTE)
	return escaped
}

// Gets the value of a struct field.
struct_get :: proc(obj: any, key: string) -> any {
	if !is_struct(obj) {
		return nil
	}

	obj := obj
	if is_union(obj) {
		obj = reflect.get_union_variant(obj)
	}

	return reflect.struct_field_value_by_name(obj, key)
}

// Retrieves a value from a map. In mustache.odin, all map keys must be
// string values because we do not know the type of value inside a tag.
//
// Eg., {{name}} -- we assume "name" is either a string key to a map,
// or the name of a field on a struct.
map_get :: proc(v: any, map_key: string) -> (dug: any, err: Template_Error) {
	if !is_map(v) {
		return nil, .Unsupported_Type
	}

	m := (^mem.Raw_Map)(v.data)
	if m == nil {
		return nil, .Unsupported_Type
	}

	v := v
	if is_union(v) {
		v = reflect.get_union_variant(v)
	}

	// Use type_info_base to ensure we get the underlying data structure
	// of a named type if we run into one. Like Map, List, etc.
	base_tinfo := runtime.type_info_base(type_info_of(v.id))
	tinfo := base_tinfo.variant.(runtime.Type_Info_Map)
	map_info := tinfo.map_info

	if map_info == nil {
		return nil, .Unsupported_Type
	}

	map_cap := uintptr(runtime.map_cap(m^))
	ks, vs, hs, _, _ := runtime.map_kvh_data_dynamic(m^, map_info)

	for bucket_index in 0..<map_cap {
		runtime.map_hash_is_valid(hs[bucket_index]) or_continue

		// Accessing the map key.
		key_ptr := rawptr(runtime.map_cell_index_dynamic(ks, map_info.ks, bucket_index))
		key_any := any{key_ptr, tinfo.key.id}
		key_info := runtime.type_info_base(type_info_of(key_any.id))
		key_info_any := any{key_any.data, key_info.id}
		key: string

		// Keys can only be of a string type.
		#partial switch tinfo in key_info.variant {
		case runtime.Type_Info_String:
			switch s in key_info_any {
			case string:
				key = s
			case cstring:
				key = string(s)
			}
		case:
			return nil, .Unsupported_Type
		}

		// Access the value.
		value_ptr := rawptr(runtime.map_cell_index_dynamic(vs, map_info.vs, bucket_index))
		value_any := any{value_ptr, tinfo.value.id}
		value_info := runtime.type_info_base(type_info_of(value_any.id))
		value_info_any := any{value_any.data, value_info.id}
		value := value_info_any

		if map_key == key {
			return value, nil
		}
	}

	return nil, .Map_Key_Not_Found
}

// Checks if an 'any' object is a struct of some kind.
is_struct :: proc(obj: any) -> bool {
	tid: typeid
	tinfo: ^runtime.Type_Info

	if is_union(obj) {
		tid = reflect.union_variant_typeid(obj)
	} else {
		tid = obj.id
	}

	tinfo = type_info_of(tid)
	return reflect.is_struct(tinfo)
}

// Checks if an 'any' object is a union of some kind.
is_union :: proc(obj: any) -> bool {
	tinfo: ^runtime.Type_Info
	base_tinfo: ^runtime.Type_Info

	tinfo = type_info_of(obj.id)
	base_tinfo = runtime.type_info_base(tinfo)
	return reflect.type_kind(base_tinfo.id) == reflect.Type_Kind.Union
}

// Checks if an 'any' object is a map of some kind.
is_map :: proc(obj: any) -> bool {
	tinfo: ^runtime.Type_Info
	id: typeid

	if is_union(obj) {
		id = reflect.union_variant_typeid(obj)
	} else {
		id = obj.id
	}

	tinfo = type_info_of(id)
	return reflect.is_dynamic_map(tinfo)
}

// Checks if an 'any' object is a list of some kind.
is_list :: proc(obj: any) -> bool {
	tinfo: ^runtime.Type_Info
	id: typeid

	if is_union(obj) {
		id = reflect.union_variant_typeid(obj)
	} else {
		id = obj.id
	}

	tinfo = type_info_of(id)
	return reflect.is_array(tinfo) || reflect.is_dynamic_array(tinfo) || reflect.is_slice(tinfo)
}

// Checks if a string is plain whitespace.
is_text_blank :: proc(s: string) -> (res: bool) {
	for r in s {
		if !_whitespace[r] {
			return false
		}
	}

	return true
}

// Retrieves an element from a list (can be of any type -- array,
// dynamic array, slice) at a given index.
list_at :: proc(obj: any, i: int) -> any {
	obj := obj

	if is_union(obj) {
		obj = reflect.get_union_variant(obj)
	}

	if !is_list(obj) {
		return nil
	}

	return reflect.index(obj, i)
}

// Gets the length of a given object.
data_len :: proc(obj: any) -> (l: int) {
	obj := obj

	if is_union(obj) {
		obj = reflect.get_union_variant(obj)
	}

	switch data_type(obj) {
	case .Struct:
		l = len(reflect.struct_field_names(obj.id))
	case .Map, .List, .Value:
		l = reflect.length(obj)
	case .Null:
	}

	return l
}

// Checks if a map has a given key.
map_has_key :: proc(v: any, map_key: string) -> (has: bool) {
	if !is_map(v) {
		return false
	}

	m := (^mem.Raw_Map)(v.data)
	if m == nil {
		return false
	}

	v := v
	if is_union(v) {
		v = reflect.get_union_variant(v)
	}

	// Use type_info_base to ensure we get the underlying data structure
	// of a named type if we run into one. Like Map, List, etc.
	base_tinfo := runtime.type_info_base(type_info_of(v.id))
	tinfo := base_tinfo.variant.(runtime.Type_Info_Map)
	map_info := tinfo.map_info

	if map_info == nil {
		return false
	}

	map_cap := uintptr(runtime.map_cap(m^))
	ks, _, hs, _, _ := runtime.map_kvh_data_dynamic(m^, map_info)

	for bucket_index in 0..<map_cap {
		runtime.map_hash_is_valid(hs[bucket_index]) or_continue

		// Accessing string type in key
		key_ptr := rawptr(runtime.map_cell_index_dynamic(ks, map_info.ks, bucket_index))
		key_any := any{key_ptr, tinfo.key.id}
		key_info := runtime.type_info_base(type_info_of(key_any.id))
		key_info_any := any{key_any.data, key_info.id}
		key: string

		// Validate that the map keys must be of a string or cstring type.
		#partial switch tinfo in key_info.variant {
		case runtime.Type_Info_String:
			switch s in key_info_any {
			case string:
				key = s
			case cstring:
				key = string(s)
			}
		case:
			return false
		}

		if map_key == key {
			return true
		}
	}

	return false
}
