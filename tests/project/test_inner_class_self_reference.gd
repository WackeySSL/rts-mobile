extends GdUnitTestSuite
## An inner class that extends a project script and uses a class it belongs to as a run-time value
## in its own body (`Name.new()`, `x is Name`, `x as Name`, `Array[Name]`, a bare `Name`) leaves
## every loaded script alive when the engine exits, once a suite that names that base script has
## run before the suite that holds the class. Godot then prints "ObjectDB instances were leaked at
## exit" (a warning) and the errors "resources still in use at exit" and "Pages in use exist at
## exit", and verify.sh fails on the errors. Every test passes and the exit code stays 0; only the
## exit lines show it.
##
## P26n2 (PR #41, closed unmerged; commit db02f7f on claude/p26n-cpp-spike) met it: the inner class
## SlowTick of tests/ui/test_perf_probe_worker.gd had a static factory that called its own `new()`.
## The suites ran in the order the file system lists them, so the commit was green locally and red
## on CI, where another suite came first. scripts/run-tests.sh now sorts the suites (P56c), so
## every machine runs the same order, but a new suite still changes the order of the ones after
## it. So the uses below are refused here, in whatever order the suites run.
##
## Measured on main (Godot 4.7.2, P56c) with two scratch suites run as `-a A -a B` and `-a B -a A`.
## A names SimProbe; B holds `class Slow extends SimProbe` (or extends its path, which leaks too).
## In the first order 144 ObjectDB instances and 101 resources leak, in the other order nothing
## does, when the body of Slow has one of:
## - `Slow.new()`, `Slow.new` (a Callable), `Slow.f()` and `Slow.f` of a static function
## - `x is Slow`, `x is not Slow`, `x as Slow`, `for x: Slow in list`
## - `Array[Slow]` (a variable, a return type), `Dictionary[String, Slow]`
## - a bare `Slow` (the name alone is the use): returned, a dictionary value, a ternary branch, a
##   match pattern, `const M = Slow`
## - the same names for a class that Slow sits in (also two levels up, whatever its own base is) or
##   for the `class_name` of the file, and `class C extends Slow` inside Slow
## - an alias declared outside the body (`const Alias = Slow` in the file, `Alias.new()` in Slow)
## Measured clean: a type annotation of the class (a return type, `var`, `const`, `static var`, a
## parameter with or without a default, a signal parameter, a lambda parameter, `Array[Slow]` as a
## parameter only), a constant or an enum of it (`Slow.N`, `Slow.Kind.A`, `var k: Slow.Kind`),
## `new()` and `get_script().new()` and `load("res://...").new()` without the name, a sibling class
## that names another (both script based), a nested class that extends nothing and names the class
## it sits in, and a class that extends a RefCounted class it sits in. The same uses in a class that
## extends RefCounted, Node or Object, or nothing, do not leak, nor do they in the enclosing script
## (`func make()` at file level).
##
## The scan reads one line at a time and flags a use of the names of the innermost class, the
## classes around it and the file's `class_name`, if that innermost class extends a script. It
## flags every base that ClassDB does not know, since it cannot tell which script bases leak. That
## leaves alone the RefCounted `Mirror` of tests/sim/native/test_kernel_abi.gd. It lets pass what
## is measured clean: a type annotation (parameter types only in a func or signal signature, so a
## dictionary key before `A` is not read as one) and a constant (`Name.` followed by a capital).
## It is stricter than the measurements in one place: `Array[Name]` is refused as a parameter too.
## It does not follow an alias declared outside the body, the one blind spot above.
## Name the class outside its own body: a helper in the enclosing script builds the instance.

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
## The `class_name F` line of a file; group 1 is F.
const CLASS_NAME_LINE: String = r"^class_name\s+(\w+)"
## A line that opens a func or a signal, or holds a lambda: its parameters have types.
const SIGNATURE_LINE: String = r"\b(?:func|signal)\b"
const STRING_LITERAL: String = r"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'"

