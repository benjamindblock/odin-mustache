.PHONY: build check debug test

build:
	@mkdir -p bin
	odin build src -show-timings -out:bin/odin-mustache

check:
	odin check src -vet -strict-style

debug:
	@mkdir -p bin
	odin build src -show-timings -vet -strict-style -out:bin/odin-mustache -warnings-as-errors -debug

test:
	@mkdir -p bin
	odin test src -show-timings -vet -strict-style -out:bin/odin-mustache -warnings-as-errors -debug
