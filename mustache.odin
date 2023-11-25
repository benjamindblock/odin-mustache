package mustache

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

/*
  Mustache characters.
*/
TAG_START :: '{'
TAG_END :: '}'
SECTION_START :: '#'
SECTION_END :: '/'
LITERAL :: '&'
COMMENT :: '!'

/*
  Mustache tag descriptions needed for lexing.
*/
STANDARD_OPEN :: "{{"
STANDARD_CLOSE :: "}}"
LITERAL_CLOSE :: "}}}"
COMMENT_OPEN :: "{{!"

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

TokenType :: enum {
  Text,
  Tag,
  TagLiteral,
  TagLiteralTriple,
  SectionOpen,
  SectionClose,
  Comment,
  CommentStandalone,
  EOF // The last token parsed, caller should not call again.
}

// TODO: Just store the beginning/end position of the string
// rather than the entire string as the value...
Token :: struct {
  type: TokenType,
  value: string,
  start_pos: int,
  end_pos: int
}

Lexer :: struct {
  data: string,
  cursor: int,
  tokens: [dynamic]Token,
  cur_token_type: TokenType,
  last_token_start_pos: int,
  tag_stack: [dynamic]rune,
  standalone_comment: bool
}

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
  context_stack: [dynamic]ContextStackEntry,
  pos: int
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

/*
  Digs data from a Data map, given a list of keys.
*/
data_dig :: proc(data: Data, keys: []string) -> (Data) {
  data := data

  if len(keys) == 0 {
    return data
  }

  for k in keys {
    switch _data in data {
      case string:
        return _data
      case List:
        return _data
      case Map:
        data = _data[k]
    }
  }

  return data
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

// Checks if a rune is plain whitespace.
is_whitespace :: proc(r: rune) -> (res: bool) {
  return r == ' '
}

// Trims all whitespace to the right of a string.
trim_right_whitespace :: proc(s: string) -> (res: string) {
  return strings.trim_right_proc(s, is_whitespace)
}

// Checks if a specific substring appears directly AFTER the provided
// end point in a string.
is_followed_by :: proc(s: string, search: string, end: int) -> (bool) {
  offset := len(search)
  if len(s) > end + offset {
    searchable := s[:end+offset]
    return strings.has_suffix(searchable, search) 
  } else {
    return false
  }
}

// A standalone comment will be on a new line, separate
// from any other content.
is_standalone_comment :: proc(s: string) -> (bool) {
  // If a .Comment is preceded by a .Text tag that is entirely
  // madeup of whitespace, we consider it standalone.
  if len(s) == strings.count(s, " ") {
    return true
  }

  newline_index := strings.index_rune(s, '\n')
  if newline_index == -1 {
    return false
  }

  for i := newline_index+1; i < len(s); i += 1 {
    if !strings.is_space(rune(s[i])) {
      return false
    }
  }

  return true
}

/*
  Adds a new token to our list.
*/
append_token :: proc(lexer: ^Lexer, token_type: TokenType) {
  start_pos := lexer.last_token_start_pos
  end_pos := lexer.cursor
  token_text := lexer.data[start_pos:end_pos]

  // Superfluous whitespace inside a tag should be ignored when
  // we access the data.
  #partial switch token_type {
    // A text tag will be added as a Token without any modifications.
    case .Text:
      token_text = lexer.data[start_pos:end_pos]
      if is_followed_by(lexer.data, COMMENT_OPEN, end_pos) && is_standalone_comment(token_text) {
        lexer.standalone_comment = true
        token_text = trim_right_whitespace(token_text)
      }

    // Remove all empty whitespace inside a valid tag so that we don't
    // mess up our access of the data.
    case .Tag, .TagLiteral, .TagLiteralTriple, .SectionOpen, .SectionClose:
      token_text, _ = strings.remove_all(token_text, " ")

    // Comment tags will not have their content output. Set to blank.
    case .Comment:
      token_text = ""
  }

  // fmt.printf("Token '%v'\n", token_text)

  if start_pos != end_pos && len(token_text) > 0 {
    token := Token{
      type=token_type,
      value=token_text,
      start_pos=start_pos,
      end_pos=end_pos
    }
    append(&lexer.tokens, token)
  }
}

