# odin-mustache
Native implementation of {{mustache}} templates in [Odin](https://odin-lang.org).

https://github.com/benjamindblock/odin-mustache/assets/1155805/7d794861-e308-4132-aaa0-f800392208a4

All features are implemented, except for the ability to change delimiters.

All in tests in the [official mustache spec](https://github.com/mustache/spec) pass successfully (except for the delimiters spec suite).

## Documentation

For more information about mustache, see the [mustache project page](https://mustache.github.io) or the mustache [man](https://mustache.github.io/mustache.5.html) [pages](https://mustache.github.io/mustache.1.html).

View some [example mustache files](https://github.com/mustache/mustache/tree/master/examples) to get an overview.

## Usage

### CLI Usage
```
Usage:
  odin-mustache [path to template] [path to JSON]

Example:
  $ odin-mustache template.txt data.json
```

### Odin Usage
#### 1. `render(template: string, data: any, partials: any)`

Renders a template, provided as a `string`. `data` and `partials` should be *either* a `map[string]...` or a `struct`.

All `map` arguments passed **must** be keyed with `string` type data. When parsing a Mustache template, the text inside a tag (eg. `name` inside `{{name}}`) will be parsed as a `string`.

#### 2. `render_from_filename(filename: string, data: any, partials: any)`

Renders a template stored in a text file using `data` and `partials` provided.

#### 3. `render_with_json(template: string, json_filename: string)`

Renders a template `string` using data and partials stored inside a JSON file. `odin-mustache` will handle loading the JSON into a usable format for Mustache to work with.

**NOTE**: The JSON file leverages the following top-level keys:
```
"data":      [required]
"partials":  [optional]
```

#### 4. `render_from_filename_with_json(filename: string, json_filename: string)`

Renders a template stored in a text file using data and partials stored inside a JSON file. `odin-mustache` will handle loading the JSON into a usable format for Mustache to work with.

### Example
```odin
input := "Hello, {{name}}!"
data: map[string]string = {
    "name" = "St. Charles",
}
output, err := render(input, data)
// => "Hello, St. Charles!"
```

### Precompiled Templates
`odin-mustache` works in two steps:
1. Lexing and parsing
2. Rendering with data

If you are rendering the same template multiple times (ex: sending out personalized emails to subscribers), the lexing+parsing step can be performed once to create a compiled template. This compiled template can then be used multiple times with different data.

#### Example
```odin
src := "Hello, {{name}}!"
template: Template
output: string
data: map[string]string
partials: map[string]string

lexer := Lexer{src=src, delim=CORE_DEF}
parse(&lexer)

data = {"name" = "St. Charles"}
template = Template{lexer=lexer, data=data, partials=partials}
output, _ = process(&template)
// => Hello, St. Charles!

data = {"name" = "Edouard"}
template = Template{lexer=lexer, data=data, partials=partials}
output, _ = process(&template)
// => Hello, Edouard!
```

## Escaping
`odin-mustache` follows the official mustache HTML escaping rules. That is, if you enclose a variable with two curly brackets, `{{var}}`, the contents are HTML-escaped. For instance, strings like `5 > 2` are converted to `5 &gt; 2`. To use raw characters, use three curly brackets `{{{var}}}`.

## Future Work
- Improve error handling and reporting
- Add optional logging for debugging and performance work
- Support layouts (non-template text to render a template inside of) 
- Configurable precision for floating point types
- Add support for changing delimiters
- Loop conditionals (eg., checking for the first iteration or last iteration)
