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

TokenDelimiter :: struct {
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
  ctag_delim: string
}

CORE_DEF :: TokenDelimiter {
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
  ctag_delim = "=}}"
}

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

Token :: struct {
  type: TokenType,
  value: string,
  pos: Pos
}

TokenType :: enum {
  Text,
  Tag,
  SectionOpenInverted,
  TagLiteral,
  TagLiteralTriple,
  SectionOpen,
  SectionClose,
  Comment,
  Partial,
  Newline,
  EOF // The last token parsed, caller should not call again.
}

Pos :: struct {
  start: int,
  end: int,
  line: int
}

Lexer :: struct {
  src: string,
  cursor: int,
  line: int,
  tokens: [dynamic]Token,
  cur_token_type: TokenType,
  cur_token_start_pos: int,
  tag_stack: [dynamic]rune,
  delim: TokenDelimiter
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
is_whitespace :: proc(r: rune) -> (bool) {
  return _whitespace[r]
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
  Used when we move from a standard .Tag to a more special kind
  (.TagLiteral, .SectionOpen, .SectionClose). We need to update
  the current type tracked by lexer, and increase the content
  start position by one to account for the additional token.
*/
lexer_update_token :: proc(l: ^Lexer, new_type: TokenType) {
  l.cur_token_start_pos += 1
  l.cur_token_type = new_type
}

lexer_push_brace :: proc(l: ^Lexer, brace: rune) {
  inject_at(&l.tag_stack, 0, brace)
}

lexer_peek_brace :: proc(l: ^Lexer) -> (rune) {
  if len(l.tag_stack) == 0 {
    return 0
  } else {
    return l.tag_stack[0]
  }
}

lexer_pop_brace :: proc(l: ^Lexer) {
  ordered_remove(&l.tag_stack, 0)
}

lexer_tag_stack_len :: proc(l: ^Lexer) -> (int) {
  return len(l.tag_stack)
}

peek :: proc(l: ^Lexer, s: string, offset := 0) -> (bool) {
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

/*
  Used AFTER a new Token is inserted into the tokens dynamic
  array. In the case of a .TagLiteral ('{{{...}}}'), we need
  to advance the next start position by three instead of two,
  to account for the additional brace.
*/
lexer_start :: proc(l: ^Lexer, new_type: TokenType) {
  cur_type := l.cur_token_type

  switch {
  // Moving from some type of tag back to regular text.
  case cur_type == .Text:
    switch new_type {
    case .SectionOpen:
      l.cur_token_start_pos = l.cursor + len(l.delim.otag_section_open)
    case .SectionClose:
      l.cur_token_start_pos = l.cursor + len(l.delim.otag_section_close)
    case .SectionOpenInverted:
      l.cur_token_start_pos = l.cursor + len(l.delim.otag_inverted)
    case .Partial:
      l.cur_token_start_pos = l.cursor + len(l.delim.otag_partial)
    case .Comment:
      l.cur_token_start_pos = l.cursor + len(l.delim.otag_comment)
    case .TagLiteral:
      l.cur_token_start_pos = l.cursor + len(l.delim.otag_literal)
    case .TagLiteralTriple:
      l.cur_token_start_pos = l.cursor + len(l.delim.otag_lit)
    case .Tag:
      l.cur_token_start_pos = l.cursor + len(l.delim.otag)
    case .Text, .Newline, .EOF:
    }
  // Moving from some type of tag into text.
  case new_type == .Text:
    switch cur_type {
    case .Newline:
      l.cur_token_start_pos = l.cursor + len("\n")
    case .Tag, .SectionOpenInverted, .TagLiteral, .SectionClose, .SectionOpen, .Comment, .Partial:
      l.cur_token_start_pos = l.cursor + len(l.delim.ctag)
    case .TagLiteralTriple:
      l.cur_token_start_pos = l.cursor + len(l.delim.ctag_lit)
    case .Text, .EOF:
    }
  }

  // Update the current type to the new type.
  l.cur_token_type = new_type
}

/*
  Adds a new token to our list.
*/
lexer_append :: proc(l: ^Lexer) {
  #partial switch l.cur_token_type {
  case .Text:
    append_text(l)
  case .Newline:
    append_newline(l)
  case:
    append_tag(l, l.cur_token_type)
  }
}

append_tag :: proc(l: ^Lexer, token_type: TokenType) {
  pos := Pos{
    start=l.cur_token_start_pos,
    end=l.cursor,
    line=l.line
  }

  if pos.end > pos.start {
    // Remove all empty whitespace inside a valid tag so that we don't
    // mess up our access of the data.
    token_text := l.src[pos.start:pos.end]
    token_text, _ = strings.remove_all(token_text, " ")
    token := Token{type=token_type, value=token_text, pos=pos}
    append(&l.tokens, token)
  }
}

append_text :: proc(l: ^Lexer) {
  pos := Pos{
    start=l.cur_token_start_pos,
    end=l.cursor,
    line=l.line
  }

  if pos.end > pos.start {
    text := l.src[pos.start:pos.end]
    token := Token{type=.Text, value=text, pos=pos}
    append(&l.tokens, token)
  }
}

append_newline :: proc(l: ^Lexer) {
  pos := Pos{
    start=l.cur_token_start_pos,
    end=l.cursor + 1,
    line=l.line
  }

  newline := Token{type=.Newline, value="\n", pos=pos}
  append(&l.tokens, newline)
}

parse :: proc(l: ^Lexer) -> (ok: bool) {
  for ch, i in l.src {
    l.cursor = i

    switch {
      case ch == TAG_START:
        lexer_push_brace(l, ch)
      case ch == TAG_END:
        lexer_pop_brace(l)
    }

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
    case peek(l, l.delim.otag_lit):
      lexer_append(l)
      lexer_start(l, .TagLiteralTriple)
    case peek(l, l.delim.otag_section_open):
      lexer_append(l)
      lexer_start(l, .SectionOpen)
    case peek(l, l.delim.otag_section_close):
      lexer_append(l)
      lexer_start(l, .SectionClose)
    case peek(l, l.delim.otag_inverted):
      lexer_append(l)
      lexer_start(l, .SectionOpenInverted)
    case peek(l, l.delim.otag_partial):
      lexer_append(l)
      lexer_start(l, .Partial)
    case peek(l, l.delim.otag_literal):
      lexer_append(l)
      lexer_start(l, .TagLiteral)
    case peek(l, l.delim.otag_comment):
      lexer_append(l)
      lexer_start(l, .Comment)
    // Be careful with checking for "{{" -- it could be a substring of "{{{"
    case peek(l, l.delim.otag) && l.cur_token_type != .TagLiteralTriple:
      lexer_append(l)
      lexer_start(l, .Tag)
    case ch == TAG_END && l.cur_token_type != .Text:
      lexer_append(l)
      lexer_start(l, .Text)
    }
  }

  if lexer_tag_stack_len(l) > 0 {
    // Fail out if we have unbalanced braces for tags.
    fmt.println("Unbalanced braces detected.")
    return false
  } else {
    // Add the last tag and mark that we hit the end of the file.
    l.cursor += 1
    lexer_append(l)
    l.cur_token_type = .EOF
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

/*
  .SectionOpen #repo ["resque", "sidekiq", "countries"]
    .Text
    .Tag
  .SectionClose /repo

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
template_add_to_context_stack :: proc(tmpl: ^Template, token: Token, index: int) {
  data_id := token.value
  ids := strings.split(data_id, ".", allocator=context.temp_allocator)

  // New stack entries always need to resolve against the current top
  // of the stack entry.
  to_add := data_dig(tmpl.context_stack[0].data, ids)

  // If we couldn't resolve against the top of the stack,
  // add from the root.
  if to_add == nil {
    to_add = data_dig(tmpl.context_stack[len(tmpl.context_stack)-1].data, ids)
  }

  // If we STILL can't find anything, mark this section as false-y.
  if to_add == nil {
    to_add = "false"
  }

  // Inverting the content of a .SectionOpen tag if we are inverting it.
  if token.type == .SectionOpenInverted {
    to_add = invert_data(to_add)
  }

  switch _data in to_add {
  case Map:
    stack_entry := ContextStackEntry{data=to_add, label=data_id}
    inject_at(&tmpl.context_stack, 0, stack_entry)
  case List:
    start_chunk := index + 1
    end_chunk := template_find_section_close_tag_index(tmpl, data_id, index)
    chunk := slice.clone_to_dynamic(tmpl.lexer.tokens[start_chunk:end_chunk])

    // Remove the original chunk from the token list.
    for _ in start_chunk..<end_chunk {
      ordered_remove(&tmpl.lexer.tokens, start_chunk)
    }

    // Add the "loop" chunk N-times to the token list.
    // ordered_remove(&tmpl.context_stack, 0)
    for i in 0..<len(_data) {
      // When performing list-substitution, add a .SectionClose to pop off
      // the top item IF it is NOT a list items. List items will need to
      // undergo substitution and should not be discarded.
      #partial switch _d in _data[i] {
        case Map, string:
          inject_at(
            &tmpl.lexer.tokens,
            start_chunk,
            Token{.SectionClose, "TEMP LIST", Pos{-1, -1, token.pos.line}}
          )
      }

      #reverse for t in chunk {
        inject_at(&tmpl.lexer.tokens, start_chunk, t)
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

lexer_print_tokens :: proc(lexer: Lexer) {
  for t, i in lexer.tokens {
    fmt.println("    ", t)
  }
}

// Retrieves all the tokens that are on a given line of the input text.
tokens_on_line :: proc(lexer: Lexer, line: int) -> (tokens: [dynamic]Token) {
  for t in lexer.tokens {
    if t.pos.line == line {
      append(&tokens, t)
    }
  }

  return tokens
}

// Skip a newline if we are on a line that has either a
// non-blank .Text token OR any valid tags.
should_skip_newline :: proc(lexer: Lexer, token: Token) -> (bool) {
  on_line := tokens_on_line(lexer, token.pos.line)[:]
  defer delete(on_line)

  for t in on_line {
    #partial switch t.type {
    case .Text:
      if !is_text_blank(t.value) {
        return false
      }
    case .Tag, .TagLiteral, .TagLiteralTriple:
      return false
    }
  }

  return true
}

// If we are rendering a .Text tag, we should NOT render it if it is:
//  - On a line with one .Section tag
//  - Comprised of only whitespace, along with all the other .Text tokens
should_skip_text :: proc(lexer: Lexer, token: Token) -> (bool) {
  on_line := tokens_on_line(lexer, token.pos.line)[:]
  defer delete(on_line)

  standalone_tag_count := 0
  for t in on_line {
    #partial switch t.type {
    case .Text:
      if !is_text_blank(t.value) {
        return false
      }
    case .Tag, .TagLiteral, .TagLiteralTriple, .Partial:
      return false
    case .SectionOpen, .SectionOpenInverted, .SectionClose, .Comment:
      standalone_tag_count += 1
    }
  }

  // If we have gotten to the end, that means all the .Text
  // tags on this line are blank. If we also only have a single
  // section or comment tag, that means that tag is standalone.
  return standalone_tag_count == 1
}

/*
  Checks if a given .Partial Token is "standalone."
*/
is_standalone_partial :: proc(lexer: Lexer, token: Token) -> (bool) {
  on_line := tokens_on_line(lexer, token.pos.line)[:]
  defer delete(on_line)

  standalone_tag_count := 0
  for t in on_line {
    #partial switch t.type {
    case .Text:
      if !is_text_blank(t.value) {
        return false
      }
    case .Tag, .TagLiteral, .TagLiteralTriple:
      return false
    case .SectionOpen, .SectionOpenInverted, .SectionClose, .Comment, .Partial:
      standalone_tag_count += 1
    }
  }

  // If we have gotten to the end, that means all the .Text
  // tags on this line are blank. If we also only have a single
  // section or comment tag, that means that tag is standalone.
  return standalone_tag_count == 1
}

/*
  Retrieves the content for a given token.
*/
token_text_content :: proc(tmpl: ^Template, token: Token) -> (str: string) {
  if !token_valid_in_template_context(tmpl, token) {
    return str
  }

  // NOTE: Carriage returns causing some wonkiness with .concatenate.
  if token.value != "\r" {
    return token.value
  }

  return str
}

/*
  Retrieves the content for a given token when it is one of:
    - .Tag [NOTE: Will have HTML codes escaped]
    - .TagLiteral
    - .TagLiteralTriple
*/
token_tag_content :: proc(tmpl: ^Template, token: Token) -> (str: string) {
  if !token_valid_in_template_context(tmpl, token) {
    return str
  }

  str = template_stack_extract(tmpl, token)
  if token.type == .Tag {
    str = escape_html_string(str)
  }
  return str
}

/*
  When a .Partial token is encountered, we need to inject the contents
  of the partial into the current list of tokens.
*/
template_insert_partial :: proc(tmpl: ^Template, token: Token, index: int) {
  partial_name := token.value
  partial_names := [1]string{partial_name}
  partial_content := data_dig(tmpl.partials, partial_names[:])
  is_standalone_partial := is_standalone_partial(tmpl.lexer, token)

  data, ok := partial_content.(string)
  if !ok {
    fmt.println("Could not find partial content.")
    return
  }

  lexer := Lexer{src=data, line=token.pos.line, delim=CORE_DEF}
  if !parse(&lexer) {
    fmt.println("Could not parse partial content.")
    return
  }

  // Performs any indentation on the .Partial that we are inserting.
  //
  // Example: use the first Token as the indentation for the .Partial Token.
  // [Token{type=.Text, value="  "}, Token{type=.Partial, value="to_add"}]
  //
  if index > 0 && is_standalone_partial {
    prev_token := tmpl.lexer.tokens[index-1]
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
    inject_at(&tmpl.lexer.tokens, index+1, t)
  }
}

template_process :: proc(tmpl: ^Template) -> (output: string, ok: bool) {
  str: [dynamic]string
  defer delete(str)

  root := ContextStackEntry{data=tmpl.data, label="ROOT"}
  inject_at(&tmpl.context_stack, 0, root)

  // First pass to find all the whitespace/newline elements
  // that should be removed. This is performed up-front due
  // to the partial templates -- we cannot check for the
  // whitespace logic *after* the partials have been included.
  to_delete: [dynamic]int
  for token, i in tmpl.lexer.tokens {
    #partial switch token.type {
    case .Newline:
      if should_skip_newline(tmpl.lexer, token) {
        append(&to_delete, i) 
      }
    case .Text:
      if should_skip_text(tmpl.lexer, token) {
        append(&to_delete, i) 
      }
    }
  }

  // Remove in reverse order to avoid messing up our index
  // as we iterate.
  #reverse for i in to_delete {
    ordered_remove(&tmpl.lexer.tokens, i)
  }

  // Now render all the content in a single pass.
  for token, i in tmpl.lexer.tokens {
    switch token.type {
    case .Newline, .Text:
      append(&str, token_text_content(tmpl, token))
    case .Tag, .TagLiteral, .TagLiteralTriple:
      append(&str, token_tag_content(tmpl, token))
    case .SectionOpen, .SectionOpenInverted:
      template_add_to_context_stack(tmpl, token, i)
    case .SectionClose:
      template_pop_from_context_stack(tmpl)
    case .Partial:
      template_insert_partial(tmpl, token, i)
    // Do nothing for these tags.
    case .Comment, .EOF:
    }
  }

  output = strings.concatenate(str[:])
  return output, true
}

render :: proc(input: string, data: Data, partials := Map{}) -> (string, bool) {
  lexer := Lexer{src=input, delim=CORE_DEF}
  defer delete(lexer.tag_stack)
  defer delete(lexer.tokens)

  if !parse(&lexer) {
    return "", false
  }

  template := Template{lexer=lexer, data=data, partials=partials}
  defer delete(template.context_stack)

  text, ok := template_process(&template)
  return text, true
}

_main :: proc() -> (err: Error) {
  defer free_all(context.temp_allocator)

  input := "|\r\n{{>partial}}\r\n|"
  data := Map {}
  partials := Map {
    "partial" = ">"
  }

  fmt.printf("====== RENDERING\n")
  fmt.printf("Input : '%v'\n", input)
  fmt.printf("Data : '%v'\n", data)
  output, ok := render(input, data, partials)
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