/*
  Used AFTER a new Token is inserted into the tokens dynamic
  array. In the case of a .TagLiteral ('{{{...}}}'), we need
  to advance the next start position by three instead of two,
  to account for the additional brace.
*/
lexer_reset_token :: proc(lexer: ^Lexer, new_type: TokenType) {
  cur_type := lexer.cur_token_type

  if cur_type == .TagLiteralTriple || new_type == .TagLiteralTriple {
    lexer.last_token_start_pos = lexer.cursor + len(LITERAL_CLOSE)
  } else {
    lexer.last_token_start_pos = lexer.cursor + len(STANDARD_CLOSE)
  }

  if cur_type == .Comment && lexer.standalone_comment {
    chomping := true
    for i := lexer.last_token_start_pos; i < len(lexer.data) && chomping; i += 1 {
      if rune(lexer.data[i]) == '\n' || rune(lexer.data[i]) == '\r' {
        lexer.last_token_start_pos += 1
      } else {
        chomping = false
      }
    }

    lexer.standalone_comment = false
  }

  lexer.cur_token_type = new_type
}

/*
  Used when we move from a standard .Tag to a more special kind
  (.TagLiteral, .SectionOpen, .SectionClose). We need to update
  the current type tracked by lexer, and increase the content
  start position by one to account for the additional token.
*/
lexer_update_token :: proc(lexer: ^Lexer, new_type: TokenType) {
  lexer.last_token_start_pos += 1
  lexer.cur_token_type = new_type
}

lexer_push_brace :: proc(lexer: ^Lexer, brace: rune) {
  inject_at(&lexer.tag_stack, 0, brace)
}

lexer_peek_brace :: proc(lexer: ^Lexer) -> (rune) {
  if len(lexer.tag_stack) == 0 {
    return 0
  } else {
    return lexer.tag_stack[0]
  }
}

lexer_pop_brace :: proc(lexer: ^Lexer) {
  ordered_remove(&lexer.tag_stack, 0)
}

lexer_tag_stack_len :: proc(lexer: ^Lexer) -> (int) {
  return len(lexer.tag_stack)
}

lexer_peek :: proc(lexer: ^Lexer, forward := 1) -> (rune) {
  peek_i := lexer.cursor + forward
  peeked := rune(lexer.data[peek_i])
  return peeked
}

