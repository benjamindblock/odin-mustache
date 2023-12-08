package mustache

import "core:fmt"
import "core:mem"
import "core:os"

_main :: proc() -> (err: RenderError) {
  defer free_all(context.temp_allocator)

  input := "tmp/test.txt"
  data := Map{
    "name" = "Ben",
    "institution" = "UPS"
  }

  fmt.printf("====== RENDERING\n")
  fmt.printf("Input : '%v'\n", input)
  fmt.printf("Data : '%v'\n", data)
  output := render_from_filename(input, data) or_return
  fmt.printf("Output: %v\n", output)
  fmt.println("")

  return nil
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
