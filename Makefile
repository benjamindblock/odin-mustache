.PHONY: build debug test run

build:
	@mkdir -p bin
	odin build src -show-timings -out:bin/odin-mustache

debug:
	@mkdir -p bin
	odin build src -show-timings -vet -vet-style -out:bin/odin-mustache -warnings-as-errors -debug

test:
	@mkdir -p bin
	odin test src -show-timings -vet -vet-style -out:bin/odin-mustache -warnings-as-errors -debug

run:
	@mkdir -p bin
	odin run src -show-timings -vet -vet-style -out:bin/odin-mustache -warnings-as-errors -debug
