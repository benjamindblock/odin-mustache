package mustache

import "base:runtime"

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:strings"

TRUE :: "true"
FALSEY :: "false"

// Special characters that will receive HTML-escaping
// treatment, if necessary.
HTML_LESS_THAN :: "&lt;"
HTML_GREATER_THAN :: "&gt;"
HTML_QUOTE :: "&quot;"
HTML_AMPERSAND :: "&amp;"

Render_Error :: union {
	Lexer_Error,
	Template_Error,
	File_Not_Found_Error,
	json.Error,
}

File_Not_Found_Error :: struct {
	filename: string,
}

Lexer_Error :: union {
	Unbalanced_Tags,
}

Unbalanced_Tags :: struct {}

Token_Delimiters :: struct {
	otag: string,
	ctag: string,
	otag_lit: string,
	ctag_lit: string,
	otag_section_open: string,
	otag_section_close: string,
	otag_literal: string,
	otag_comment: string,
	otag_inverted: string,
	otag_partial: string,
	otag_delim: string,
	ctag_delim: string,
}

CORE_DEF :: Token_Delimiters {
	otag = "{{",
	ctag = "}}",
	otag_lit = "{{{",
	ctag_lit = "}}}",
	otag_section_open = "{{#",
	otag_section_close = "{{/",
	otag_literal = "{{&",
	otag_comment = "{{!",
	otag_inverted = "{{^",
	otag_partial = "{{>",
	otag_delim = "{{=",
	ctag_delim = "=}}",
}

Token :: struct {
	type: Token_Type,
	value: string,
	pos: Pos,
	iters: int,
	start_i: int,
}

Token_Type :: enum {
	Text,
	Tag,
	Section_Open_Inverted,
	Tag_Literal,
	Tag_Literal_Triple,
	Section_Open,
	Section_Close,
	Comment,
	Partial,
	Newline,
	Skip,
	EOF, // The last token parsed, caller should not call again.
}

Pos :: struct {
	start: int,
	end: int,
	line: int,
}

Lexer :: struct {
	src: string,
	cursor: int,
	line: int,
	tokens: [dynamic]Token,
	cur_token_type: Token_Type,
	cur_token_start_pos: int,
	tag_stack: [dynamic]rune,
	delim: Token_Delimiters,
}

Data_Error :: enum {
	None,
	Unsupported_Type,
	Map_Key_Not_Found,
}

Template_Error :: union {
	Data_Error,
}

Template :: struct {
	lexer: ^Lexer,
	data: any,
	partials: any,
	context_stack: [dynamic]Context_Stack_Entry,
	layout: string,
}

Context_Stack_Entry :: struct {
	data: any,
	label: string,
}

Data_Type :: enum {
	Map,
	Struct,
	List,
	Value,
	Null,
}

// Returns true if the value is one of the "falsey" values
// for a context.
@(private)
_falsey_context := make(map[string]bool)

// Returns true if the value is one of the "falsey" values
// for a context.
@(private)
_whitespace := make(map[rune]bool)


/*
	UTILITY PROCEDURES
*/

trim_decimal_string :: proc(s: string, allocator := context.allocator) -> string {
	if len(s) == 0 || s[len(s)-1] != '0' {
		return strings.clone(s[:], allocator = allocator)
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
			return strings.clone(s[:trailing_start_idx], allocator = allocator)
		}
	}

	return strings.clone(s[:], allocator = allocator)
}

