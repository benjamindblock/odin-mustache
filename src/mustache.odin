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
	lexer := Lexer{
		src=template,
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
	partials: any = map[string]string {},
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
	template: string,
	json_filename: string,
) -> (s: string, err: Render_Error) {
	json_src, _ := os.read_entire_file_from_filename(json_filename)
	defer delete(json_src)
	json_data := json.parse(json_src) or_return
	defer json.destroy_value(json_data)
	json_root := json_data.(json.Object)

	lexer := Lexer{
		src=template,
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
