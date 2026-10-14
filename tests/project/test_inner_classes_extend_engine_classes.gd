extends GdUnitTestSuite
## An inner class in game/ or tests/ extends an engine class that ClassDB knows, or nothing. A class
## with a script base goes into a file of its own (the file may `extends` a script, only inner
## classes count). A script base is a `class_name` script such as SimProbe or UnitLayer, an
## `extends "res://..."` path, another inner class, or a dotted name `Outer.Inner`.
##
## The leak. Once a suite that names a script has run, an inner class that extends that script and
## names a class it belongs to leaves every loaded script alive when the engine exits. Godot then
## prints "ObjectDB instances were leaked at exit" (a warning) and the errors "resources still in
## use at exit" and "Pages in use exist at exit", and verify.sh fails on the errors. Every test
## passes and the exit code stays 0; only the exit lines show it, and only in one suite order.
##
## P26n2 (PR #41, closed unmerged; commit db02f7f on claude/p26n-cpp-spike) met it: the inner class
## SlowTick of tests/ui/test_perf_probe_worker.gd had a static factory that called its own `new()`.
## The suites ran in the order the file system lists them, so the commit was green locally and red
## on CI, where another suite came first. scripts/run-tests.sh now sorts the suites (P56c), so
## every machine runs the same order, but a new suite still moves the ones after it.
##
## Measured with Godot 4.7.2 on the scripts of main (P56c), with two scratch suites run as
## `-a A -a B` and as `-a B -a A`. A names SimProbe; B holds `class Slow extends SimProbe` (the
## base on the class line or on the first line of the body). In the first order 144 ObjectDB
## instances and 101 resources leak, in the other nothing does, when the body of Slow has one of:
## - review round 1: the name of Slow, or of a class it sits in, used as a value: `Slow.new()`,
##   `Slow.f()`, `x is Slow`, `x as Slow`, `Array[Slow]`, a bare `Slow`, `const M = Slow`,
##   `Slow.C.new()`; also with Slow two levels down, inside a class that extends RefCounted
## - review round 2: `static var inst: Slow = null` and a static func that assigns `inst`;
##   `const Base = preload("res://game/sim/SimProbe.gd")` reached as `Slow.Base.new()`;
##   `class C extends Outer.Slow` inside Slow (a dotted path to an enclosing class); `@abstract`
##   before `class` (on its line or the line above) and `o is Slow`; `const Own =
##   preload(<the path of the file itself>)` with `Own.Slow.new()`
## Every one of them needs a class with a script base. The same shapes with RefCounted as the base
## did not leak. Nor did the round 1 uses together (`Slow.new()`, a bare `Slow`, `Array[Slow]`, a
## static var read as `Slow.count`, `is` and `as`) with Node, Object, Logger, CanvasGroup,
## HBoxContainer, no base and SimKernels (a GDExtension class) as the base.
##
## Two review rounds of scanning the body for such uses each found new shapes, so the rule is about
## the base alone. It is total for every shape measured, because each needs a script base. ClassDB
## decides: a quoted path (blanked to `""` with the other strings), a dotted name and the name of
## an inner class or of a `class_name` script are not in it. The scan reads `class` lines at any
## depth, with annotations before `class` on the same line, the base on the class line (`class A
## extends B:`, `class A: extends B`) or as the first statement of the body (`extends B`, after
## blank lines and comments), and a `\` that continues the class line (a `\` that ends a comment
## continues nothing). Godot 4.7.2 parses all of those, and refuses an `extends` that follows a
## `var` of the body.
##
## It is stricter than the leak in two places, both measured clean (STRICTER): a script base with a
## body that names no class it sits in, and an inner class that extends an inner class that ends
## in RefCounted. It moved one class: TwoTypeLayer of tests/input/test_player_controller.gd, which
## extends UnitLayer and was the only inner class on main with a script base, is now
## tests/input/support/two_type_layer.gd.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const ROOTS: Array[String] = ["res://game", "res://tests"]
## Scripts that hold an inner class on main, each with the base of one of its classes (all of them
## write `class X:` and `extends Y` on the next line). The scan must read that class in each, or it
## could pass by finding nothing. A rename or a move of one fails the test, and the new place
## goes here.
const KNOWN_SCRIPTS: Dictionary[String, String] = {
	"res://game/view/UnitLayer.gd": "Sprite2D",  # Ring, a Node2D until P40 made it the ring sprite.
	"res://game/view/MoveMarkerLayer.gd": "CanvasGroup",
	"res://game/ui/SelectionPanel.gd": "HBoxContainer",
	"res://tests/scenes/test_controls_flow.gd": "Logger",
	"res://tests/sim/native/test_kernel_abi.gd": "RefCounted",
	"res://tests/input/test_touch_input.gd": "Node",
}
const RULE: String = (
	"An inner class may extend only an engine class (one ClassDB knows) or nothing. "
	+ "Move a class with a script base into a file of its own:\n"
)