escape_html_string :: proc(s: string, allocator := context.allocator) -> string {
	escaped := s
	// Ampersand escaping goes first.
	escaped, _ = strings.replace_all(escaped, "&", HTML_AMPERSAND, allocator = allocator)
	escaped, _ = strings.replace_all(escaped, "<", HTML_LESS_THAN, allocator = allocator)
	escaped, _ = strings.replace_all(escaped, ">", HTML_GREATER_THAN, allocator = allocator)
	escaped, _ = strings.replace_all(escaped, "\"", HTML_QUOTE, allocator = allocator)
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

/*
	LEXER-RELATED PROCEDURES
*/

lexer_make :: proc() -> ^Lexer {
	l := new(Lexer, context.temp_allocator)
	l.tokens = make([dynamic]Token, 0, context.temp_allocator)
	l.tag_stack = make([dynamic]rune, 0, context.temp_allocator)
	return l
}

lexer_peek :: proc(l: ^Lexer, s: string, offset := 0) -> (bool) {
	peek_i: int
	peeked: rune

	if l.cursor + offset + len(s) >= len(l.src) {
		return false
	}

	for i := 0; i < len(s); i += 1 {
		peek_i = l.cursor + offset + i
		peeked = rune(l.src[peek_i])
		if peeked != rune(s[i]) {
			return false
		}
	}

	return true
}

// Used AFTER a new Token is inserted into the tokens dynamic
// array. In the case of a .Tag_Literal ('{{{...}}}'), we need
// to advance the next start position by three instead of two,
// to account for the additional brace.
lexer_start :: proc(l: ^Lexer, new_type: Token_Type) {
	cur_type := l.cur_token_type

	switch {
	// Moving from text into a tag.
	case cur_type == .Text:
		switch new_type {
		case .Section_Open:
			l.cur_token_start_pos = l.cursor + len(l.delim.otag_section_open)
		case .Section_Close:
			l.cur_token_start_pos = l.cursor + len(l.delim.otag_section_close)
		case .Section_Open_Inverted:
			l.cur_token_start_pos = l.cursor + len(l.delim.otag_inverted)
		case .Partial:
			l.cur_token_start_pos = l.cursor + len(l.delim.otag_partial)
		case .Comment:
			l.cur_token_start_pos = l.cursor + len(l.delim.otag_comment)
		case .Tag_Literal:
			l.cur_token_start_pos = l.cursor + len(l.delim.otag_literal)
		case .Tag_Literal_Triple:
			l.cur_token_start_pos = l.cursor + len(l.delim.otag_lit)
		case .Tag:
			l.cur_token_start_pos = l.cursor + len(l.delim.otag)
		case .Text, .Newline, .EOF, .Skip:
		}
	// Moving from a tag back into text.
	case new_type == .Text:
		switch cur_type {
		case .Newline:
			l.cur_token_start_pos = l.cursor + len("\n")
		case .Tag, .Section_Open_Inverted, .Tag_Literal, .Section_Close, .Section_Open, .Comment, .Partial:
			l.cur_token_start_pos = l.cursor + len(l.delim.ctag)
		case .Tag_Literal_Triple:
			l.cur_token_start_pos = l.cursor + len(l.delim.ctag_lit)
		case .Text, .EOF, .Skip:
		}
	}

	// Update the current type to the new type.
	l.cur_token_type = new_type
}

// Adds a new token to our list.
lexer_append :: proc(l: ^Lexer) {
	switch l.cur_token_type {
	case .Text:
		lexer_append_text(l)
	case .Newline:
		lexer_append_newline(l)
	case .Tag, .Tag_Literal, .Tag_Literal_Triple, .Comment, .Partial, .Section_Open, .Section_Open_Inverted, .Section_Close:
		lexer_append_tag(l, l.cur_token_type)
	case .EOF, .Skip:
	}
}

lexer_append_tag :: proc(l: ^Lexer, token_type: Token_Type) {
	pos := Pos {
		start=l.cur_token_start_pos,
		end=l.cursor,
		line=l.line,
	}

	if pos.end > pos.start {
		// Remove all empty whitespace inside a valid tag so that we don't
		// mess up our access of the data.
		token_text := l.src[pos.start:pos.end]
		token_text, _ = strings.remove_all(token_text, " ", allocator = context.temp_allocator)
		token := Token{type=token_type, value=token_text, pos=pos}
		append(&l.tokens, token)
	}
}

lexer_append_text :: proc(l: ^Lexer) {
	pos := Pos {
		start=l.cur_token_start_pos,
		end=l.cursor,
		line=l.line,
	}

	if pos.end > pos.start {
		text := l.src[pos.start:pos.end]
		token := Token{type=.Text, value=text, pos=pos}
		append(&l.tokens, token)
	}
}

lexer_append_newline :: proc(l: ^Lexer) {
	pos := Pos {
		start=l.cur_token_start_pos,
		end=l.cursor + 1,
		line=l.line,
	}

	newline := Token{type=.Newline, value="\n", pos=pos}
	append(&l.tokens, newline)
}

lexer_parse :: proc(l: ^Lexer) -> (err: Lexer_Error) {
	for l.cursor < len(l.src) {
		ch := rune(l.src[l.cursor])
		defer { l.cursor += 1 }

		switch {
		// When we hit a newline (and we are not inside a .Comment, as multi-line
		// comments are permitted), add the current chunk as a new Token, insert
		// a special .Newline token, and then begin as a new .Text Token.
		case ch == '\n' && l.cur_token_type != .Comment:
			lexer_append(l)
			lexer_start(l, .Newline)
			lexer_append(l)
			lexer_start(l, .Text)
			l.line += 1
		case lexer_peek(l, l.delim.otag_lit):
			lexer_append(l)
			lexer_start(l, .Tag_Literal_Triple)
		case lexer_peek(l, l.delim.otag_section_open):
			lexer_append(l)
			lexer_start(l, .Section_Open)
		case lexer_peek(l, l.delim.otag_section_close):
			lexer_append(l)
			lexer_start(l, .Section_Close)
		case lexer_peek(l, l.delim.otag_inverted):
			lexer_append(l)
			lexer_start(l, .Section_Open_Inverted)
		case lexer_peek(l, l.delim.otag_partial):
			lexer_append(l)
			lexer_start(l, .Partial)
		case lexer_peek(l, l.delim.otag_literal):
			lexer_append(l)
			lexer_start(l, .Tag_Literal)
		case lexer_peek(l, l.delim.otag_comment):
			lexer_append(l)
			lexer_start(l, .Comment)
		// Be careful with checking for "{{" -- it could be a substring of "{{{"
		case lexer_peek(l, l.delim.otag) && l.cur_token_type != .Tag_Literal_Triple:
			lexer_append(l)
			lexer_start(l, .Tag)
		case lexer_peek(l, "}") && l.cur_token_type != .Text:
			lexer_append(l)
			lexer_start(l, .Text)
		}
	}

	// Add the last tag and mark that we hit the end of the file.
	lexer_append(l)
	l.cur_token_type = .EOF
	return nil
}

lexer_print_tokens :: proc(l: ^Lexer) {
	for t, i in l.tokens {
		fmt.println(i, "    ", t)
	}
}

lexer_token_should_skip :: proc(l: ^Lexer, t: Token) -> (skip: bool) {
	switch t.type {
	case .Newline:
		skip = lexer_should_skip_newline_token(l, t)
	case .Text:
		skip = lexer_should_skip_text_token(l, t)
	case .Tag, .Tag_Literal, .Tag_Literal_Triple, .Partial, .Section_Open, .Section_Close, .Section_Open_Inverted:
		skip = false
	case .EOF, .Skip, .Comment:
		skip = true
	}

	return skip
}

// Retrieves all the tokens that are on a given line of the input text.
lexer_tokens_on_same_line :: proc(l: ^Lexer, line: int) -> (tokens: []Token) {
	on_line := false
	start_i: int
	end_i: int

	for t, i in l.tokens {
		if t.pos.line == line && !on_line {
			on_line = true
			start_i = i
		} else if t.pos.line != line && on_line {
			on_line = false
			end_i = i
			break
		}
	}

	if on_line {
		end_i = len(l.tokens)
	}

	if start_i <= end_i {
		return l.tokens[start_i:end_i]
	} else {
		return l.tokens[0:0]
	}
}


// Skip a newline if we are on a line that has either a
// non-blank .Text token OR any valid tags.
lexer_should_skip_newline_token :: proc(l: ^Lexer, token: Token) -> bool {
	on_line := lexer_tokens_on_same_line(l, token.pos.line)

	// If the newline is the only token present, do not skip it.
	if len(on_line) == 1 {
		return false
	}

	for t in on_line {
		switch t.type {
		case .Text:
			if !is_text_blank(t.value) {
				return false
			}
		case .Tag, .Tag_Literal, .Tag_Literal_Triple:
			return false
		case .Section_Open, .Section_Close, .Section_Open_Inverted, .Comment,
				 .Partial, .Newline, .Skip, .EOF:
		}
	}

	return true
}

// If we are rendering a .Text tag, we should NOT render it if it is:
//  - On a line with one .Section tag, AND
//  - comprised of only whitespace, along with all the other .Text tokens
lexer_should_skip_text_token :: proc(l: ^Lexer, token: Token) -> bool {
	on_line := lexer_tokens_on_same_line(l, token.pos.line)

	standalone_tag_count := 0
	for t in on_line {
		switch t.type {
		case .Text:
			if !is_text_blank(t.value) {
				return false
			}
		case .Tag, .Tag_Literal, .Tag_Literal_Triple, .Partial:
			return false
		case .Section_Open, .Section_Open_Inverted, .Section_Close, .Comment:
			standalone_tag_count += 1
		case .Newline, .Skip, .EOF:
		}
	}

	// If we have gotten to the end, that means all the .Text
	// tags on this line are blank. If we also only have a single
	// section or comment tag, that means that tag is standalone.
	return standalone_tag_count == 1
}

// Checks if a given .Partial Token is "standalone."
lexer_token_is_standalone_partial :: proc(l: ^Lexer, token: Token) -> bool {
	on_line := lexer_tokens_on_same_line(l, token.pos.line)

	standalone_tag_count := 0
	for t in on_line {
		switch t.type {
		case .Text:
			if !is_text_blank(t.value) {
				return false
			}
		case .Tag, .Tag_Literal, .Tag_Literal_Triple:
			return false
		case .Section_Open, .Section_Open_Inverted, .Section_Close, .Comment, .Partial:
			standalone_tag_count += 1
		case .Newline, .Skip, .EOF:
		}
	}

	// If we have gotten to the end, that means all the .Text
	// tags on this line are blank. If we also only have a single
	// section or comment tag, that means that tag is standalone.
	return standalone_tag_count == 1
}

/*
	TEMPLATE-RELATED PROCEDURES
*/

template_make :: proc(l: ^Lexer) -> ^Template {
	t := new(Template, context.temp_allocator)
	t.lexer = l
	t.context_stack = make([dynamic]Context_Stack_Entry, 0, context.temp_allocator)
	return t
}

// Sections can have false-y values in their corresponding data. When this
// is the case, the section should not be rendered. Example:
// input := "\"{{#boolean}}This should not be rendered.{{/boolean}}\""
// data := Map {
//   "boolean" = "false"
// }
// Valid contexts are:
//   - Map with at least one key
//   - List with at least one element
//   - string NOT in the _falsey_context mapping
template_token_is_valid :: proc(tmpl: ^Template, token: Token) -> (bool) {
	stack_entry := tmpl.context_stack[0]

	// The root stack is always valid.
	if stack_entry.label == "ROOT" {
		return true
	}

	switch data_type(stack_entry.data) {
	case .Map, .List, .Struct:
		return data_len(stack_entry.data) > 0
	case .Value:
		s := fmt.tprintf("%v", stack_entry.data)
		return !_falsey_context[s]
	case .Null:
		return false
	}

	return false
}

template_string_from_key :: proc(
	tmpl: ^Template,
	key: string,
) -> (s: string) {
	resolved: any

	if key == "." {
		resolved = tmpl.context_stack[0].data
	} else {
		// If the top of the stack is a string and we need to access a hash of data,
		// dig from the layer beneath the top.
		ids := strings.split(key, ".", allocator = context.temp_allocator)
		for ctx in tmpl.context_stack {
			resolved = dig(ctx.data, ids[0:1])
			if resolved != nil {
				break
			}
		}

		// Apply "dotted name resolution" if we have parts after the core ID.
		if len(ids[1:]) > 0 {
			last := slice.last(ids[:])
			last_slice := ids[len(ids)-1:]
			resolved = dig(resolved, ids[1:])
			if is_map(resolved) || is_struct(resolved) && has_key(resolved, last) {
				resolved = dig(resolved, last_slice)
			}
		}
	}

	s, _ = any_to_string(resolved)
	return s
}

template_print_stack :: proc(tmpl: ^Template) {
	fmt.println("Current stack")
	for c, i in tmpl.context_stack {
		fmt.printf("\t[%v] %v: %v\n", i, c.label, c.data)
	}
}

// Retrieves data to place on the context stack.
template_get_data_for_stack :: proc(tmpl: ^Template, data_id: string) -> (data: any) {
	ids := strings.split(data_id, ".")
	defer delete(ids)

	// New stack entries always need to resolve against the current top
	// of the stack entry.
	data = dig(tmpl.context_stack[0].data, ids)

	// If we couldn't resolve against the top of the stack, add from the root.
	if data == nil {
		root_stack_entry := tmpl.context_stack[len(tmpl.context_stack)-1]
		data = dig(root_stack_entry.data, ids)
	}

	// If we still can't find anything, mark this section as false-y.
	if reflect.is_nil(data) {
		return runtime.new_clone(FALSEY, allocator = context.temp_allocator)^
	} else {
		return data
	}
}

// Adds a new entry to the Template's context_stack. This occurs
// when we encounter a .Section_Open tag.
template_add_to_context_stack :: proc(tmpl: ^Template, t: Token, offset: int) {
	data_id := t.value
	data := template_get_data_for_stack(tmpl, data_id)

	if t.type == .Section_Open_Inverted {
		stack_entry := Context_Stack_Entry{
			data=invert_data(data),
			label=data_id,
		}
		inject_at(&tmpl.context_stack, 0, stack_entry)
	} else {
		switch data_type(data) {
		case .Map, .Struct, .Value:
			stack_entry := Context_Stack_Entry{data=data, label=data_id}
			inject_at(&tmpl.context_stack, 0, stack_entry)
		case .List:
			template_inject_list_into_context_stack(tmpl, data, offset)
		case .Null:
			stack_entry := Context_Stack_Entry{data=nil, label=data_id}
			inject_at(&tmpl.context_stack, 0, stack_entry)
		}
	}
}

template_inject_list_into_context_stack :: proc(tmpl: ^Template, list: any, offset: int) {
	section_open := tmpl.lexer.tokens[offset]
	section_name := section_open.value
	start_chunk := offset + 1
	end_chunk := template_find_section_close_tag_index(tmpl, section_name, offset)

	// Remove the original chunk from the token list if the list is empty.
	// We treat empty lists as false-y values.
	if data_len(list) == 0 {
		for _ in start_chunk..<end_chunk {
			ordered_remove(&tmpl.lexer.tokens, start_chunk)
		}
		return
	}

	// If we have a list with contents, update the closing tag with:
	// 1. The number of iterations to perform
	// 2. The position of the start of the loop (eg., .Section_Open tag)
	section_close := tmpl.lexer.tokens[end_chunk]
	section_close.iters = data_len(list) - 1
	section_close.start_i = offset
	tmpl.lexer.tokens[end_chunk] = section_close

	// Add each element of the list to the context stack. Add the data in
	// reverse order of the list, so that the first entry is at the top.
	for i := section_close.iters; i >= 0; i -= 1 {
		el := list_at(list, i)
		stack_entry := Context_Stack_Entry{data=el, label="TEMP LIST"}
		inject_at(&tmpl.context_stack, 0, stack_entry)
	}
}

// Finds the closing tag with a given value after
// the given offset.
template_find_section_close_tag_index :: proc(
	tmpl: ^Template,
	label: string,
	offset: int,
) -> (int) {
	for t, i in tmpl.lexer.tokens[offset:] {
		if t.type == .Section_Close && t.value == label {
			return i + offset
		}
	}

	return -1
}

template_pop_from_context_stack :: proc(tmpl: ^Template) {
	if len(tmpl.context_stack) > 1 {
		ordered_remove(&tmpl.context_stack, 0)
	}
}

token_content :: proc(tmpl: ^Template, t: Token) -> (s: string) {
	switch t.type {
	case .Text:
		// NOTE: Carriage returns causing some wonkiness with .concatenate.
		if t.value != "\r" {
			s = t.value
		}
	case .Tag:
		s = template_string_from_key(tmpl, t.value)
		s = escape_html_string(s, allocator = context.temp_allocator)
	case .Tag_Literal, .Tag_Literal_Triple:
		s = template_string_from_key(tmpl, t.value)
	case .Newline:
		s = "\n"
	case .Section_Open, .Section_Open_Inverted, .Section_Close,
		 .Comment, .Skip, .EOF, .Partial:
	}

	return s
}

token_is_tag :: proc(t: Token) -> bool {
	switch t.type {
	case .Tag, .Tag_Literal, .Tag_Literal_Triple:
		return true
	case .Text, .Newline, .Section_Open, .Section_Open_Inverted, .Section_Close,
		 .Comment, .Skip, .EOF, .Partial:
		return false
	}

	return false
}

// When a .Partial token is encountered, we need to inject the contents
// of the partial into the current list of tokens.
template_insert_partial :: proc(
	tmpl: ^Template,
	token: Token,
	offset: int,
) -> (err: Lexer_Error) {
	partial_name := token.value
	partial_content := dig(tmpl.partials, []string{partial_name})
	partial_str, _ := any_to_string(partial_content)

	lexer := lexer_make()
	lexer.src = partial_str
	lexer.line = token.pos.line
	lexer.delim = CORE_DEF
	lexer_parse(lexer) or_return

	// Performs any indentation on the .Partial that we are inserting.
	//
	// Example: use the first Token as the indentation for the .Partial Token.
	// [Token{type=.Text, value="  "}, Token{type=.Partial, value="to_add"}]
	//
	standalone := lexer_token_is_standalone_partial(tmpl.lexer, token)
	if offset > 0 && standalone {
		prev_token := tmpl.lexer.tokens[offset-1]
		if prev_token.type == .Text && is_text_blank(prev_token.value) {
			cur_line := lexer.tokens[len(lexer.tokens)-1].pos.line
			#reverse for t, i in lexer.tokens {
				// Do not indent the top line.
				if cur_line == 0 {
					break
				}

				// When moving back up a line, insert the indentation.
				if cur_line != t.pos.line {
					inject_at(&lexer.tokens, i+1, prev_token)
				}

				cur_line = t.pos.line
			}
		}
	}

	// Inject tokens from the partial into the primary template.
	#reverse for t in lexer.tokens {
		inject_at(&tmpl.lexer.tokens, offset+1, t)
	}

	return nil
}

