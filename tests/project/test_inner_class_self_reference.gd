extends GdUnitTestSuite
## An inner class that extends a project script and names itself as a runtime value in its own
## body (`Name.new()`, `x is Name`) leaves every loaded script alive when the engine exits, once a
## suite that names that base script has run before the suite that holds the class. Godot then
## prints "ObjectDB instances were leaked at exit" (a warning) and the errors "resources still in
## use at exit" and "Pages in use exist at exit", and verify.sh fails on the errors. Every test
## passes and the exit code stays 0; only the exit lines show it.
##
## P26n2 (PR #41, closed unmerged; commit db02f7f on claude/p26n-cpp-spike) met it: the inner class
## SlowTick of tests/ui/test_perf_probe_worker.gd had a static factory that called its own `new()`.
## The suites ran in the order the file system lists them, so the commit was green locally and red
## on CI, where another suite came first. scripts/run-tests.sh now sorts the suites (P56c), so
## every machine runs the same order, but a new suite still changes the order of the ones after
## it. So the pattern is refused here, whatever the order.
##
## Measured again on main (Godot 4.7.2, P56c) with two scratch suites. One names SimProbe, the
## other holds `class Slow extends SimProbe` (or `extends "res://game/sim/SimProbe.gd"`) with a
## factory that calls `Slow.new()`: in that order 144 ObjectDB instances and 101 resources leak,
## in the other order nothing does. The same class extending RefCounted, Node or Object, or
## extending nothing, did not leak in the first order either, and neither did one extending
## UnitLayer (a Node2D script) after a suite that names UnitLayer. The scan cannot tell which
## script bases leak, so it flags every one that ClassDB does not know. That leaves alone the
## RefCounted `Mirror` of tests/sim/native/test_kernel_abi.gd, which is measured clean. A type
## annotation (`-> Name`, `var t: Name`), a constant (`Name.CONST`) and the same call in the
## enclosing script did not leak on #41 either. Name the class outside its own body: a helper in
## the enclosing script builds the instance.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const ROOTS: Array[String] = ["res://game", "res://tests"]
## Scripts that hold an inner class, one under each root (the second extends a project script, the
## shape the scan looks at): the scan must see them, or it could pass by finding nothing. A rename
## or a move of one fails the test, and the new place goes here.
const KNOWN_SCRIPTS: Array[String] = [
	"res://game/view/UnitLayer.gd",
	"res://tests/input/test_player_controller.gd",
]

## Group 2 is the class name, group 3 its base when it is on this line (`class A extends B:`).
const CLASS_LINE: String = r"^(\t*)class (\w+)\b(?:\s+extends\s+([^\s:]+))?[^:]*:"
## The `extends B` line that opens the body of a class; group 1 is B.
const EXTENDS_LINE: String = r"^\s*extends\s+([^\s:]+)"
const STRING_LITERAL: String = r"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'"

## Source that has the leak: each names the class `A` inside `A`, which extends a script (`B`, a
## path, an inner class of another script).
const MUST_FLAG: Array[String] = [
	"class A:\n\textends B\n\tstatic func make() -> A:\n\t\treturn A.new()\n",
	"class A extends B:\n\tfunc is_mine(other: Object) -> bool:\n\t\treturn other is A\n",
	"class A:\n\textends B\n\tfunc copy() -> A:\n\t\tvar c: A = A.new()\n\t\treturn c\n",
	(
		"class A:\n\textends B\n\n\tclass C:\n\t\textends B\n\t\tfunc make() -> C:\n"
		+ "\t\t\treturn C.new()\n"
	),
	"class A extends B:\n\tstatic func make() -> A:\n\t\treturn A.new()\n",
	'class A:\n\textends "res://b.gd"\n\tstatic func make() -> A:\n\t\treturn A.new()\n',
	"class A extends Outer.B:\n\tstatic func make() -> A:\n\t\treturn A.new()\n",
]