## What the scan lets pass, each with the class name at %s: a return type, the type of a `var` or
## a `const`, a parameter type, and the access to a constant, an enum or a constant class
## (`Name.N`, `Name.Kind.X`), which the compiler reads. Taken out of a line before the scan looks
## for the name. `for x: Name in` and `Array[Name]` are not among them: they leak.
const RETURN_TYPE: String = r"->\s*%s\b"
const DECLARED_TYPE: String = r"\b(?:var|const)\s+\w+\s*:\s*%s\b"
const PARAMETER_TYPE: String = r"(?:^|[(,])\s*[A-Za-z_]\w*\s*:\s*%s\b"
const CONSTANT_ACCESS: String = r"\b%s\s*\.\s*(?=[A-Z])"
const MENTION: String = r"\b%s\b"

## Source that has the leak: each uses a class it belongs to as a value inside `A`, which extends a
## script (`B`, a path, an inner class of another script). The first three are the shapes the scan
## began with; the others were each measured to leak (see the header).
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
	"class A extends B:\n\tfunc f(o: Object) -> bool:\n\t\treturn o is not A\n",
	"class A extends B:\n\tfunc f(o: Object) -> A:\n\t\treturn o as A\n",
	"class A extends B:\n\tstatic func f() -> Callable:\n\t\treturn A.new\n",
	(
		"class A extends B:\n\tstatic func g() -> int:\n\t\treturn 1\n"
		+ "\tstatic func f() -> int:\n\t\treturn A.g()\n"
	),
	(
		"class A extends B:\n\tstatic func g() -> int:\n\t\treturn 1\n"
		+ "\tstatic func f() -> Callable:\n\t\treturn A.g\n"
	),
	"class A extends B:\n\tfunc f() -> void:\n\t\tvar a: Array[A] = []\n\t\ta.clear()\n",
	"class A extends B:\n\tstatic func f() -> Array[A]:\n\t\treturn []\n",
	"class A extends B:\n\tfunc f() -> void:\n\t\tvar d: Dictionary[String, A] = {}\n",
	"class A extends B:\n\tstatic func f() -> Variant:\n\t\treturn A\n",
	'class A extends B:\n\tstatic func f() -> Dictionary:\n\t\treturn {"k": A}\n',
	"class A extends B:\n\tstatic func f(c: bool) -> Variant:\n\t\treturn A if c else null\n",
	"class A extends B:\n\tfunc f(l: Array) -> void:\n\t\tfor x: A in l:\n\t\t\tprint(x)\n",
	"class A extends B:\n\tstatic func f() -> void:\n\t\tvar x := A.new()\n\t\tprint(x)\n",
	"class A extends B:\n\tstatic func f() -> Object:\n\t\treturn A .new()\n",
	"class A extends B:\n\tstatic func f() -> Object:\n\t\treturn (\n\t\t\tA.new()\n\t\t)\n",
	(
		"class A extends B:\n\tstatic func f(o: Object) -> int:\n\t\tmatch o:\n"
		+ "\t\t\tA:\n\t\t\t\treturn 1\n"
	),
	"class A extends B:\n\tconst Me = A\n",
	# The parameter type is taken out, the default of the same parameter is not.
	"class A extends B:\n\tstatic func f(\n\t\t\ta: A = A.new(),\n\t) -> void:\n\t\tpass\n",
	# Not a signature: `x: A` is a dictionary entry, not a parameter type.
	"class A extends B:\n\tstatic func f(x: Variant) -> Variant:\n\t\treturn {1: 2, x: A}\n",
	(
		"class A extends B:\n\tstatic func f(x: Variant) -> void:\n\t\tprint(\n"
		+ "\t\t\t{1: 2, x: A}\n\t\t)\n"
	),
	(
		"class A extends B:\n\tstatic func f(c: Signal, x: Variant) -> void:\n"
		+ "\t\tc.connect(func(a: A) -> void:\n\t\t\tprint({1: 2, x: A})\n\t\t)\n"
	),
	# A class it sits in (any level, whatever that class extends) and the class_name of the file.
	(
		"class A:\n\textends RefCounted\n\n\tclass C:\n\t\textends B\n\t\tstatic func f() -> Object:\n"
		+ "\t\t\treturn A.new()\n"
	),
	(
		"class A:\n\textends RefCounted\n\n\tclass M:\n\t\textends RefCounted\n\n\t\tclass C:\n"
		+ "\t\t\textends B\n\t\t\tstatic func f() -> Object:\n\t\t\t\treturn A.new()\n"
	),
	(
		"class_name F\nextends Node\n\nclass A:\n\textends B\n"
		+ "\tstatic func f() -> Object:\n\t\treturn F.new()\n"
	),
	# A class that extends a class it sits in, when that class extends a script.
	"class A:\n\textends B\n\n\tclass C:\n\t\textends A\n",
	"class A extends B:\n\tclass C extends A:\n\t\tpass\n",
]