// Inject a chunk of text into the token list of the larger layout template.
template_insert_content_into_layout :: proc(
	tmpl: ^Template,
	token: Token,
	offset: int,
	content: string,
) -> (err: Lexer_Error) {
	lexer := lexer_make()
	lexer.src = content
	lexer.line = token.pos.line
	lexer.delim = CORE_DEF
	lexer_parse(lexer) or_return

	// Performs indentation on the content.
	if offset > 0 {
		prev_token := tmpl.lexer.tokens[offset-1]
		if prev_token.type == .Text && is_text_blank(prev_token.value) {
			cur_line := lexer.tokens[len(lexer.tokens)-1].pos.line
			#reverse for t, i in lexer.tokens {
				// Do not indent the top line.
				if cur_line == 0 {
					break
				}

				// When moving back up a line, insert the indentation.
				if cur_line != t.pos.line {
					inject_at(&lexer.tokens, i+1, prev_token)
				}

				cur_line = t.pos.line
			}
		}
	}

	// Inject tokens from the partial into the primary template.
	#reverse for t in lexer.tokens {
		inject_at(&tmpl.lexer.tokens, offset+1, t)
	}

	return nil
}

template_eat_tokens :: proc(tmpl: ^Template, sb: ^strings.Builder) {
	root: Context_Stack_Entry
	root.label = "ROOT"
	root.data = tmpl.data
	inject_at(&tmpl.context_stack, 0, root)

	// First pass to find all the whitespace/newline elements that should be skipped.
	// This is performed up-front due to partial templates -- we cannot check for the
	// whitespace logic *after* the partials have been injected into the template.
	for &t in tmpl.lexer.tokens {
		if lexer_token_should_skip(tmpl.lexer, t) {
			t.type = .Skip
		}
	}

	// Second pass to render the template.
	i := 0
	for i < len(tmpl.lexer.tokens) {
		defer { i += 1 }
		t := tmpl.lexer.tokens[i]

		switch t.type {
		case .Newline, .Text, .Tag, .Tag_Literal, .Tag_Literal_Triple:
			if template_token_is_valid(tmpl, t) {
				strings.write_string(sb, token_content(tmpl, t))
			}
		case .Section_Open, .Section_Open_Inverted:
			template_add_to_context_stack(tmpl, t, i)
		case .Section_Close:
			template_pop_from_context_stack(tmpl)
			// If we are in a loop and have iterations remaining, jump back to
			// the token at the start of the loop.
			if t.iters > 0 {
				t.iters -= 1
				tmpl.lexer.tokens[i] = t
				i = t.start_i
			}
		case .Partial:
			template_insert_partial(tmpl, t, i)
		// Do nothing for these tags.
		case .Comment, .Skip, .EOF:
		}
	}
}

