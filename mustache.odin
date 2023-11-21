package mustache

import "core:container/queue"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:strconv"

TAG_START :: '{'
TAG_END :: '}'
SECTION_START :: '#'
SECTION_END :: '/'
LITERAL :: '&'

STANDARD_CLOSE :: "}}"
LITERAL_CLOSE :: "}}}"

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
  tag_stack: queue.Queue(rune)
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

Template :: struct {
  lexer: Lexer,
  data: Data
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

/*
  Adds a new token to our list.
*/
append_token :: proc(lexer: ^Lexer, token_type: TokenType) {
  start_pos := lexer.last_token_start_pos
  end_pos := lexer.cursor
  token_text: string

  // Superfluous whitespace inside a tag should be ignored when
  // we access the data.
  #partial switch token_type {
    case .Text:
      token_text = lexer.data[start_pos:end_pos]
    case:
      token_text, _ = strings.remove_all(lexer.data[start_pos:end_pos], " ")
  }

  if start_pos != end_pos && len(token_text) > 0 {
    token := Token{type=token_type, value=token_text, start_pos=start_pos, end_pos=end_pos}
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
  queue.push_front(&lexer.tag_stack, brace)
}

lexer_peek_brace :: proc(lexer: ^Lexer) -> (rune) {
  if queue.len(lexer.tag_stack) == 0 {
    return 0
  } else {
    return queue.peek_front(&lexer.tag_stack)^
  }
}

lexer_pop_brace :: proc(lexer: ^Lexer) {
  queue.pop_front_safe(&lexer.tag_stack)
}

lexer_tag_stack_len :: proc(lexer: ^Lexer) -> (int) {
  return queue.len(lexer.tag_stack)
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

data_extract :: proc(data: map[string]Data, token: Token, scope: ^queue.Queue(string), escape_html: bool) -> (string) {
  cur_scope := data
  output: string
  key := token.value

  dotted_keys := strings.split(key, ".", allocator=context.temp_allocator)
  if len(dotted_keys) > 1 {
    for i in 0..<(len(dotted_keys) - 1) {
      queue.push_back(scope, dotted_keys[i])
    }

    key = dotted_keys[len(dotted_keys) - 1]
  }

  for i in 0..<queue.len(scope^) {
    new_scope := cur_scope[queue.get(scope, i)]
    fmt.println("cur_scope:", cur_scope)
    fmt.println("new_scope key:", queue.get(scope, i))
    #partial switch _new_scope in new_scope {
      case map[string]Data:
        cur_scope = _new_scope
    }
  }

  text, ok := cur_scope[key]
  if !ok {
    fmt.println("Could not find", key, "in", cur_scope)
    output = ""
  } else {
    output = text.(string)
  }

  if escape_html {
    output = escape_html_string(output)
  }

  // Return the scope stack to its rightful place after parsing
  // out the dot-notation keys and adding to the scope.
  for i in 0..<(len(dotted_keys) - 1) {
    queue.pop_front(scope)
  }

  return output
}

process_template :: proc(tmpl: ^Template) -> (output: string, ok: bool) {
  str: [dynamic]string
  q: queue.Queue(string)

  for token in tmpl.lexer.tokens {
    #partial switch token.type {
      case .Text:
        append(&str, token.value)
      case .Tag:
        switch data in tmpl.data {
          case string:
            append(&str, escape_html_string(data))
          case map[string]Data:
            append(&str, data_extract(data, token, &q, true))
        }
      case .TagLiteral:
        switch data in tmpl.data {
          case string:
            append(&str, data)
          case map[string]Data:
            append(&str, data_extract(data, token, &q, false))
        }
      case .TagLiteralTriple:
        switch data in tmpl.data {
          case string:
            append(&str, data)
          case map[string]Data:
            append(&str, data_extract(data, token, &q, false))
        }
      case .SectionOpen:
        queue.push_front(&q, token.value)
      case .SectionClose:
        queue.pop_front(&q)
    }
  }

  output = strings.concatenate(str[:])
  return output, true
}

render :: proc(input: string, data: Data) -> (string, bool) {
  fmt.println("DATA:", data)
  lexer := Lexer{data=input}
  defer queue.destroy(&lexer.tag_stack)
  defer delete(lexer.tokens)

  if !parse(&lexer) {
    return "", false
  }

  fmt.printf("\n====== LEXING COMPLETED\n")
  fmt.printf("%v\n\n", lexer.tokens)

  template := Template{lexer, data}
  return process_template(&template)
}

_main :: proc() -> (err: Error) {
  defer free_all(context.temp_allocator)

  // input := "Hello, {{#person}}{{name}}{{/person}}, my name is {{name}} and {{{verb1}}} to {{verb2}}."
  // data := map[string]Data {
  //   "person" = map[string]Data {
  //     "name" = "Ben"
  //   },
  //   "name" = "Jono",
  //   "verb1" = "I like < >",
  //   "verb2" = "juggle < >"
  // }

  input := "Hello, {{person.name}}."
  data := map[string]Data {
    "person" = map[string]Data {
      "name" = "Ben"
    },
  }

  // input := "Hello, {{{verb1}}}."
  // data := map[string]Data {
  //   "verb1" = "I like < >",
  // }

  // input := "Hello, {Mustache}!"
  // data := ""

  output, ok := render(input, data)
  if !ok {
    return .Something
  }

  fmt.printf("====== RENDERING COMPLETED\n")
  fmt.println("Input :", input)
  fmt.println("Output:", output)
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