## Source the scan leaves alone. Everything up to the comment fixtures is measured clean (see the
## header); the rest is outside the pattern.
const MUST_PASS: Array[String] = [
	"class A:\n\textends B\n\tconst N: int = 1\n\tstatic func n() -> int:\n\t\treturn A.N\n",
	"class A:\n\textends B\n\tfunc make() -> A:\n\t\tvar t: A = null\n\t\treturn t\n",
	"class A:\n\textends B\n\nfunc make() -> A:\n\treturn A.new()\n",
	"class A:\n\textends RefCounted\n\tstatic func make() -> A:\n\t\treturn A.new()\n",
	"class A extends Node:\n\tfunc is_mine(other: Object) -> bool:\n\t\treturn other is A\n",
	"class A:\n\tstatic func make() -> A:\n\t\treturn A.new()\n",
	"class A:\n\textends B\n\n\tclass C:\n\t\tfunc make() -> C:\n\t\t\treturn C.new()\n",
	"class A extends B:\n\tenum Kind { X, Y }\n\tstatic func f() -> int:\n\t\treturn A.Kind.X\n",
	(
		"class A extends B:\n\tenum Kind { X, Y }\n\tfunc f() -> void:\n"
		+ "\t\tvar k: A.Kind = A.Kind.X\n\t\tprint(k)\n"
	),
	(
		"class A extends B:\n\tfunc f(a: A, b: A = null) -> A:\n"
		+ "\t\tvar t: A = a\n\t\treturn t if t else b\n"
	),
	"class A extends B:\n\tvar m: A = null\n\tconst K: A = null\n\tstatic var cache: A = null\n",
	"class A extends B:\n\tsignal changed(who: A)\n",
	"class A extends B:\n\tfunc f() -> Callable:\n\t\treturn func(a: A) -> A: return a\n",
	"class A extends B:\n\tfunc f(a: Array[Variant]) -> A:\n\t\treturn null\n",
	"class A extends B:\n\tstatic func f(\n\t\t\ta: A,\n\t\t\tb: A = null,\n\t) -> A:\n\t\treturn a\n",
	"class A extends B:\n\tfunc clone() -> Object:\n\t\treturn (get_script() as GDScript).new()\n",
	(
		"class A:\n\textends B\n\tstatic func f() -> Object:\n\t\treturn S.new()\n"
		+ "\n\nclass S:\n\textends B\n"
	),
	"class A:\n\textends B\n\n\tclass C:\n\t\tstatic func make() -> A:\n\t\t\treturn A.new()\n",
	"class A:\n\textends RefCounted\n\n\tclass C:\n\t\textends A\n",
	"class_name F\nextends Node\n\nclass A:\n\textends B\n\tconst N: int = F.N\n",
	"class A:\n\textends B\n\tfunc other() -> Object:\n\t\treturn C.new()\n",
	'class A:\n\textends B\n\t# A.new() is only a comment\n\tconst TEXT: String = "A.new()"\n',
	"var made: Object = A.new()\n",
]


func test_a_class_that_uses_itself_in_its_own_body_is_flagged() -> void:
	for source: String in MUST_FLAG:
		assert_array(_find(source)).override_failure_message(source).is_not_empty()


func test_code_that_does_not_need_the_leak_is_not_flagged() -> void:
	for source: String in MUST_PASS:
		assert_array(_find(source)).override_failure_message(source).is_empty()