template_render :: proc(tmpl: ^Template) -> (output: string, err: Render_Error) {
	sb := strings.builder_make(context.temp_allocator)

	template_eat_tokens(tmpl, &sb)
	rendered := strings.to_string(sb) 

	if tmpl.layout != "" {
		sbl := strings.builder_make(context.temp_allocator)

		// Parse the layout
		layout_lexer := lexer_make()
		layout_lexer.src = tmpl.layout
		layout_lexer.delim = CORE_DEF
		lexer_parse(layout_lexer) or_return

		// The Layout template will have no partials or layouts.
		// layout_template: Template
		layout_template := template_make(layout_lexer)
		layout_template.data = tmpl.data

		// TODO: Could we directly index the special {{content}} tag so that
		// we don't need to search it here by iterating and just get it?
		for t, i in layout_lexer.tokens {
			if token_is_tag(t) && t.value == "content" {
				template_insert_content_into_layout(layout_template, t, i, rendered)
			}
		}

		template_eat_tokens(layout_template, &sbl)
		rendered = strings.to_string(sbl)
	}

	return rendered, nil
}

/*
	DATA-SPECIFIC PROCEDURES
*/

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

// Given a list of keys, access nested data inside any combination of
// maps, structs, and lists.
dig :: proc(d: any, keys: []string) -> any {
	d := d

	if len(keys) == 0 {
		return d
	}

	for key in keys {
		switch data_type(d) {
		case .Struct:
			d = struct_get(d, key)
		case .Map:
			d, _ = map_get(d, key)
		case .List:
			d = d
		case .Value:
			if key == "." {
				d = fmt.tprintf("%v", d) 
			} else {
				return nil
			}
		case .Null:
			return nil
		}
	}

	return d
}

