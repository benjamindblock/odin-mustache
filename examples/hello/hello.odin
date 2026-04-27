package main

import "core:fmt"
import "core:os"

import mustache "../.."

Person :: struct {
	name:        string,
	languages:   []string,
	show_footer: bool,
}

main :: proc() {
	data := Person{
		name      = "World",
		languages = {"Odin", "C", "Rust"},
		show_footer = true,
	}

	result, err := mustache.render_from_filename("hello.mustache", data)
	if err != nil {
		fmt.eprintfln("render error: %v", err)
		os.exit(1)
	}

	fmt.print(result)
}