parse :: proc(lex: ^Lexer) -> (ok: bool) {
  for ch, i in lex.data {
    lex.cursor = i

    switch {
      case ch == TAG_START:
        lexer_push_brace(lex, ch)
      case ch == TAG_END:
        lexer_pop_brace(lex)
    }

    switch {
      case ch == TAG_START && lexer_peek(lex) == TAG_START && lexer_peek(lex, 2) == TAG_START:
        // If we were processing text and hit an opening brace '{',
        // then create that text token and flag that we are heading
        // inside a brace now.
        if lex.cur_token_type == .Text {
          append_token(lex, TokenType.Text)
          lexer_reset_token(lex, .TagLiteralTriple)
        }
      case ch == TAG_START && lexer_peek(lex) == TAG_START:
        // If we were processing text and hit an opening brace '{',
        // then create that text token and flag that we are heading
        // inside a brace now.
        if lex.cur_token_type == .Text {
          append_token(lex, TokenType.Text)
          lexer_reset_token(lex, .Tag)
        }
      case ch == TAG_END:
        // If we hit the end of a tag and are not in a text tag,
        // create a new tag. If in text and we came across a random
        // '}' rune, don't do anything.
        if lexer_tag_stack_len(lex) > 0 && lex.cur_token_type != .Text {
          append_token(lex, lex.cur_token_type)
          lexer_reset_token(lex, .Text)
        }
      case ch == SECTION_START && lexer_peek_brace(lex) == TAG_START:
        lexer_update_token(lex, .SectionOpen)
      case ch == SECTION_END && lexer_peek_brace(lex) == TAG_START:
        lexer_update_token(lex, .SectionClose)
      case ch == LITERAL && lexer_peek_brace(lex) == TAG_START:
        lexer_update_token(lex, .TagLiteral)
      case ch == COMMENT && lexer_peek_brace(lex) == TAG_START:
        lexer_update_token(lex, .Comment)
    }
  }

  if lexer_tag_stack_len(lex) > 0 {
    // Fail out if we have unbalanced braces for tags.
    fmt.println("Unbalanced braces detected.")
    return false
  } else {
    // Add the last tag.
    lex.cursor += 1
    append_token(lex, lex.cur_token_type)
    lex.cur_token_type = .EOF
    return true
  }
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
  Sections can have false-y values in their corresponding data. When this
  is the case, the section should not be rendered. Example:

  input := "\"{{#boolean}}This should not be rendered.{{/boolean}}\""
  data := Map {
    "boolean" = "false"
  }

  A Map is a valid top context, as well as any string NOT in the
  _falsey_context mapping.

  .SectionClose and .Comment tokens have no impact on our output, so they
  always are true.
*/
token_valid_in_template_context :: proc(tmpl: ^Template, token: Token) -> (bool) {
  // The root stack is always valid.
  current_stack := tmpl.context_stack[0]
  if current_stack.label == "ROOT" {
    return true
  }

  #partial switch token.type {
    case .SectionClose:
      return true
    case .Comment:
      return true
  }

  switch _data in current_stack.data {
    case Map:
      return true
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
template_stack_extract :: proc(tmpl: ^Template, token: Token, escape_html: bool) -> (string) {
  if token.value == "." {
    return tmpl.context_stack[0].data.(string)
  }

  ids := strings.split(token.value, ".", allocator=context.temp_allocator)

  resolved: Data
  for ctx in tmpl.context_stack {
    resolved = data_dig(ctx.data, ids[0:1])
    if resolved != nil {
      break
    }
  }

  // Apply "dotted name resolution" if we have parts after the core ID.
  if len(ids[1:]) > 0 {
    resolved = data_dig(resolved, ids[1:])
  }

  // Make sure that the final value is a string. If not, raise
  // error.
  str, ok := resolved.(string)
  if !ok {
    fmt.println("COULD NOT RESOLVE TO A STRING")
    return ""
  }

  if escape_html {
    str = escape_html_string(str)
  }

  return str
}

template_print_stack :: proc(tmpl: ^Template) {
  fmt.println("Current stack")
  for c, i in tmpl.context_stack {
    fmt.printf("\t[%v] %v: %v\n", i, c.label, c.data)
  }
}

/*
  ... when a list is encountered ...

  .SectionOpen #repo ["resque", "sidekiq", "countries"]
    .Text
    .Tag
  .SectionClose /repo

  ... becomes ...

  .SectionOpen #repo ["resque", "sidekiq", "countries"]
    .SectionOpen "resque"
      .Text
      .Tag
    .SectionClose "resque"
    .SectionOpen "sidekiq"
      .Text
      .Tag
    .SectionClose "sidekiq"
    .SectionOpen "countries"
      .Text
      .Tag
    .SectionClose "countries"
  .SectionClose /repo
*/
template_add_to_context_stack :: proc(tmpl: ^Template, data_id: string, index: int) {
  ids := strings.split(data_id, ".", allocator=context.temp_allocator)

  // New stack entries always need to resolve against the current top
  // of the stack entry.
  to_add := data_dig(tmpl.context_stack[0].data, ids)

  switch _data in to_add {
    case Map:
      stack_entry := ContextStackEntry{data=to_add, label=data_id}
      inject_at(&tmpl.context_stack, 0, stack_entry)
    case List:
      // template_pop_from_context_stack(tmpl)
      start_chunk := index + 1
      end_chunk := template_find_section_close_tag_index(tmpl, data_id, index)
      chunk := slice.clone_to_dynamic(tmpl.lexer.tokens[start_chunk:end_chunk])

      // Remove the original chunk from the token list.
      for _ in start_chunk..<end_chunk {
        ordered_remove(&tmpl.lexer.tokens, start_chunk)
      }

      // Add the "loop" chunk N-times to the token list.
      ordered_remove(&tmpl.context_stack, 0)
      insert_length := 0
      for i in 0..<len(_data) {
        // When performing list-substitution, add a .SectionClose to pop off
        // the top item IF it is NOT a list items. List items will need to
        // undergo substitution and should not be discarded.
        #partial switch _d in _data[i] {
          case Map, string:
            inject_at(&tmpl.lexer.tokens, start_chunk, Token{.SectionClose, "TEMP LIST", 0, 0})
            insert_length += 1
        }
        #reverse for t in chunk {
          inject_at(&tmpl.lexer.tokens, start_chunk, t)
          insert_length += 1
        }

        // Add the loop data to the context_stack in reverse order of the list,
        // so that the first entry is at the top.
        stack_entry := ContextStackEntry{data=_data[len(_data)-1-i], label="TEMP LIST"}
        inject_at(&tmpl.context_stack, 0, stack_entry)
      }
    case string:
      stack_entry := ContextStackEntry{data=to_add, label=data_id}
      inject_at(&tmpl.context_stack, 0, stack_entry)
  }
}