## What the scan takes out before it reads a line, read from the left so that a comment hides the
## quote in it and a string hides the "#" in it: a triple-quoted string, a string (Godot accepts a
## line break inside one), a comment. A string becomes `""` and keeps its line breaks, a comment
## goes.
const TOKEN: String = (
	r'(?s)"""(?:[^\\]|\\.)*?"""|'
	+ r"'''(?:[^\\]|\\.)*?'''|"
	+ r'"(?:[^"\\]|\\.)*"|'
	+ r"'(?:[^'\\]|\\.)*'|"
	+ r"#[^\n]*"
)
## A `class` line with annotations before `class` (`@abstract`, `@warning_ignore("...")`). Group 1
## is the base after the name (`class A extends B:`), group 2 the base after the colon (`class A:
## extends B`). A base is a word, a path in quotes or a dotted name; it ends at a space, ":" or ";".
const CLASS_LINE: String = (
	r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*class\s+\w+\s*(?:extends\s+([^\s:;]+)\s*)?:\s*"
	+ r"(?:extends\s+([^\s:;]+))?"
)
## The `extends B` statement that opens the body of a class; group 1 is B.
const EXTENDS_LINE: String = r"^\s*extends\s+([^\s:;]+)"

## A class with a script base, in each way to write it. Each source has exactly one such class.
const MUST_FLAG: Array[String] = [
	# A script base, in both forms of the declaration.
	"class A extends B:\n\tpass\n",
	"class A:\n\textends B\n",
	"class A extends SimProbe:\n\tpass\n",
	"class A:\n\textends UnitLayer\n",
	# A path, in either quote and in both forms.
	'class A extends "res://b.gd":\n\tpass\n',
	'class A:\n\textends "res://b.gd"\n',
	"class A extends 'res://b.gd':\n\tpass\n",
	"class A:\n\textends 'res://b.gd'\n",
	# A dotted name.
	"class A extends Outer.B:\n\tpass\n",
	"class A:\n\textends Outer.B\n",
	# An inner class, a sibling or an enclosing one, also when it ends in an engine class.
	"class A:\n\textends RefCounted\n\n\nclass C:\n\textends A\n",
	"class A extends RefCounted:\n\tpass\n\n\nclass C extends A:\n\tpass\n",
	"class A:\n\textends RefCounted\n\n\tclass C:\n\t\textends A\n",
	"class A extends RefCounted:\n\tclass C extends A:\n\t\tpass\n",
	(
		"class A extends RefCounted:\n\tclass M extends RefCounted:\n"
		+ "\t\tclass C extends A.M:\n\t\t\tpass\n"
	),
	# @abstract and other annotations with a script base, on the line of the class or above it.
	"@abstract class A extends B:\n\tpass\n",
	"@abstract class A:\n\textends B\n",
	"@abstract\nclass A extends B:\n\tpass\n",
	"@abstract\nclass A:\n\textends B\n",
	'@warning_ignore("unused_signal") class A extends B:\n\tpass\n',
	'@abstract @warning_ignore("unused_signal") class A:\n\textends B\n',
	'@warning_ignore("unused_signal", "unused_variable")\nclass A extends B:\n\tpass\n',
	# A script base at depth 2 and deeper, in both forms.
	"class A:\n\textends RefCounted\n\n\tclass C:\n\t\textends B\n",
	"class A extends RefCounted:\n\tclass C extends B:\n\t\tpass\n",
	(
		"class A:\n\textends RefCounted\n\n\tclass M:\n\t\textends RefCounted\n\n"
		+ "\t\tclass C:\n\t\t\textends B\n"
	),
	"class A extends Node:\n\tclass M extends Node:\n\t\tclass C extends B:\n\t\t\tpass\n",
	"@abstract class A:\n\textends RefCounted\n\n\t@abstract class C:\n\t\textends B\n",
	# Other ways to write the declaration.
	"class A: extends B\n",
	"class A extends B: pass\n",
	"class A :\n\textends B\n",
	"class A:\n\t# a note\n\n\t## docs\n\n\textends B\n",
	"class A \\\n\textends B:\n\tpass\n",
	"class A:\n    extends B\n",
	# After a class that is fine, and in a file that extends an engine class or a script itself.
	"class A:\n\tpass\n\n\nclass C:\n\textends B\n",
	"class A:\n\textends RefCounted\n\n\nclass C:\n\textends B\n",
	"extends Node\n\nclass A:\n\textends B\n",
	"class_name F\nextends Node\n\nclass A extends B:\n\tpass\n",
	"extends B\n\nclass A:\n\textends B\n",
	# After strings and comments that look like classes.
	(
		'# class X extends RefCounted:\nconst S: String = "class Y extends RefCounted:"\n'
		+ "class A:\n\textends B\n"
	),
	'const S: String = """\nclass X extends RefCounted:\n"""\n\n\nclass A:\n\textends B\n',
	# After a comment with a quote in it, a "#" in a string and a string with a line break in it.
	"# it's here\nclass A:\n\textends B\n# don't\n",
	"# a \\\nclass A extends B:\n\tpass\n",
	'var s: String = "#"\nclass A extends B:\n\tpass\n',
	'const S: String = "a\nb"\nclass A extends B:\n\tpass\n',
	# Lines that end in CR LF, also in a class line that continues.
	"class A:\r\n\textends B\r\n",
	"class A \\\r\n\textends B:\r\n\tpass\r\n",
	# A name that ClassDB does not know, whatever it looks like.
	"class A extends Nod:\n\tpass\n",
	"class A extends node:\n\tpass\n",
]