any_to_string :: proc(obj: any) -> (s: string, err: Render_Error) {
	switch data_type(obj) {
	case .Struct, .Map, .List:
		fmt.println("Could not convert", obj, "to printable content.")
		return s, Template_Error {}
	case .Value:
		s = fmt.tprintf("%v", obj)
	case .Null:
		s = ""
	}

	return s, nil
}

has_key :: proc(obj: any, key: string) -> (has: bool) {
	obj := obj

	switch data_type(obj) {
	case .Map:
		return map_has_key(obj, key)
	case .Struct:
		if is_union(obj) {
			obj = reflect.get_union_variant(obj)
		}
		fields := reflect.struct_field_names(obj.id)
		return slice.contains(fields, key)
	case .List, .Value, .Null:
		return false
	}

	return has
}

// Get the data type of an object.
data_type :: proc(obj: any) -> Data_Type {
	if reflect.is_nil(obj) {
		return .Null
	} else if is_struct(obj) {
		return .Struct
	} else if is_map(obj) {
		return .Map
	} else if is_list(obj) {
		return .List
	} else {
		return .Value
	}
}

// Inverts a piece of data. If it has any content, then return a
// falsey value. Otherwise, a truthful value.
invert_data :: proc(data: any) -> any {
	s: string

	switch data_type(data) {
	case .Struct, .Map, .List:
		if data_len(data) > 0 {
			s = FALSEY
		} else {
			s = TRUE
		}
	case .Value:
		if _falsey_context[fmt.tprintf("%v", data)] {
			s = TRUE
		} else {
			s = FALSEY
		}
	case .Null:
		s = TRUE
	}

	if s == "" {
		s = FALSEY
	}

	return runtime.new_clone(s, allocator = context.temp_allocator)^
}

