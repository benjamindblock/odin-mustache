package mustache

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"

render :: proc(
	template: string,
	data: any,
	partials: any = map[string]string {},
) -> (s: string, err: Render_Error) {
	// Parse template.
	lexer: Lexer
	defer lexer_delete(&lexer)
	lexer.src = template
	lexer.delim = CORE_DEF
	parse(&lexer) or_return

	// Render template
	template: Template
	defer template_delete(&template)
	template.lexer = lexer
	template.data = data
	template.partials = partials

	s = template_render(&template) or_return
	return s, nil
}

render_in_layout :: proc(
	template: string,
	data: any,
	partials: any = map[string]string {},
	layout: string,
) -> (s: string, err: Render_Error) {
	// Parse template.
	lexer: Lexer
	defer lexer_delete(&lexer)
	lexer.src = template
	lexer.delim = CORE_DEF
	parse(&lexer) or_return

	// Render template.
	template: Template
	defer template_delete(&template)
	template.lexer = lexer
	template.data = data
	template.partials = partials
	template.layout = layout

	s = template_render(&template) or_return
	return s, nil
}

render_in_layout_file :: proc(
	template: string,
	data: any,
	partials: any = map[string]string {},
	layout_filename: string,
) -> (s: string, err: Render_Error) {
	// Read layout file.
	layout, _ := os.read_entire_file_from_filename(layout_filename)
	defer delete(layout)

	// Parse template.
	lexer: Lexer
	defer lexer_delete(&lexer)
	lexer.src = template
	lexer.delim = CORE_DEF
	parse(&lexer) or_return

	// Render template
	template: Template
	defer template_delete(&template)
	template.lexer = lexer
	template.data = data
	template.partials = partials
	template.layout = string(layout)

	s = template_render(&template) or_return
	return s, nil
}

render_from_filename :: proc(
	filename: string,
	data: any,
	partials: any = map[string]string {},
) -> (s: string, err: Render_Error) {
	// Read template file.
	src, _ := os.read_entire_file_from_filename(filename)
	defer delete(src)

	// Parse template.
	lexer: Lexer
	defer lexer_delete(&lexer)
	lexer.src = string(src)
	lexer.delim = CORE_DEF
	parse(&lexer) or_return

	// Render template.
	template: Template
	defer template_delete(&template)
	template.lexer = lexer
	template.data = data
	template.partials = partials

	s = template_render(&template) or_return
	return s, nil
}

render_from_filename_in_layout :: proc(
	filename: string,
	data: any,
	partials: any = map[string]string {},
	layout: string,
) -> (s: string, err: Render_Error) {
	// Read template file.
	src, _ := os.read_entire_file_from_filename(filename)
	defer delete(src)

	// Parse template.
	lexer: Lexer
	defer lexer_delete(&lexer)
	lexer.src = string(src)
	lexer.delim = CORE_DEF
	parse(&lexer) or_return

	// Render template.
	template: Template
	defer template_delete(&template)
	template.lexer = lexer
	template.data = data
	template.partials = partials
	template.layout = layout

	s = template_render(&template) or_return
	return s, nil
}

render_from_filename_in_layout_file :: proc(
	filename: string,
	data: any,
	partials: any = map[string]string {},
	layout_filename: string,
) -> (s: string, err: Render_Error) {
	// Read template file.
	src, _ := os.read_entire_file_from_filename(filename)
	defer delete(src)

	// Read layout file.
	layout, _ := os.read_entire_file_from_filename(layout_filename)
	defer delete(layout)

	// Parse template.
	lexer: Lexer
	defer lexer_delete(&lexer)
	lexer.src = string(src)
	lexer.delim = CORE_DEF
	parse(&lexer) or_return

	// Render template
	template: Template
	defer template_delete(&template)
	template.lexer = lexer
	template.data = data
	template.partials = partials
	template.layout = string(layout)

	s = template_render(&template) or_return
	return s, nil
}

render_with_json :: proc(
	template: string,
	json_filename: string,
) -> (s: string, err: Render_Error) {
	// Load JSON.
	json_src, _ := os.read_entire_file_from_filename(json_filename)
	defer delete(json_src)
	json_data := json.parse(json_src) or_return
	defer json.destroy_value(json_data)
	json_root := json_data.(json.Object)

	// Parse template.
	lexer: Lexer
	defer lexer_delete(&lexer)
	lexer.src = template
	lexer.delim = CORE_DEF
	parse(&lexer) or_return

	// Render template.
	template: Template
	defer template_delete(&template)
	template.lexer = lexer
	template.data = json_root["data"]
	template.partials = json_root["partials"]

	s = template_render(&template) or_return
	return s, nil
}

render_with_json_in_layout :: proc(
	template: string,
	json_filename: string,
	layout: string,
) -> (s: string, err: Render_Error) {
	// Load JSON.
	json_src, _ := os.read_entire_file_from_filename(json_filename)
	defer delete(json_src)
	json_data := json.parse(json_src) or_return
	defer json.destroy_value(json_data)
	json_root := json_data.(json.Object)

	// Parse template.
	lexer: Lexer
	defer lexer_delete(&lexer)
	lexer.src = template
	lexer.delim = CORE_DEF
	parse(&lexer) or_return

	// Render template.
	template: Template
	defer template_delete(&template)
	template.lexer = lexer
	template.data = json_root["data"]
	template.partials = json_root["partials"]
	template.layout = layout

	s = template_render(&template) or_return
	return s, nil
}

