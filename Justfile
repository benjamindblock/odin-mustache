flags := "-vet -show-timings -strict-style -vet-cast -vet-tabs -vet-using-param -disallow-do -vet-semicolon"
name := "odin-mustache"

build:
	@mkdir -p bin
	odin build . -out:bin/{{name}} -debug {{flags}}

test: build
	odin test . -out:bin/{{name}}

run: build
	bin/{{name}} test/template.txt test/data.json test/layout.txt

check:
	odin check . {{flags}}