/*
	PRIMARY RENDER PROCEDURES
*/
render :: proc(
	template: string,
	data: any,
	partials: any = map[string]string {}
) -> (s: string, err: Render_Error) {
	defer(free_all(context.temp_allocator))

	// Parse template.
	lexer := lexer_make()
	lexer.src = template
	lexer.delim = CORE_DEF
	lexer_parse(lexer) or_return

	// Render template
	template := template_make(lexer)
	template.data = data
	template.partials = partials

	s = template_render(template) or_return
	return strings.clone(s), nil
}

render_in_layout :: proc(
	template: string,
	data: any,
	layout: string,
	partials: any = map[string]string {}
) -> (s: string, err: Render_Error) {
	defer(free_all(context.temp_allocator))

	lexer := lexer_make()
	lexer.src = template
	lexer.delim = CORE_DEF
	lexer_parse(lexer) or_return

	// Render template.
	template := template_make(lexer)
	template.data = data
	template.partials = partials
	template.layout = layout

	s = template_render(template) or_return
	return strings.clone(s), nil
}

render_in_layout_file :: proc(
	template: string,
	data: any,
	layout_filename: string,
	partials: any = map[string]string {},
) -> (s: string, err: Render_Error) {
	defer(free_all(context.temp_allocator))

	// Read layout file.
	layout, _ := os.read_entire_file_from_filename(layout_filename, context.temp_allocator)

	// Parse template.
	lexer := lexer_make()
	lexer.src = template
	lexer.delim = CORE_DEF
	lexer_parse(lexer) or_return

	// Render template
	tmpl := template_make(lexer)
	tmpl.lexer = lexer
	tmpl.data = data
	tmpl.partials = partials
	tmpl.layout = string(layout)

	s = template_render(tmpl) or_return
	return strings.clone(s), nil
}