template_find_section_close_tag_index :: proc(tmpl: ^Template, label: string, index: int) -> (int) {
  for token, i in tmpl.lexer.tokens[index:] {
    #partial switch token.type {
      case .SectionClose:
        if token.value == label {
          return i + index
        }
    }
  }

  return -1
}

template_pop_from_context_stack :: proc(tmpl: ^Template) {
  if len(tmpl.context_stack) > 1 {
    ordered_remove(&tmpl.context_stack, 0)
  }
}

template_print_tokens :: proc(tmpl: ^Template) {
  for t, i in tmpl.lexer.tokens {
    if i == tmpl.pos {
      fmt.println(" -->", t)
    } else {
      fmt.println("    ", t)
    }
  }
}

template_process :: proc(tmpl: ^Template) -> (output: string, ok: bool) {
  str: [dynamic]string
  root := ContextStackEntry{data=tmpl.data, label="ROOT"}
  inject_at(&tmpl.context_stack, 0, root)

  for token, i in tmpl.lexer.tokens {
    tmpl.pos = i

    if !token_valid_in_template_context(tmpl, token) {
      continue
    }

    switch token.type {
      case .Text:
        append(&str, token.value)
      case .Tag:
        append(&str, template_stack_extract(tmpl, token, true))
      case .TagLiteral:
        append(&str, template_stack_extract(tmpl, token, false))
      case .TagLiteralTriple:
        append(&str, template_stack_extract(tmpl, token, false))
      case .SectionOpen:
        template_add_to_context_stack(tmpl, token.value, i)
      case .SectionClose:
        template_pop_from_context_stack(tmpl)
      // Do nothing for these cases.
      case .Comment:
      case .CommentStandalone:
      case .EOF:
    }
  }

  output = strings.concatenate(str[:])
  return output, true
}

render :: proc(input: string, data: Data) -> (string, bool) {
  lexer := Lexer{data=input}
  defer delete(lexer.tag_stack)
  defer delete(lexer.tokens)

  if !parse(&lexer) {
    return "", false
  }

  template := Template{lexer=lexer, data=data, pos=0}
  return template_process(&template)
}

_main :: proc() -> (err: Error) {
  defer free_all(context.temp_allocator)

  // TEST 2
  input := "{{#repo}}\n<b>{{.}}</b>{{/repo}}"
  data := Map {
    "repo" = List{"resque", "sidekiq", "countries"}
  }

  fmt.printf("====== RENDERING\n")
  fmt.printf("Input : '%v'\n", input)
  output, ok := render(input, data)
  if !ok {
    return .Something
  }
  fmt.printf("Output: %v\n", output)
  fmt.println("")

  // TEST 2
  input = "{{#os}}\n<b>{{name}}</b>{{/os}}"
  data = Map {
    "os" = List{
      Map { "name" = "MacOS" },
      Map { "name" = "Windows" }
    }
  }

  fmt.printf("====== RENDERING\n")
  fmt.printf("Input : '%v'\n", input)
  output, ok = render(input, data)
  if !ok {
    return .Something
  }
  fmt.printf("Output: %v\n", output)
  fmt.println("")

  // TEST 3
  input = "{{#.}}({{value}}){{/.}}"
  data2 := List {
    Map { "value" = "a" },
    Map { "value" = "b" }
  }

  fmt.printf("====== RENDERING\n")
  fmt.printf("Input : '%v'\n", input)
  output, ok = render(input, data2)
  if !ok {
    return .Something
  }
  fmt.printf("Output: %v\n", output)
  fmt.println("")

  // TEST 4
  input = "\"{{#list}}({{#.}}{{.}}{{/.}}){{/list}}\""
  data2 = List {
    List{"1", "2", "3"},
    List{"a", "b", "c"}
  }

  fmt.printf("====== RENDERING\n")
  fmt.printf("Input : '%v'\n", input)
  output, ok = render(input, data2)
  if !ok {
    return .Something
  }
  fmt.printf("Output: %v\n", output)
  fmt.println("")

  return .None
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
