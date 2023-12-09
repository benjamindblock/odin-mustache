package mustache

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

/*
  Special characters that will receive HTML-escaping
  treatment, if necessary.
*/
HTML_LESS_THAN :: "&lt;"
HTML_GREATER_THAN :: "&gt;"
HTML_QUOTE :: "&quot;"
HTML_AMPERSAND :: "&amp;"

RenderError :: union {
  LexerError
}

LexerError :: union {
  UnbalancedTags
}

UnbalancedTags :: struct {}

// All data provided will either be:
// 1. A string
// 2. A mapping from string => string
// 3. A mapping from string => more Data
// 4. An array of Data?
Map :: distinct map[string]Data
List :: distinct [dynamic]Data
Data :: union {
  Map,
  List,
  string
}

Template :: struct {
  lexer: Lexer,
  data: Data,
  partials: Data,
  context_stack: [dynamic]ContextStackEntry
}

ContextStackEntry :: struct {
  data: Data,
  label: string
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

data_get_string :: proc(data: string, key: string) -> (Data) {
  nil_data: Data

  if key == "." {
    return data
  } else {
    return nil_data
  }
}

data_get_map :: proc(data: Map, key: string) -> (Data) {
  return data[key]
}

data_get_list :: proc(data: List, key: string) -> (Data) {
  return data
}

data_get :: proc{data_get_string, data_get_map, data_get_list}

data_dig :: proc(data: Data, keys: []string) -> (Data) {
  data := data

  if len(keys) == 0 {
    return data
  }

  for key in keys {
    switch _data in data {
    case string:
      data = data_get(_data, key)
    case Map:
      data = data_get(_data, key)
    case List:
      data = data_get(_data, key)
    }
  }

  return data
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

/*
  Returns true if the value is one of the "falsey" values
  for a context.
*/
@(private) _falsey_context := map[string]bool{
  "false" = true,
  "null" = true,
  "" = true
}

/*
  Returns true if the value is one of the "falsey" values
  for a context.
*/
@(private) _whitespace := map[rune]bool{
  ' ' = true,
  '\t' = true,
  '\r' = true
}

/*
  Sections can have false-y values in their corresponding data. When this
  is the case, the section should not be rendered. Example:

  input := "\"{{#boolean}}This should not be rendered.{{/boolean}}\""
  data := Map {
    "boolean" = "false"
  }

  Valid contexts are:
    - Map with at least one key
    - List with at least one element
    - string NOT in the _falsey_context mapping
*/
token_valid_in_template_context :: proc(tmpl: ^Template, token: Token) -> (bool) {
  stack_entry := tmpl.context_stack[0]

  // The root stack is always valid.
  if stack_entry.label == "ROOT" {
    return true
  }

  switch _data in stack_entry.data {
  case Map:
    return len(_data) > 0
  case List:
    return len(_data) > 0 
  case string:
    return !_falsey_context[_data]
  }

  return false
}

/*
  TODO: Update return value to (string, bool) and add an appropriate
        error and message during the string confirmation phase.
*/
template_stack_extract :: proc(tmpl: ^Template, token: Token) -> (string) {
  str: string
  resolved: Data
  ok: bool

  if token.value == "." {
    resolved = tmpl.context_stack[0].data
  } else {
    // If the top of the stack is a string and we need to access a hash of data,
    // dig from the layer beneath the top.
    ids := strings.split(token.value, ".", allocator=context.temp_allocator)
    for ctx in tmpl.context_stack {
      resolved = data_dig(ctx.data, ids[0:1])
      if resolved != nil {
        break
      }
    }

    // Apply "dotted name resolution" if we have parts after the core ID.
    if len(ids[1:]) > 0 {
      resolved = data_dig(resolved, ids[1:])
      r, ok := resolved.(Map)
      if ok && slice.last(ids[:]) in r {
        resolved = r[slice.last(ids[:])]
      }
    }
  }

  // TODO: When adding types, make sure that the value is NOT
  // a Map or a List, instead. We want a single value here.
  // Make sure that the final value is a single value. If not,
  // raise error.
  str, ok = resolved.(string)
  if !ok {
    fmt.println("Could not resolve", resolved, "to a value.")
    return ""
  }

  return str
}

template_print_stack :: proc(tmpl: ^Template) {
  fmt.println("Current stack")
  for c, i in tmpl.context_stack {
    fmt.printf("\t[%v] %v: %v\n", i, c.label, c.data)
  }
}

get_data_for_stack :: proc(tmpl: ^Template, data_id: string) -> (data: Data) {
  ids := strings.split(data_id, ".")
  defer delete(ids)

  // New stack entries always need to resolve against the current top
  // of the stack entry.
  data = data_dig(tmpl.context_stack[0].data, ids)

  // If we couldn't resolve against the top of the stack, add from the root.
  if data == nil {
    root_stack_entry := tmpl.context_stack[len(tmpl.context_stack)-1]
    data = data_dig(root_stack_entry.data, ids)
  }

  // If we still can't find anything, mark this section as false-y.
  if data == nil {
    data = "false"
  }

  return data
}

template_add_to_context_stack :: proc(tmpl: ^Template, t: Token, offset: int) {
  data_id := t.value
  data := get_data_for_stack(tmpl, data_id)

  if t.type == .SectionOpenInverted {
    data = invert_data(data)
  }

  switch _data in data {
  case Map:
    stack_entry := ContextStackEntry{data=data, label=data_id}
    inject_at(&tmpl.context_stack, 0, stack_entry)
  case List:
    inject_list_data_into_context_stack(tmpl, _data, offset)
  case string:
    stack_entry := ContextStackEntry{data=data, label=data_id}
    inject_at(&tmpl.context_stack, 0, stack_entry)
  }
}

inject_list_data_into_context_stack :: proc(tmpl: ^Template, list: List, offset: int) {
  section_open := tmpl.lexer.tokens[offset]
  section_name := section_open.value
  start_chunk := offset + 1
  end_chunk := template_find_section_close_tag_index(tmpl, section_name, offset)

  // Remove the original chunk from the token list if the list is empty.
  // We treat empty lists as false-y values.
  if len(list) == 0 {
    for _ in start_chunk..<end_chunk {
      ordered_remove(&tmpl.lexer.tokens, start_chunk)
    }
    return
  }


  // If we have a list with contents, update the closing tag with:
  // 1. The number of iterations to perform
  // 2. The position of the start of the loop (eg., .SectionOpen tag)
  section_close := tmpl.lexer.tokens[end_chunk]
  section_close.iters = len(list) - 1
  section_close.start_i = offset
  tmpl.lexer.tokens[end_chunk] = section_close

  // Add each element of the list to the context stack. Add the data in
  // reverse order of the list, so that the first entry is at the top.
  for i := section_close.iters; i >= 0; i -= 1 {
    stack_entry := ContextStackEntry{data=list[i], label="TEMP LIST"}
    inject_at(&tmpl.context_stack, 0, stack_entry)
  }
}

invert_data :: proc(data: Data) -> (Data) {
  inverted := data

  switch _data in data {
  case Map:
    if len(_data) > 0 {
      inverted = "false"
    } else {
      inverted = "true"
    }
  case List:
    if len(_data) > 0 {
      inverted = "false"
    } else {
      inverted = "true"
    }
  case string:
    if !_falsey_context[_data] {
      inverted = "false"
    } else {
      inverted = "true"
    }
  }

  return inverted
}

// Finds the closing tag with a given value after
// the given offset.
template_find_section_close_tag_index :: proc(
  tmpl: ^Template,
  label: string,
  offset: int
) -> (int) {
  for t, i in tmpl.lexer.tokens[offset:] {
    if t.type == .SectionClose && t.value == label {
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
    s = template_stack_extract(tmpl, t)
    s = escape_html_string(s)
  case .TagLiteral, .TagLiteralTriple:
    s = template_stack_extract(tmpl, t)
  case .Newline:
    s = "\n"
  case .SectionOpen, .SectionOpenInverted, .SectionClose, .Comment, .Skip, .EOF, .Partial:
  }

  return s
}

/*
  When a .Partial token is encountered, we need to inject the contents
  of the partial into the current list of tokens.
*/
template_insert_partial :: proc(
  tmpl: ^Template,
  token: Token,
  offset: int
) -> (err: LexerError) {
  partial_name := token.value
  partial_content := data_dig(tmpl.partials, []string{partial_name})

  data, ok := partial_content.(string)
  if !ok {
    fmt.println("Could not find partial content.")
    return
  }

  lexer := Lexer{src=data, line=token.pos.line, delim=CORE_DEF}
  parse(&lexer) or_return

  // Performs any indentation on the .Partial that we are inserting.
  //
  // Example: use the first Token as the indentation for the .Partial Token.
  // [Token{type=.Text, value="  "}, Token{type=.Partial, value="to_add"}]
  //
  standalone := is_standalone_partial(tmpl.lexer, token)
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

template_process :: proc(tmpl: ^Template) -> (output: string, err: RenderError) {
  b: strings.Builder

  root := ContextStackEntry{data=tmpl.data, label="ROOT"}
  inject_at(&tmpl.context_stack, 0, root)

  // First pass to find all the whitespace/newline elements that should be skipped.
  // This is performed up-front due to partial templates -- we cannot check for the
  // whitespace logic *after* the partials have been injected into the template.
  for &t, i in tmpl.lexer.tokens {
    if token_should_skip(tmpl.lexer, t) {
      t.type = .Skip
    }
  }

  // Second pass to render the template.
  i := 0
  for i < len(tmpl.lexer.tokens) {
    defer { i += 1 }
    t := tmpl.lexer.tokens[i]

    switch t.type {
    case .Newline, .Text, .Tag, .TagLiteral, .TagLiteralTriple:
      if token_valid_in_template_context(tmpl, t) {
        strings.write_string(&b, token_content(tmpl, t))
      }
    case .SectionOpen, .SectionOpenInverted:
      template_add_to_context_stack(tmpl, t, i)
      // lexer_print_tokens(tmpl.lexer)
    case .SectionClose:
      template_pop_from_context_stack(tmpl)
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

  return strings.to_string(b), nil
}

render :: proc(
  input: string,
  data: Data,
  partials := Map{}
) -> (s: string, err: RenderError) {
  lexer := Lexer{src=input, delim=CORE_DEF}
  defer delete(lexer.tag_stack)
  defer delete(lexer.tokens)

  parse(&lexer) or_return

  template := Template{lexer=lexer, data=data, partials=partials}
  defer delete(template.context_stack)

  text, ok := template_process(&template)
  return text, nil
}

render_from_filename :: proc(
  filename: string,
  data: Data
) -> (s: string, err: RenderError) {
  src, _ := os.read_entire_file_from_filename(filename)
  str := string(src)

  lexer := Lexer{src=str, delim=CORE_DEF}
  defer delete(lexer.tag_stack)
  defer delete(lexer.tokens)
  parse(&lexer) or_return

  lexer_print_tokens(lexer)

  partials := Map{}
  template := Template{lexer=lexer, data=data, partials=partials}
  defer delete(template.context_stack)

  text, ok := template_process(&template)
  return text, nil
}
