package mustache

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:strconv"

/*
  A section is like:
  {{#person}}
    Hello!
  {{/person}
*/
SECTION_OPEN :: "{{#"
SECTION_TRIPLE_OPEN :: "{{{#"
SECTION_CLOSE :: "{{/"
SECTION_TRIPLE_CLOSE :: "{{{/"

/*
  Normal interpolation is like:
  Hello, {{name}}!
*/
OTAG :: "{{"
OTAG_TRIPLE :: "{{{"
CTAG :: "}}"
CTAG_TRIPLE :: "}}}"

/*
  Special characters that will receive HTML-escaping
  treatment, if necessary.
*/
HTML_LESS_THAN :: "&lt;"
HTML_GREATER_THAN :: "&gt;"
HTML_QUOTE :: "&quot;"
HTML_AMPERSAND :: "&amp;"

Error :: enum {
  None,
  Something
}

// All data provided will either be:
// 1. A string
// 2. A mapping from string => string
// 3. A mapping from string => more Data
// 4. An array of Data?
Data :: union {
  map[string]Data,
  string
}

/*

*/
Template :: struct {
  // Raw input string.
  str: string,
  // Points to the current position in str when parsing.
  pos: int,
  tags: [dynamic]Tag,
  data: Data
}

Tag :: union {
  TextTag,
  DataTag
}

TextTag :: struct {
  str: string
}

DataTag :: struct {
  key: string,
  escape: bool
}

active_str :: proc(tmpl: ^Template) -> (string) {
  str_len := len(tmpl.str)
  if tmpl.pos >= str_len {
    return ""
  }

  return strings.cut(tmpl.str, tmpl.pos, str_len, context.temp_allocator)
}

/*

*/
parse_string :: proc(tmpl: ^Template) -> (ok: bool) {
  str := active_str(tmpl)

  otag_triple_section := strings.index(str, SECTION_TRIPLE_OPEN)
  otag_triple_pos := strings.index(str, OTAG_TRIPLE)  
  otag_section := strings.index(str, SECTION_OPEN)  
  otag_pos := strings.index(str, OTAG)  

  if otag_triple_section > -1 {
    // TODO: Add triple section parsing.
  } else if otag_triple_pos > -1 {
    ok = parse_triple_tag(tmpl)
  } else if otag_section > -1 {
    // TODO: Add normal section parsing.
    ok = parse_section(tmpl)
  } else if otag_pos > -1 {
    ok = parse_standard_tag(tmpl)
  } else {
    // If we did not find an open tag, set our pointer to the
    // end of the string, add the remaining text as a TextTag,
    // and return.
    tmpl.pos = len(tmpl.str)
    append(&tmpl.tags, TextTag{str})
    ok = true
  }

  return ok
}

parse_standard_tag :: proc(tmpl: ^Template) -> (bool) {
  str := active_str(tmpl)
  otag_pos := strings.index(str, OTAG)  

  tag_content_start_pos := otag_pos + len(OTAG)

  // Text to seek for the closing tag is from the start
  // of the tag content until the end of the string.
  seek := strings.cut(str, tag_content_start_pos, allocator=context.temp_allocator)

  ctag_pos := strings.index(seek, CTAG)

  // If we could not find a matching closing tag, return
  // with a failure signal.
  if ctag_pos == -1 {
    fmt.println("No matching closing tag found from position:", tmpl.pos)
    return false
  }

  // Now that we know we have a valid chunk of text with a
  // tag inside of it, store all the text leading up to the
  // opening tag as "preceding" and put it inside a TextTag.
  // tmpl.pos is always ABSOLUTE position.
  preceding := strings.cut(tmpl.str, tmpl.pos, otag_pos, context.temp_allocator)
  append(&tmpl.tags, TextTag{preceding})

  // Get the data_id (eg., the content inside the tag) and
  // store it as a DataTag.
  data_id := strings.cut(str, tag_content_start_pos, ctag_pos, context.temp_allocator)
  append(&tmpl.tags, DataTag{key=data_id, escape=true})

  // Increment our position cursor (this is ABSOLUTE position).
  tmpl.pos = tmpl.pos + tag_content_start_pos + ctag_pos + len(CTAG)

  return true
}

// TODO: Fill in.
// input := "Hello, {{#person}}{{name}}{{/person}}"
parse_section :: proc(tmpl: ^Template) -> (bool) {
  tmpl.pos = len(tmpl.str)
  return true
}