## The shapes that leaked (see the header), each with the number of its classes that have a script
## base: the rule refuses all of them for that base, whatever the body does.
const LEAK_NEW: String = (
	"class Slow:\n\textends B\n\n" + "\tstatic func make() -> Variant:\n\t\treturn Slow.new()\n"
)
const LEAK_STATIC_VAR: String = (
	"class Slow extends B:\n\tstatic var inst: Slow = null\n\n"
	+ "\tstatic func f() -> void:\n\t\tinst = null\n"
)
const LEAK_CONST_BASE: String = (
	'class Slow extends B:\n\tconst Base = preload("res://b.gd")\n\n'
	+ "\tstatic func f() -> Object:\n\t\treturn Slow.Base.new()\n"
)
const LEAK_DOTTED: String = (
	"class Outer extends RefCounted:\n\tclass Slow extends B:\n"
	+ "\t\tclass C extends Outer.Slow:\n\t\t\tpass\n"
)
const LEAK_ABSTRACT: String = (
	"@abstract class Slow extends B:\n"
	+ "\tstatic func f(o: Object) -> bool:\n\t\treturn o is Slow\n"
)
const LEAK_PRELOAD_OWN: String = (
	'class Slow extends B:\n\tconst Own = preload("res://a.gd")\n\n'
	+ "\tstatic func f() -> Object:\n\t\treturn Own.Slow.new()\n"
)
const LEAKED: Dictionary[String, int] = {
	LEAK_NEW: 1,
	LEAK_STATIC_VAR: 1,
	LEAK_CONST_BASE: 1,
	LEAK_DOTTED: 2,
	LEAK_ABSTRACT: 1,
	LEAK_PRELOAD_OWN: 1,
}

