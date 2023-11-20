# odin-mustache
Logic-less templates for Odin

## TODO:


## OLD
### CLI Usage
```
Usage:
  od-mustache [data] template [flags]

Examples:
  $ od-mustache data.yml template.mustache
  $ cat data.yml | od-mustache template.mustache
  $ od-mustache --layout wrapper.mustache data template.mustache
  $ od-mustache --overide over.yml data.yml template.mustache

Flags:
  -h, --help   help for od-mustache
  --layout     a file to use as the layout template
  --override   a data.yml file whose definitions supercede data.yml
```

### Odin Usage
Methods to define:
1. `render` - takes a struct of data and a template in string form
2. `render_file` - takes a struct of data and filename containing the string
3. `compile` - takes a string and returns a compiled template that can be reused
4. `compile_file` - takes a filename and returns a compiled template that can be reused

### Escaping
`od-mustache` follows the official mustache HTML escaping rules. That is, if you enclose a variable with two curly brackets, {{var}}, the contents are HTML-escaped. For instance, strings like 5 > 2 are converted to 5 &gt; 2. To use raw characters, use three curly brackets {{{var}}}.