render_from_filename :: proc(
	filename: string,
	data: any,
	partials: any = map[string]string {},
) -> (s: string, err: Render_Error) {
	defer(free_all(context.temp_allocator))

	// Read template file.
	src, _ := os.read_entire_file_from_filename(filename, context.temp_allocator)

	// Parse template.
	lexer := lexer_make()
	lexer.src = string(src)
	lexer.delim = CORE_DEF
	lexer_parse(lexer) or_return

	// Render template.
	template := template_make(lexer)
	template.lexer = lexer
	template.data = data
	template.partials = partials

	s = template_render(template) or_return
	return strings.clone(s), nil
}

render_from_filename_in_layout :: proc(
	filename: string,
	data: any,
	layout: string,
	partials: any = map[string]string {},
) -> (s: string, err: Render_Error) {
	defer(free_all(context.temp_allocator))

	// Read template file and trim the trailing newline.
	src, _ := os.read_entire_file_from_filename(filename, context.temp_allocator)
	if rune(src[len(src)-1]) == '\n' {
		src = src[0:len(src)-1]
	}

	// Parse template.
	lexer := lexer_make()
	lexer.src = string(src)
	lexer.delim = CORE_DEF
	lexer_parse(lexer) or_return

	// Render template.
	template := template_make(lexer)
	template.data = data
	template.partials = partials
	template.layout = layout

	s = template_render(template) or_return
	return strings.clone(s), nil
}

render_from_filename_in_layout_file :: proc(
	filename: string,
	data: any,
	layout_filename: string,
	partials: any = map[string]string {},
) -> (s: string, err: Render_Error) {
	defer(free_all(context.temp_allocator))

	// Read template file and trim the trailing newline.
	src, _ := os.read_entire_file_from_filename(filename, context.temp_allocator)
	if rune(src[len(src)-1]) == '\n' {
		src = src[0:len(src)-1]
	}

	// Read layout file.
	layout, _ := os.read_entire_file_from_filename(layout_filename, context.temp_allocator)

	// Parse template.
	lexer := lexer_make()
	lexer.src = string(src)
	lexer.delim = CORE_DEF
	lexer_parse(lexer) or_return

	// Render template
	template := template_make(lexer)
	template.data = data
	template.partials = partials
	template.layout = string(layout)

	s = template_render(template) or_return
	return strings.clone(s), nil
}

render_with_json :: proc(
	template: string,
	json_filename: string,
) -> (s: string, err: Render_Error) {
	defer(free_all(context.temp_allocator))

	// Load JSON.
	json_src, _ := os.read_entire_file_from_filename(json_filename, context.temp_allocator)
	json_data := json.parse(json_src, allocator = context.temp_allocator) or_return
	// defer json.destroy_value(json_data)
	json_root := json_data.(json.Object)

	// Parse template.
	lexer := lexer_make()
	lexer.src = template
	lexer.delim = CORE_DEF
	lexer_parse(lexer) or_return

	// Render template.
	template := template_make(lexer)
	template.data = json_root["data"]
	template.partials = json_root["partials"]

	s = template_render(template) or_return
	return strings.clone(s), nil
}

render_with_json_in_layout :: proc(
	template: string,
	json_filename: string,
	layout: string,
) -> (s: string, err: Render_Error) {
	defer(free_all(context.temp_allocator))

	// Load JSON.
	json_src, _ := os.read_entire_file_from_filename(json_filename, context.temp_allocator)
	json_data := json.parse(json_src, allocator = context.temp_allocator) or_return
	json_root := json_data.(json.Object)

	// Parse template.
	lexer := lexer_make()
	lexer.src = template
	lexer.delim = CORE_DEF
	lexer_parse(lexer) or_return

	// Render template.
	template := template_make(lexer)
	template.data = json_root["data"]
	template.partials = json_root["partials"]
	template.layout = layout

	s = template_render(template) or_return
	return strings.clone(s), nil
}

render_with_json_in_layout_file :: proc(
	template: string,
	json_filename: string,
	layout_filename: string,
) -> (s: string, err: Render_Error) {
	defer(free_all(context.temp_allocator))

	// Read layout file.
	layout, _ := os.read_entire_file_from_filename(layout_filename, context.temp_allocator)

	// Load JSON.
	json_src, _ := os.read_entire_file_from_filename(json_filename, context.temp_allocator)
	json_data := json.parse(json_src, allocator = context.temp_allocator) or_return
	json_root := json_data.(json.Object)

	// Parse template.
	lexer := lexer_make()
	lexer.src = template
	lexer.delim = CORE_DEF
	lexer_parse(lexer) or_return

	// Render template.
	template := template_make(lexer)
	template.data = json_root["data"]
	template.partials = json_root["partials"]
	template.layout = string(layout)

	s = template_render(template) or_return
	return strings.clone(s), nil
}

