package mustache

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"

render :: proc(
  input: string,
  data: any,
  partials: any,
) -> (s: string, err: Render_Error) {
  lexer := Lexer{
    src=input,
    delim=CORE_DEF,
  }
  defer delete(lexer.tag_stack)
  defer delete(lexer.tokens)

  parse(&lexer) or_return

  template := Template {
    lexer=lexer,
    data=data,
    partials=partials,
  }
  text := process(&template) or_return
  defer delete(template.context_stack)

  return text, nil
}

render_from_filename :: proc(
  filename: string,
  data: any,
) -> (s: string, err: Render_Error) {
  src, _ := os.read_entire_file_from_filename(filename)
  defer delete(src)
  str := string(src)

  lexer := Lexer {
    src=str,
    delim=CORE_DEF,
  }
  defer delete(lexer.tag_stack)
  defer delete(lexer.tokens)
  parse(&lexer) or_return

  partials: any
  template := Template {
    lexer=lexer,
    data=data,
    partials=partials,
  }
  defer delete(template.context_stack)

  text := process(&template) or_return
  return text, nil
}

render_with_json :: proc(
  input: string,
  json_filename: string,
) -> (s: string, err: Render_Error) {
  json_src, _ := os.read_entire_file_from_filename(json_filename)
  defer delete(json_src)
  json_data := json.parse(json_src) or_return
  defer json.destroy_value(json_data)
  json_root := json_data.(json.Object)

  lexer := Lexer{
    src=input,
    delim=CORE_DEF,
  }
  defer delete(lexer.tag_stack)
  defer delete(lexer.tokens)

  parse(&lexer) or_return

  data := json_root["data"]
  partials := json_root["partials"]
  template := Template {
    lexer=lexer,
    data=data,
    partials=partials,
  }
  text := process(&template) or_return
  defer delete(template.context_stack)

  return text, nil
}

render_from_filename_with_json :: proc(
  filename: string,
  json_filename: string,
) -> (s: string, err: Render_Error) {
  src, _ := os.read_entire_file_from_filename(filename)
  defer delete(src)
  str := string(src)

  json_src, _ := os.read_entire_file_from_filename(json_filename)
  defer delete(json_src)
  json_data := json.parse(json_src) or_return
  defer json.destroy_value(json_data)
  json_root := json_data.(json.Object)

  lexer := Lexer {
    src=str,
    delim=CORE_DEF,
  }
  defer delete(lexer.tag_stack)
  defer delete(lexer.tokens)
  parse(&lexer) or_return

  data := json_root["data"]
  partials := json_root["partials"]
  template := Template {
    lexer=lexer,
    data=data,
    partials=partials,
  }
  defer delete(template.context_stack)

  text := process(&template) or_return
  return text, nil
}

_main :: proc() -> (err: Render_Error) {
  defer free_all(context.temp_allocator)

  input := "Hello.{{#names}} You were born on {{.}}.{{/names}}"
  json := "tmp/test.json"

  fmt.printf("====== RENDERING\n")
  fmt.printf("Input : '%v'\n", input)
  output := render_with_json(input, json) or_return
  fmt.printf("Output: %v\n", output)

  return nil
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