## Source the scan leaves alone. The first three were seen not to leak (a constant, a type
## annotation, the call in the enclosing script); the next four are the same call or test in a
## class that extends RefCounted or Node or nothing, measured not to leak on main (see the
## header); the rest is outside the pattern.
const MUST_PASS: Array[String] = [
	"class A:\n\textends B\n\tconst N: int = 1\n\tstatic func n() -> int:\n\t\treturn A.N\n",
	"class A:\n\textends B\n\tfunc make() -> A:\n\t\tvar t: A = null\n\t\treturn t\n",
	"class A:\n\textends B\n\nfunc make() -> A:\n\treturn A.new()\n",
	"class A:\n\textends RefCounted\n\tstatic func make() -> A:\n\t\treturn A.new()\n",
	"class A extends Node:\n\tfunc is_mine(other: Object) -> bool:\n\t\treturn other is A\n",
	"class A:\n\tstatic func make() -> A:\n\t\treturn A.new()\n",
	"class A:\n\textends B\n\n\tclass C:\n\t\tfunc make() -> C:\n\t\t\treturn C.new()\n",
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
	var files: Dictionary[String, String] = {}
	for root: String in ROOTS:
		for path: String in FileScan.list_files(root, ".gd"):
			files[path] = FileAccess.get_file_as_string(path)
	# Guards against the scan passing because it found nothing.
	assert_array(files.keys()).contains(KNOWN_SCRIPTS)
	var found: Array[String] = _report(files)
	assert_array(found).override_failure_message("\n".join(found)).is_empty()


## The report names the script and the line, and a clean tree has none to name.
func test_a_hit_is_reported_with_its_script_and_line() -> void:
	var files: Dictionary[String, String] = {"res://a.gd": MUST_PASS[0], "res://b.gd": MUST_FLAG[0]}
	assert_array(_report(files)).is_equal(["res://b.gd line 4: return A.new()"])


## "path line N: text" for each hit in the scripts of `files` (path -> source).
func _report(files: Dictionary[String, String]) -> Array[String]:
	var found: Array[String] = []
	for path: String in files:
		for hit: String in _find(files[path]):
			found.append("%s %s" % [path, hit])
	return found


## "line N: text" for each line of `source` that names the inner class it sits in, as a call to
## its `new()` or as the right side of `is`, when that class extends a script. Only the innermost
## class counts, which keeps the scan simple: a nested class naming the class around it is not
## looked at.
func _find(source: String) -> Array[String]:
	var class_line: RegEx = RegEx.create_from_string(CLASS_LINE)
	var extends_line: RegEx = RegEx.create_from_string(EXTENDS_LINE)
	var strings: RegEx = RegEx.create_from_string(STRING_LITERAL)
	var found: Array[String] = []
	# The stack of enclosing classes: their indentation, name and base ("" until it is seen).
	var indents: Array[int] = []
	var names: Array[String] = []
	var bases: Array[String] = []
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
			bases.pop_back()
		var declared: RegExMatch = class_line.search(code)
		if declared != null:
			indents.append(depth)
			names.append(declared.get_string(2))
			bases.append(declared.get_string(3))
		elif not names.is_empty():
			var inherits: RegExMatch = extends_line.search(code)
			if inherits != null:
				bases[-1] = inherits.get_string(1)
			if not _extends_a_script(bases[-1]):
				continue
			var own: String = names[-1]
			var call: RegEx = RegEx.create_from_string("\\b%s\\s*\\.\\s*new\\s*\\(" % own)
			var test: RegEx = RegEx.create_from_string("\\bis\\s+%s\\b" % own)
			if call.search(code) != null or test.search(code) != null:
				found.append("line %d: %s" % [number, raw.strip_edges()])
	return found


## Is `base` (the word after `extends`, "" for none) a script and not a class of the engine? A
## path, an inner class (`Outer.B`) and a `class_name` are not in ClassDB.
func _extends_a_script(base: String) -> bool:
	return not base.is_empty() and not ClassDB.class_exists(StringName(base))