render_from_filename_with_json :: proc(
	filename: string,
	json_filename: string,
) -> (s: string, err: Render_Error) {
	defer(free_all(context.temp_allocator))

	// Read template file.
	src, _ := os.read_entire_file_from_filename(filename, context.temp_allocator)

	// Load JSON.
	json_src, _ := os.read_entire_file_from_filename(json_filename, context.temp_allocator)
	json_data := json.parse(json_src) or_return
	defer json.destroy_value(json_data)
	json_root := json_data.(json.Object)

	// Parse template.
	lexer := lexer_make()
	lexer.src = string(src)
	lexer.delim = CORE_DEF
	lexer_parse(lexer) or_return

	// Render template.
	template := template_make(lexer)
	template.data = json_root["data"]
	template.partials = json_root["partials"]

	s = template_render(template) or_return
	return strings.clone(s), nil
}

render_from_filename_with_json_in_layout :: proc(
	filename: string,
	json_filename: string,
	layout: string,
) -> (s: string, err: Render_Error) {
	defer(free_all(context.temp_allocator))

	// Read template file and trim the trailing newline.
	src, _ := os.read_entire_file_from_filename(filename, context.temp_allocator)
	if rune(src[len(src)-1]) == '\n' {
		src = src[0:len(src)-1]
	}

	// Load JSON.
	json_src, _ := os.read_entire_file_from_filename(json_filename, context.temp_allocator)
	json_data := json.parse(json_src, allocator = context.temp_allocator) or_return
	json_root := json_data.(json.Object)

	// Parse template.
	lexer := lexer_make()
	lexer.src = string(src)
	lexer.delim = CORE_DEF
	lexer_parse(lexer) or_return

	// Render template.
	template := template_make(lexer)
	template.data = json_root["data"]
	template.partials = json_root["partials"]
	template.layout = layout

	s = template_render(template) or_return
	return strings.clone(s), nil
}

render_from_filename_with_json_in_layout_file :: proc(
	filename: string,
	json_filename: string,
	layout_filename: string,
) -> (s: string, err: Render_Error) {
	defer(free_all(context.temp_allocator))

	// Read template file and trim the trailing newline.
	src, _ := os.read_entire_file_from_filename(filename, context.temp_allocator)
	if rune(src[len(src)-1]) == '\n' {
		src = src[0:len(src)-1]
	}

	// Read layout file.
	layout, _ := os.read_entire_file_from_filename(layout_filename, context.temp_allocator)

	// Load JSON.
	json_src, _ := os.read_entire_file_from_filename(json_filename, context.temp_allocator)
	json_data := json.parse(json_src, allocator = context.temp_allocator) or_return
	json_root := json_data.(json.Object)

	// Parse template.
	lexer := lexer_make()
	lexer.src = string(src)
	lexer.delim = CORE_DEF
	lexer_parse(lexer) or_return

	// Render template.
	template := template_make(lexer)
	template.data = json_root["data"]
	template.partials = json_root["partials"]
	template.layout = string(layout)

	s = template_render(template) or_return
	return strings.clone(s), nil
}

error :: proc(msg: string, args: ..any) -> ! {
	fmt.eprint("\x1b[0;31modin-mustache Error:\x1b[0m ")
	fmt.eprintf(msg, ..args)
	fmt.eprint("\n")
	os.exit(1)
}

_main :: proc(
	template_filename: string,
	json_filename: string,
	layout_filename: string = "",
) -> (output: string, err: Render_Error) {
	if !os.is_file(template_filename) {
		return "", File_Not_Found_Error{filename=template_filename}
	}

	if !os.is_file(json_filename) {
		return "", File_Not_Found_Error{filename=json_filename}
	}

	if layout_filename != "" && !os.is_file(layout_filename) {
		return "", File_Not_Found_Error{filename=layout_filename}
	}

	if layout_filename != "" {
		output = render_from_filename_with_json_in_layout_file(
			template_filename,
			json_filename,
			layout_filename,
		) or_return
	} else {
		output = render_from_filename_with_json(
			template_filename,
			json_filename,
		) or_return
	}

	return output, nil
}

/*
	Setup global vars.
*/
@(init)
init :: proc() {
	// Returns true if the value is one of the "falsey" values
	// for a context.
	_falsey_context[FALSEY] = true
	_falsey_context["null"] = true
	_falsey_context[""] = true

	// Returns true if the value is one of the "falsey" values
	// for a context.
	_whitespace[' '] = true
	_whitespace['\t'] = true
	_whitespace['\r'] = true
}

main :: proc() {
	defer free_all(context.temp_allocator)

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		defer mem.tracking_allocator_destroy(&track)
		context.allocator = mem.tracking_allocator(&track)
	}

	if len(os.args) < 3 {
		error("You need to pass at least paths to the template and JSON data.")
	}

	// If a third argument was provided, this is the layout file.
	layout_file: string
	if len(os.args) == 4 {
		layout_file = os.args[3]
	}

	if output, err := _main(os.args[1], os.args[2], layout_file); err != nil {
		fmt.printf("Err: %v\n", err)
		os.exit(1)
	} else {
		fmt.eprint(output)
	}

	when ODIN_DEBUG {
		for _, entry in track.allocation_map {
			fmt.eprintf("%m leaked at %v\n", entry.location, entry.size)
		}

		for entry in track.bad_free_array {
			fmt.eprintf("%v allocation %p was freed badly\n", entry.location, entry.memory)
		}
	}
}
