package mustache

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:strconv"

OTAG :: "{{"
CTAG :: "}}"

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
  key: string
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
parse_string :: proc(tmpl: ^Template) -> (bool) {
  str := active_str(tmpl)

  // otag_pos IS RELATIVE to the active string.
  otag_pos := strings.index(active_str(tmpl), OTAG)  

  // If we did not find an open tag, set our pointer to the
  // end of the string, add the remaining text as a TextTag,
  // and return.
  if otag_pos == -1 {
    tmpl.pos = len(tmpl.str)
    append(&tmpl.tags, TextTag{str})
    return true
  }

  // The actual content inside the tag starts two places
  // after the start of the tag.
  tagstart_pos := otag_pos + len(OTAG)

  // Text to seek for the closing tag is from the start
  // of the tag content until the end of the string.
  seek := strings.cut(str, tagstart_pos, allocator=context.temp_allocator)

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
  data_id := strings.cut(str, tagstart_pos, ctag_pos, context.temp_allocator)
  append(&tmpl.tags, DataTag{data_id})

  // Increment our position cursor (this is ABSOLUTE position).
  tmpl.pos = tmpl.pos + tagstart_pos + ctag_pos + len(CTAG)

  return true
}

/*
  Renders a template by walking through each Tag and
  turning it into a string. At the end, the list of
  strings that we have built up is concatenated.
*/
render_template :: proc(tmpl: Template) -> (string, bool) {
  strs: [dynamic]string

  for tag in tmpl.tags {
    switch t in tag {
      case TextTag:
        append(&strs, t.str)
      // TODO: Does not handle nested keys.
      // TODO: Does not handle arrays.
      case DataTag:
        switch d in tmpl.data {
          case string:
            append(&strs, d)
          case map[string]Data:
            data := d[t.key]
            str := data.(string)
            append(&strs, str)
        }
    }
  }

  rendered := strings.concatenate(
    strs[:],
    allocator=context.temp_allocator
  )
  delete(strs)
  return rendered, true
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
  input := "Hello, {{x}}, nice to meet you. My name is {{y}}."
  data: map[string]Data
  defer delete(data)
  data["x"] = "Ben"
  data["y"] = "R2D2"

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
