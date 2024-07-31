.PHONY: build check debug test release run

# Build the 
build:
	@mkdir -p bin
	odin build src \
	  -out:bin/odin-mustache \
	  -vet \
	  -show-timings \
	  -no-dynamic-literals

# Similar to build, but with aggresive optimization and stricter checks.
release:
	@mkdir -p bin
	odin build src \
	  -out:bin/odin-mustache \
	  -o:speed \
	  -vet \
	  -strict-style \
	  -show-timings \
	  -no-dynamic-literals \
	  -warnings-as-errors

# Run an example program.
run: release
	bin/odin-mustache test/template.txt test/data.json test/layout.txt

# Check the code only, do not run or build.
check:
	odin check src -vet -strict-style -no-dynamic-literals

# Build in debug mode.
debug:
	@mkdir -p bin
	odin build src \
	  -out:bin/odin-mustache \
	  -debug \
	  -show-timings \
	  -strict-style \
	  -vet \
	  -warnings-as-errors

# Run tests.
test:
	@mkdir -p bin
	odin test src \
	  -out:bin/odin-mustache-test \
	  -debug \
	  -show-timings \
	  -strict-style \
	  -warnings-as-errors