## Source the scan leaves alone: an engine base or none, in both forms, at any depth, with the
## uses that leak under a script base, and text that only looks like a class.
const MUST_PASS: Array[String] = [
	# Engine bases, in both forms of the declaration.
	"class A extends RefCounted:\n\tpass\n",
	"class A:\n\textends RefCounted\n",
	"class A extends Node:\n\tpass\n",
	"class A:\n\textends Node\n",
	"class A extends Logger:\n\tpass\n",
	"class A:\n\textends Logger\n",
	"class A extends CanvasGroup:\n\tpass\n",
	"class A:\n\textends CanvasGroup\n",
	"class A extends HBoxContainer:\n\tpass\n",
	"class A:\n\textends HBoxContainer\n",
	"class A extends Object:\n\tpass\n",
	"class A:\n\textends Object\n",
	"class A: extends RefCounted\n",
	"class A extends RefCounted: pass\n",
	"class A extends RefCounted :\n\tpass\n",
	"class A \\\n\textends RefCounted:\n\tpass\n",
	"class A:\n\t# a note\n\n\t## docs\n\n\textends Node\n",
	"class A:\n    extends Node\n",
	# No base.
	"class A:\n\tvar x: int = 0\n",
	"class A:\n\tpass\n",
	"class A: pass\n",
	"@abstract class A:\n\tpass\n",
	"@abstract\nclass A:\n\tpass\n",
	# An engine base with annotations before class, and at depth.
	"@abstract class A extends RefCounted:\n\tpass\n",
	"@abstract class A:\n\textends RefCounted\n",
	"@abstract\nclass A extends RefCounted:\n\tpass\n",
	'@warning_ignore("unused_signal") class A extends Node:\n\tpass\n',
	"class A:\n\textends RefCounted\n\n\tclass C:\n\t\textends Node\n",
	"class A extends RefCounted:\n\tclass C extends Node:\n\t\tpass\n",
	(
		"class A:\n\textends RefCounted\n\n\tclass M:\n\t\textends Node\n\n"
		+ "\t\tclass C:\n\t\t\textends Logger\n"
	),
	"class A:\n\textends RefCounted\n\n\tclass C:\n\t\tpass\n",
	# A file whose own extends is a script or a path, with inner classes that extend the engine.
	"extends B\n\nclass A:\n\textends RefCounted\n",
	"class_name F extends B\n\nclass A extends RefCounted:\n\tpass\n",
	"class_name F\nextends SimProbe\n\nclass A:\n\textends Node\n",
	'extends "res://b.gd"\n\nclass A:\n\textends RefCounted\n',
	"extends B\n\nclass A extends Node:\n\tpass\n",
	# The uses that leak under a script base, in classes that have an engine base or none.
	"class A:\n\textends RefCounted\n\tstatic func make() -> A:\n\t\treturn A.new()\n",
	"class A extends Node:\n\tfunc is_mine(other: Object) -> bool:\n\t\treturn other is A\n",
	"class A:\n\tstatic func make() -> A:\n\t\treturn A.new()\n",
	(
		"class A:\n\textends RefCounted\n\tstatic var inst: A = null\n\n"
		+ "\tstatic func f() -> Variant:\n\t\treturn [A, A.inst]\n"
	),
	(
		'class A extends RefCounted:\n\tconst Base = preload("res://b.gd")\n\n'
		+ "\tstatic func f() -> Object:\n\t\treturn A.Base.new()\n"
	),
	(
		"class A extends Object:\n\tclass C extends RefCounted:\n"
		+ "\t\tstatic func f() -> Variant:\n\t\t\treturn A\n"
	),
	"@abstract class A extends RefCounted:\n\tstatic func f(o: Object) -> bool:\n\t\treturn o is A\n",
	# Comments and strings that hold "class X extends Y".
	"# class A extends B:\n",
	"## class A:\n## \textends B\n",
	'const S: String = "class A extends B:"\n',
	"const S: String = 'class A extends B:'\n",
	'const S: String = "class A:\\n\\textends B"\n',
	'const S: String = """\nclass A extends B:\n\nclass C:\n\textends B\n"""\n',
	# A string with an escaped quote, then a line that looks like a class.
	'const S: String = "a \\" b\nclass A extends B:\nc"\n',
	"const S: String = 'a \\' b\nclass A extends B:\nc'\n",
	# A triple-quoted string with a quote of its own in it.
	'const S: String = """say "hi\nclass A extends B:\n"""\n',
	"const S: String = '''say 'hi\nclass A extends B:\n'''\n",
	# Godot accepts a line break inside a string in single or double quotes.
	'const S: String = "a\nclass A extends B:\nb"\n',
	"const S: String = 'a\nclass A:\n\textends B\nb'\n",
	"const S: String = '''\nclass A:\n\textends B\n'''\n",
	"class A extends RefCounted:  # class C extends B:\n\tpass\n",
	"class A:  # extends B\n\textends RefCounted\n",
	"class A:\n\t# extends B\n\textends RefCounted\n",
	'class A:\n\tvar s: String = """\n\textends B\n"""\n',
	'class A:\n\textends RefCounted\n\tconst S: String = "class C extends B:"\n',
	'var s: String = "#"\nclass A extends Node:  # "class C extends B:"\n\tpass\n',
	# Godot refuses an `extends` after another member ("Unexpected extends in class body"): no base.
	"class A:\n\tvar x: int = 0\n\textends B\n",
	# Not a declaration: `class_name`, a name that holds "class", a lone extends line.
	"class_name F extends B\n",
	"class_name F\nextends B\n",
	"const subclass: int = 1\nvar class_a: int = 2\n",
	"extends B\n",
	"",
]

