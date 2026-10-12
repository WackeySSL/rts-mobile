extends GdUnitTestSuite
## An inner class that names itself as a runtime value in its own body (`Name.new()`, `x is Name`)
## leaves every loaded script alive when the engine exits, once a suite that names its base class
## has run before the suite that holds it. Godot then prints "ObjectDB instances were leaked at
## exit", "resources still in use at exit" and "Pages in use exist at exit", and verify.sh fails
## on those lines. Every test passes; only the exit shows it.
##
## The suites run in the order the file system lists them, which differs from machine to machine
## (P26n2: tests/ui/test_perf_probe_worker.gd was green locally and red on CI, where
## tests/ui/test_perf_probe_native.gd ran first). So the pattern is refused here, on every machine.
## Proved with a project script as the base class; the same code in a plain RefCounted class, a
## type annotation (`-> Name`, `var t: Name`), a constant (`Name.CONST`) and the same call in the
## enclosing script did not leak. Name the class outside its own body: a helper in the enclosing
## script builds the instance.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const ROOTS: Array[String] = ["res://game", "res://tests"]
const KNOWN_SCRIPT: String = "res://tests/ui/test_perf_probe_worker.gd"

const CLASS_LINE: String = r"^(\t*)class (\w+)\b[^:]*:"
const STRING_LITERAL: String = r"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'"

## Source that has the leak: each names the class `A` inside `A`.
const MUST_FLAG: Array[String] = [
	"class A:\n\textends B\n\tstatic func make() -> A:\n\t\treturn A.new()\n",
	"class A extends B:\n\tfunc is_mine(other: Object) -> bool:\n\t\treturn other is A\n",
	"class A:\n\textends B\n\tfunc copy() -> A:\n\t\tvar c: A = A.new()\n\t\treturn c\n",
	"class A:\n\textends B\n\n\tclass C:\n\t\tfunc make() -> C:\n\t\t\treturn C.new()\n",
]

## Source the scan leaves alone. The first three were seen not to leak (a constant, a type
## annotation, the call in the enclosing script); the rest is outside the pattern.
const MUST_PASS: Array[String] = [
	"class A:\n\textends B\n\tconst N: int = 1\n\tstatic func n() -> int:\n\t\treturn A.N\n",
	"class A:\n\textends B\n\tfunc make() -> A:\n\t\tvar t: A = null\n\t\treturn t\n",
	"class A:\n\textends B\n\nfunc make() -> A:\n\treturn A.new()\n",
	"class A:\n\textends B\n\tfunc other() -> Object:\n\t\treturn C.new()\n",
	'class A:\n\textends B\n\t# A.new() is only a comment\n\tconst TEXT: String = "A.new()"\n',
	"var made: Object = A.new()\n",
]


func test_a_class_that_names_itself_in_its_own_body_is_flagged() -> void:
	for source: String in MUST_FLAG:
		assert_array(_find(source)).override_failure_message(source).is_not_empty()


func test_code_that_does_not_need_the_leak_is_not_flagged() -> void:
	for source: String in MUST_PASS:
		assert_array(_find(source)).override_failure_message(source).is_empty()


func test_no_inner_class_in_game_or_tests_names_itself_in_its_own_body() -> void:
	var scripts: Array[String] = []
	for root: String in ROOTS:
		scripts.append_array(FileScan.list_files(root, ".gd"))
	# Guards against the scan passing because it found nothing.
	assert_array(scripts).contains([KNOWN_SCRIPT])
	var found: Array[String] = []
	for path: String in scripts:
		for hit: String in _find(FileAccess.get_file_as_string(path)):
			found.append("%s %s" % [path, hit])
	assert_array(found).override_failure_message("\n".join(found)).is_empty()


## "line N: text" for each line of `source` that names the inner class it sits in, as a call to
## its `new()` or as the right side of `is`. Only the innermost class counts, which keeps the scan
## simple: a nested class naming the class around it is not looked at.
func _find(source: String) -> Array[String]:
	var class_line: RegEx = RegEx.create_from_string(CLASS_LINE)
	var strings: RegEx = RegEx.create_from_string(STRING_LITERAL)
	var found: Array[String] = []
	var indents: Array[int] = []  # The stack of enclosing classes: their indentation and name.
	var names: Array[String] = []
	var number: int = 0
	for raw: String in source.split("\n"):
		number += 1
		var code: String = strings.sub(raw, '""', true)
		code = code.split("#")[0]
		if code.strip_edges().is_empty():
			continue
		var depth: int = code.length() - code.lstrip("\t").length()
		while not indents.is_empty() and indents[-1] >= depth:
			indents.pop_back()
			names.pop_back()
		var declared: RegExMatch = class_line.search(code)
		if declared != null:
			indents.append(depth)
			names.append(declared.get_string(2))
		elif not names.is_empty():
			var own: String = names[-1]
			var call: RegEx = RegEx.create_from_string("\\b%s\\s*\\.\\s*new\\s*\\(" % own)
			var test: RegEx = RegEx.create_from_string("\\bis\\s+%s\\b" % own)
			if call.search(code) != null or test.search(code) != null:
				found.append("line %d: %s" % [number, raw.strip_edges()])
	return found
