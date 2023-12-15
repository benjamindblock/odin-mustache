.PHONY: build

build:
	@mkdir -p bin
	odin build . -show-timings -vet -vet-style -out:bin/odin-mustache -warnings-as-errors

debug:
	@mkdir -p bin
	odin build . -show-timings -vet -vet-style -out:bin/odin-mustache -warnings-as-errors -debug

test:
	@mkdir -p bin
	odin test . -show-timings -vet -vet-style -out:bin/odin-mustache -warnings-as-errors -debug

run:
	@mkdir -p bin
	odin run . -show-timings -vet -vet-style -out:bin/odin-mustache -warnings-as-errors -debug