func test_no_inner_class_in_game_or_tests_uses_itself_in_its_own_body() -> void:
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


## "line N: text" for each line of `source` where an inner class that extends a script uses a class
## it belongs to as a value (see the header), or extends a class it sits in whose base is a script.
func _find(source: String) -> Array[String]:
	var class_line: RegEx = RegEx.create_from_string(CLASS_LINE)
	var extends_line: RegEx = RegEx.create_from_string(EXTENDS_LINE)
	var class_name_line: RegEx = RegEx.create_from_string(CLASS_NAME_LINE)
	var signature_line: RegEx = RegEx.create_from_string(SIGNATURE_LINE)
	var strings: RegEx = RegEx.create_from_string(STRING_LITERAL)
	var found: Array[String] = []
	var file_class: String = ""
	# The stack of enclosing classes: their indentation, name and base ("" until it is seen).
	var indents: Array[int] = []
	var names: Array[String] = []
	var bases: Array[String] = []
	# Unclosed "(" of the func or signal signature that is being read.
	var open: int = 0
	var number: int = 0
	for raw: String in source.split("\n"):
		number += 1
		var code: String = strings.sub(raw, '""', true)
		code = code.split("#")[0]
		if code.strip_edges().is_empty():
			continue
		var signature: RegExMatch = signature_line.search(code)
		var in_signature: bool = signature != null or open > 0
		if in_signature:
			# Count from the `func` or `signal` on, not from a call that holds a lambda.
			var tail: String = code if signature == null else code.substr(signature.get_start())
			open = maxi(0, open + tail.count("(") - tail.count(")"))
		var depth: int = code.length() - code.lstrip("\t").length()
		while not indents.is_empty() and indents[-1] >= depth:
			indents.pop_back()
			names.pop_back()
			bases.pop_back()
		var hit: String = "line %d: %s" % [number, raw.strip_edges()]
		var named: RegExMatch = class_name_line.search(code)
		var declared: RegExMatch = class_line.search(code)
		var inherits: RegExMatch = extends_line.search(code)
		if named != null:
			file_class = named.get_string(1)
		elif declared != null:
			indents.append(depth)
			names.append(declared.get_string(2))
			bases.append(declared.get_string(3))
			if _extends_enclosing(names, bases):
				found.append(hit)
		elif names.is_empty():
			continue
		elif inherits != null:
			bases[-1] = inherits.get_string(1)
			if _extends_enclosing(names, bases):
				found.append(hit)
		elif _extends_a_script(bases[-1]):
			var around: Array[String] = []
			around.assign(names)
			if not file_class.is_empty():
				around.append(file_class)
			if _uses_as_value(code, around, in_signature):
				found.append(hit)
	return found


## Is `base` (the word after `extends`, "" for none) a script and not a class of the engine? A
## path, an inner class (`Outer.B`) and a `class_name` are not in ClassDB.
func _extends_a_script(base: String) -> bool:
	return not base.is_empty() and not ClassDB.class_exists(StringName(base))


## Does the innermost class of the stack extend a class it sits in, one that extends a script?
func _extends_enclosing(names: Array[String], bases: Array[String]) -> bool:
	var at: int = names.find(bases[-1])
	return at >= 0 and _extends_a_script(bases[at])


## Does `code` (a line without strings and comment) use one of `classes` as a value: any mention
## of the name that is not a type annotation or a constant? `in_signature` allows parameter types.
func _uses_as_value(code: String, classes: Array[String], in_signature: bool) -> bool:
	var allowed: Array[String] = [RETURN_TYPE, DECLARED_TYPE, CONSTANT_ACCESS]
	if in_signature:
		allowed.append(PARAMETER_TYPE)
	for own: String in classes:
		if not code.contains(own):
			continue
		var rest: String = code
		for pattern: String in allowed:
			rest = RegEx.create_from_string(pattern % own).sub(rest, "", true)
		if RegEx.create_from_string(MENTION % own).search(rest) != null:
			return true
	return false