## Source that is measured clean and that the scan refuses all the same (see the header): a script
## base whose body names no class it sits in, and an inner class extending an inner class that
## ends in RefCounted. None of it is in game/ or tests/.
const STRICTER: Array[String] = [
	"class A:\n\textends B\n\n\tvar delay: int = 0\n\n\tfunc f(a: A) -> A:\n\t\treturn a\n",
	(
		"class Outer extends RefCounted:\n\tclass Slow extends RefCounted:\n"
		+ "\t\tclass C extends Outer.Slow:\n\t\t\tpass\n"
	),
]

## Names the rule lets pass (the bases above) and names it refuses; the fixtures rely on them.
const ENGINE_BASES: Array[String] = [
	"RefCounted", "Node", "Object", "Logger", "CanvasGroup", "HBoxContainer", "Node2D"
]
const SCRIPT_BASES: Array[String] = ["SimProbe", "UnitLayer", "A", "Outer.B", '""', "Nod", "node"]


func test_a_class_with_a_script_base_is_flagged() -> void:
	for source: String in MUST_FLAG:
		assert_array(_find(source)).override_failure_message(source).has_size(1)


func test_the_shapes_that_leaked_are_flagged_for_their_base() -> void:
	for source: String in LEAKED:
		assert_array(_find(source)).override_failure_message(source).has_size(LEAKED[source])


func test_a_class_with_an_engine_base_or_none_is_not_flagged() -> void:
	for source: String in MUST_PASS:
		assert_array(_find(source)).override_failure_message(source).is_empty()


func test_the_rule_is_stricter_than_the_leak_in_two_places() -> void:
	for source: String in STRICTER:
		assert_array(_find(source)).override_failure_message(source).is_not_empty()


func test_classdb_knows_the_engine_bases_of_the_fixtures_and_no_script() -> void:
	for base: String in ENGINE_BASES:
		assert_bool(ClassDB.class_exists(StringName(base))).override_failure_message(base).is_true()
	for base: String in SCRIPT_BASES:
		(
			assert_bool(ClassDB.class_exists(StringName(base)))
			. override_failure_message(base)
			. is_false()
		)


func test_no_inner_class_in_game_or_tests_has_a_script_base() -> void:
	var files: Dictionary[String, String] = {}
	for root: String in ROOTS:
		for path: String in FileScan.list_files(root, ".gd"):
			files[path] = FileAccess.get_file_as_string(path)
	# Guards against the scan passing because it found nothing.
	assert_array(files.keys()).contains(KNOWN_SCRIPTS.keys())
	var found: Array[String] = _report(files)
	assert_array(found).override_failure_message(RULE + "\n".join(found)).is_empty()


