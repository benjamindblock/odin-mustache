package mustache

Lexer_Error :: union {
  Unbalanced_Tags
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
  ctag_delim: string
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
  ctag_delim = "=}}"
}

Token :: struct {
  type: Token_Type,
  value: string,
  pos: Pos,
  iters: int,
  start_i: int
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
  cur_token_type: Token_Type,
  cur_token_start_pos: int,
  tag_stack: [dynamic]rune,
  delim: Token_Delimiters
}

Data_Error :: enum {
	None,
	Unsupported_Type,
  Map_Key_Not_Found
}

Template_Error :: union {
	Data_Error
}

Template :: struct {
  lexer: Lexer,
  data: any,
  partials: any,
  context_stack: [dynamic]ContextStackEntry
}

ContextStackEntry :: struct {
  data: any,
  label: string
}

Data_Type :: enum {
  Map,
  Struct,
  List,
  Value,
  Null
}

// 1. A map from string => JSON_Data
// 2. A list of JSON_Data
// 3. A value of some kind (string, int, etc.)
JSON_Map :: distinct map[string]JSON_Data
JSON_List :: distinct [dynamic]JSON_Data
JSON_Data :: union {
  JSON_Map,
  JSON_List,
  any
}