render_with_json_in_layout_file :: proc(
	template: string,
	json_filename: string,
	layout_filename: string,
) -> (s: string, err: Render_Error) {
	// Read layout file.
	layout, _ := os.read_entire_file_from_filename(layout_filename)
	defer delete(layout)

	// Load JSON.
	json_src, _ := os.read_entire_file_from_filename(json_filename)
	defer delete(json_src)
	json_data := json.parse(json_src) or_return
	defer json.destroy_value(json_data)
	json_root := json_data.(json.Object)

	// Parse template.
	lexer: Lexer
	defer lexer_delete(&lexer)
	lexer.src = template
	lexer.delim = CORE_DEF
	parse(&lexer) or_return

	// Render template.
	template: Template
	defer template_delete(&template)
	template.lexer = lexer
	template.data = json_root["data"]
	template.partials = json_root["partials"]
	template.layout = string(layout)

	s = template_render(&template) or_return
	return s, nil
}

render_from_filename_with_json :: proc(
	filename: string,
	json_filename: string,
) -> (s: string, err: Render_Error) {
	// Read template file.
	src, _ := os.read_entire_file_from_filename(filename)
	defer delete(src)

	// Load JSON.
	json_src, _ := os.read_entire_file_from_filename(json_filename)
	defer delete(json_src)
	json_data := json.parse(json_src) or_return
	defer json.destroy_value(json_data)
	json_root := json_data.(json.Object)

	// Parse template.
	lexer: Lexer
	defer lexer_delete(&lexer)
	lexer.src = string(src)
	lexer.delim = CORE_DEF
	parse(&lexer) or_return

	// Render template.
	template: Template
	defer template_delete(&template)
	template.lexer = lexer
	template.data = json_root["data"]
	template.partials = json_root["partials"]

	s = template_render(&template) or_return
	return s, nil
}

render_from_filename_with_json_in_layout :: proc(
	filename: string,
	json_filename: string,
	layout: string,
) -> (s: string, err: Render_Error) {
	// Read template file.
	src, _ := os.read_entire_file_from_filename(filename)
	defer delete(src)

	// Load JSON.
	json_src, _ := os.read_entire_file_from_filename(json_filename)
	defer delete(json_src)
	json_data := json.parse(json_src) or_return
	defer json.destroy_value(json_data)
	json_root := json_data.(json.Object)

	// Parse template.
	lexer: Lexer
	defer lexer_delete(&lexer)
	lexer.src = string(src)
	lexer.delim = CORE_DEF
	parse(&lexer) or_return

	// Render template.
	template: Template
	defer template_delete(&template)
	template.lexer = lexer
	template.data = json_root["data"]
	template.partials = json_root["partials"]
	template.layout = layout

	s = template_render(&template) or_return
	return s, nil
}

render_from_filename_with_json_in_layout_file :: proc(
	filename: string,
	json_filename: string,
	layout_filename: string,
) -> (s: string, err: Render_Error) {
	// Read template file.
	src, _ := os.read_entire_file_from_filename(filename)
	defer delete(src)

	// Read layout file.
	layout, _ := os.read_entire_file_from_filename(layout_filename)
	defer delete(layout)

	// Load JSON.
	json_src, _ := os.read_entire_file_from_filename(json_filename)
	defer delete(json_src)
	json_data := json.parse(json_src) or_return
	defer json.destroy_value(json_data)
	json_root := json_data.(json.Object)

	// Parse template.
	lexer: Lexer
	defer lexer_delete(&lexer)
	lexer.src = string(src)
	lexer.delim = CORE_DEF
	parse(&lexer) or_return

	// Render template.
	template: Template
	defer template_delete(&template)
	template.lexer = lexer
	template.data = json_root["data"]
	template.partials = json_root["partials"]
	template.layout = string(layout)

	s = template_render(&template) or_return
	return s, nil
}

error :: proc(msg: string, args: ..any) -> ! {
	fmt.eprint("\x1b[0;31modin-mustache Error:\x1b[0m ")
	fmt.eprintf(msg, ..args)
	fmt.eprint("\n")
	os.exit(1)
}

_main :: proc(
	template_filename: string,
	json_filename: string,
) -> (output: string, err: Render_Error) {
	return render_from_filename_with_json(template_filename, json_filename)
}

main :: proc() {
	defer free_all(context.temp_allocator)

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		defer mem.tracking_allocator_destroy(&track)
		context.allocator = mem.tracking_allocator(&track)
	}

	if len(os.args) != 3 {
		error("You need to pass paths to the template and JSON data.")
	}

	if output, err := _main(os.args[1], os.args[2]); err != nil {
		fmt.printf("Err: %v\n", err)
		os.exit(1)
	} else {
		fmt.eprint(output)
	}

	when ODIN_DEBUG {
		for _, entry in track.allocation_map {
			fmt.eprintf("%m leaked at %v\n", entry.location, entry.size)
		}

		for entry in track.bad_free_array {
			fmt.eprintf("%v allocation %p was freed badly\n", entry.location, entry.memory)
		}
	}
}