parse_triple_tag :: proc(tmpl: ^Template) -> (bool) {
  str := active_str(tmpl)

  otag_pos := strings.index(str, OTAG_TRIPLE)  
  tag_content_start_pos := otag_pos + len(OTAG_TRIPLE)

  seek_for_ctag := strings.cut(str, tag_content_start_pos, allocator=context.temp_allocator)
  ctag_pos := strings.index(seek_for_ctag, CTAG_TRIPLE)
  if ctag_pos == -1 {
    fmt.println("No triple closing tag found from position:", tmpl.pos)
    return false
  }

  before_tag := strings.cut(tmpl.str, tmpl.pos, otag_pos, context.temp_allocator)
  append(&tmpl.tags, TextTag{before_tag})

  data_id := strings.cut(str, tag_content_start_pos, ctag_pos, context.temp_allocator)
  append(&tmpl.tags, DataTag{key=data_id, escape=false})

  // Increment our position cursor (this is ABSOLUTE position) to
  // the character after the closing tag.
  tmpl.pos = tmpl.pos + tag_content_start_pos + ctag_pos + len(CTAG_TRIPLE)

  return true
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

extract_data :: proc(data: map[string]Data, tag: DataTag) -> (string) {
  output: string
  key := tag.key
  escape_html := tag.escape

  // Key prefixed with "&" should be like a triple tag.
  if strings.has_prefix(key, "&") {
    key = strings.trim_prefix(key, "&")
    escape_html = false
  }

  dotted_keys := strings.split(key, ".", allocator=context.temp_allocator)
  fmt.println(dotted_keys)

  data, ok := data[key]
  if !ok {
    fmt.println("Could not find", key, "in", data)
    output = ""
  } else {
    output = data.(string)
  }

  if escape_html {
    output = escape_html_string(output)
  }

  return output
}

/*
  Renders a template by walking through each Tag and
  turning it into a string. At the end, the list of
  strings that we have built up is concatenated.
*/
render_template :: proc(tmpl: Template) -> (string, bool) {
  strs: [dynamic]string

  fmt.println(tmpl.tags)

  for _tag in tmpl.tags {
    switch tag in _tag {
      case TextTag:
        append(&strs, tag.str)
      // TODO: Does not handle nested keys.
      // TODO: Does not handle arrays.
      case DataTag:
        switch data in tmpl.data {
          case string:
            append(&strs, data)
          case map[string]Data:
            str := extract_data(data, tag)
            append(&strs, str)
        }
    }
  }

  rendered := strings.concatenate(
    strs[:],
    allocator=context.temp_allocator
  )
  delete(strs)

  fmt.println("Rendered:", rendered)
  return rendered, true
}

escape_html_string :: proc(s: string, allocator := context.allocator) -> (string) {
  context.allocator = allocator

  escaped := s
  // Ampersand escaping goes first.
  escaped, _ = strings.replace_all(escaped, "&", HTML_AMPERSAND)
  escaped, _ = strings.replace_all(escaped, "<", HTML_LESS_THAN)
  escaped, _ = strings.replace_all(escaped, ">", HTML_GREATER_THAN)
  escaped, _ = strings.replace_all(escaped, "\"", HTML_QUOTE)
  return escaped
}

/*
  Processes a Mustache template by:
  1. Parsing the string into a Template
  2. Rendering the Template with the provided Data.
*/
process_template :: proc(str: string, data: Data) -> (string, bool) {
  ok: bool
  output: string
  tmpl := &Template{
    str=str,
    pos=0,
    tags=make([dynamic]Tag),
    data=data
  }
  defer delete(tmpl.tags)

  when ODIN_DEBUG && !ODIN_TEST {
    fmt.printf("\n====== STARTING MUSTACHE PROCESS\n")
    fmt.printf("%v\n", tmpl)
  }

  for tmpl.pos < len(tmpl.str) {
    ok = parse_string(tmpl)
    if !ok {
      fmt.println("Could not parse.")
      return "", false
    }

    when ODIN_DEBUG && !ODIN_TEST {
      fmt.println("\n====== AFTER parse_string(...)")
      fmt.println(tmpl)
    }
  }

  output, ok = render_template(tmpl^)
  if !ok {
    fmt.println("Could not render.")
    return "", false
  }

  return output, true
}

_main :: proc() -> (err: Error) {
  input := "Hello, {{#person}}{{name}}{{/person}}"
  data: map[string]Data
  defer delete(data)
  data["person"] = map[string]Data {
    "name" = "ben"
  }

  output, ok := process_template(input, data)
  defer free_all(context.temp_allocator)
  if !ok {
    return .Something
  }

  fmt.printf("\n====== MUSTACHE COMPLETED\n")
  fmt.printf("%v\n\n", output)
  return
}

main :: proc() {
  track: mem.Tracking_Allocator
  mem.tracking_allocator_init(&track, context.allocator)
  defer mem.tracking_allocator_destroy(&track)
  context.allocator = mem.tracking_allocator(&track)

  if err := _main(); err != nil {
    fmt.printf("Err: %v\n", err)
    os.exit(1)
  }

  for _, entry in track.allocation_map {
    fmt.eprintf("%m leaked at %v\n", entry.location, entry.size)
  }

  for entry in track.bad_free_array {
    fmt.eprintf("%v allocation %p was freed badly\n", entry.location, entry.memory)
  }
}