func test_the_scan_reads_the_inner_classes_of_the_known_scripts() -> void:
	for path: String in KNOWN_SCRIPTS:
		var bases: Dictionary[int, String] = _bases(FileAccess.get_file_as_string(path))
		assert_array(bases.values()).override_failure_message(path).contains([KNOWN_SCRIPTS[path]])


## The report names the script and the line that names the base: the class line, or the `extends`
## line of a class that has one on its own.
func test_a_hit_is_reported_with_its_script_and_line() -> void:
	var files: Dictionary[String, String] = {
		"res://a.gd": "class A:\n\textends RefCounted\n",
		"res://b.gd": "class A:\n\textends RefCounted\n\n\nclass C:\n\textends A\n",
		"res://c.gd": "extends Node\n\nclass A extends B:\n\tpass\n",
		"res://d.gd":
		"class A:\n\textends RefCounted\n\n\tclass C extends 'res://x.gd':\n\t\tpass\n",
	}
	(
		assert_array(_report(files))
		. is_equal(
			[
				"res://b.gd line 6: extends A",
				"res://c.gd line 3: class A extends B:",
				"res://d.gd line 4: class C extends 'res://x.gd':",
			]
		)
	)


func test_a_class_line_that_continues_is_reported_on_its_first_line() -> void:
	assert_array(_find("class A \\\n\textends B:\n\tpass\n")).is_equal(["line 1: class A \\"])


## "path line N: text" for each hit in the scripts of `files` (path -> source).
func _report(files: Dictionary[String, String]) -> Array[String]:
	var found: Array[String] = []
	for path: String in files:
		for hit: String in _find(files[path]):
			found.append("%s %s" % [path, hit])
	return found


## "line N: text" for each inner class of `source` whose base is no class of the engine.
func _find(source: String) -> Array[String]:
	var raws: PackedStringArray = source.split("\n")
	var bases: Dictionary[int, String] = _bases(source)
	var found: Array[String] = []
	for line: int in bases:
		if not ClassDB.class_exists(StringName(bases[line])):
			found.append("line %d: %s" % [line, raws[line - 1].strip_edges()])
	return found


## Line number (from 1) -> the base that line names, for each inner class of `source` that has one:
## on the `class` line, or on the first statement of the body when that is an `extends`.
func _bases(source: String) -> Dictionary[int, String]:
	var class_line: RegEx = RegEx.create_from_string(CLASS_LINE)
	var extends_line: RegEx = RegEx.create_from_string(EXTENDS_LINE)
	var lines: PackedStringArray = _code_lines(source)
	var bases: Dictionary[int, String] = {}
	# True when the last line opened a class that has no base yet: its body may begin with `extends`.
	var waiting: bool = false
	for at: int in lines.size():
		var code: String = lines[at]
		if code.strip_edges().is_empty():
			continue
		var inherits: RegExMatch = extends_line.search(code)
		if waiting and inherits != null:
			bases[at + 1] = inherits.get_string(1)
		waiting = false
		var declared: RegExMatch = class_line.search(code)
		if declared == null:
			continue
		var base: String = declared.get_string(1) + declared.get_string(2)
		if base.is_empty():
			waiting = true
		else:
			bases[at + 1] = base
	return bases


## The lines of `source` as code: each string literal `""`, each comment gone, the lines of a
## statement that continues with "\" joined into the first of them (the others are empty), so the
## line numbers stay.
func _code_lines(source: String) -> PackedStringArray:
	var parts: PackedStringArray = PackedStringArray()
	var from: int = 0
	for token: RegExMatch in RegEx.create_from_string(TOKEN).search_all(source):
		parts.append(source.substr(from, token.get_start() - from))
		if not token.get_string().begins_with("#"):
			parts.append('""' + "\n".repeat(token.get_string().count("\n")))
		from = token.get_end()
	parts.append(source.substr(from))
	var lines: PackedStringArray = "".join(parts).replace("\r", "").split("\n")
	# The line that a run of continuations is joined into, -1 when none is open.
	var head: int = -1
	for at: int in lines.size():
		var target: int = head if head >= 0 else at
		if target != at:
			lines[target] = lines[target].trim_suffix("\\") + " " + lines[at].strip_edges()
			lines[at] = ""
		head = target if lines[target].ends_with("\\") else -1
	return lines
