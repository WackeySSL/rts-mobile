extends GdUnitTestSuite
## Purity guard for game/sim (CLAUDE.md architecture rules 1 to 3): no Node, no engine time or
## input, no floats, no randomness except through a DetRandom passed in, no autoload.
##
## Four layers guard game/sim:
## - Name and literal patterns on each line, after string literals and comments are stripped.
## - An identifier scan that asks ClassDB whether a capitalised word is an engine Node class or
##   a *Server singleton. Names alone cannot list the 200 Node classes.
## - A base type check: no sim script may extend a Node, directly or through a user base class.
## - An allocation check by indentation (ADR 0007 section 1): no array or dictionary literal,
##   Array or Dictionary variable without a value, Packed*Array(...), duplicate() or slice()
##   inside a for or while body or a while condition, unless the line ends with `# alloc-ok`.
## game/ai is scanned for randomness only (rule 3).
##
## The scans over game/sim and game/ai are vacuous until those folders hold code. The fixture
## tests are not: they prove each pattern catches what it must and leaves legal integer code
## alone.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const SIM_DIR: String = "res://game/sim"
const AI_DIR: String = "res://game/ai"
## Read as text and never loaded, so no scan of game/ and no import step meets it.
const LOOP_FIXTURE: String = "res://tests/project/fixtures/sim_loop_allocations.txt"
const ALLOC_OK: String = "# alloc-ok"

const STRING_LITERAL: String = r"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'"
## Array.shuffle() and pick_random() use the global generator. They take no argument, which
## tells them apart from a DetRandom method that must receive the array.
const RAND_NAMES: String = (
	r"\b(RandomNumberGenerator"
	+ r"|rand(i|f|i_range|f_range|fn|_from_seed|omize))\b"
	+ r"|\.(shuffle|pick_random)\s*\(\s*\)"
)
const BANNED_NAMES: String = (
	r"\b(Node[A-Za-z0-9]*|SceneTree|Input|OS|Time|Engine"
	+ r"|float|sin|cos|tan|sqrt|atan2?|pow|PI|TAU|INF|NAN|Vector[234]|Rect2|Transform[23]D"
	+ r"|get_tree|DetRng|CommandQueue|_process|_physics_process"
	+ r"|get_(physics_)?process_delta_time"
	+ r"|Packed(Float32|Float64|Vector[234]|Color)Array|Color|Basis|Quaternion|Plane|AABB"
	+ r"|Projection|Performance"
	+ r"|lerpf?|inverse_lerp|remap|floorf|ceilf|roundf|absf|clampf|signf|snappedf|wrapf"
	+ r"|fmod|fposmod|asin|acos|deg_to_rad|rad_to_deg|to_float|is_equal_approx"
	+ r"|maxf|minf|move_toward|smoothstep|lerp_angle|angle_difference|rotate_toward|pingpong"
	+ r"|sinh|cosh|tanh|is_zero_approx|cubic_interpolate\w*|bezier_\w+|distance_to"
	+ r"|get_node|queue_free|create_tween)\b"
)
## Only as calls: `var exp: int` (veterancy) and `var log: Array` (command log) are legal
## names in the sim. Vector2i.length() and aspect() return float, and JSON parses every
## number as float. hash() is engine defined (ADR 0007 section 1); `\b` keeps state_hash(),
## defs_hash() and hash_hex() legal.
const BANNED_CALLS: String = r"\b(exp|log|ease|aspect|length|hash)\s*\(|\bJSON\.parse"
## What to do about a banned call, appended to its report line.
const HINTS: Dictionary[String, String] = {
	r"\blength\s*\(": "use len() for a String size; Vector2i.length() is a float",
	r"\bhash\s*\(": "hash() is engine defined; use World.state_hash() or an integer mix",
}
## A `[` opens an array literal after an operator, an opening bracket, a comma or a keyword,
## and from the start of a line. After a name, `)`, `]` or a string it indexes. A typed Array or
## Dictionary variable without a value is a new object on every pass too.
const ALLOC_NAMES: String = (
	r"(?:^|[=(,:+\-*/%&|^<>!~\[])\s*\["
	+ r"|\b(?:return|in|and|or|not|if|else|elif|while|match)\s*\["
	+ r"|\{|\bPacked(?:Int32|Int64|Byte)Array\s*\(|\.(?:duplicate(?:_deep)?|slice)\s*\("
	+ r"|^\s*var\s+\w+\s*:\s*(?:Array|Dictionary)\b[^=]*$"
)
const LOOP_HEADER: String = r"^\s*(?:for|while)\b"
const FLOAT_LITERAL: String = (
	r"(?<![A-Za-z0-9_.])[0-9][0-9_]*\.[0-9]|(?<![A-Za-z0-9_])\.[0-9]"
	+ r"|(?<![A-Za-z0-9_.])[0-9][0-9_]*\.(?![0-9A-Za-z_])|\b[0-9]+[eE][+-]?[0-9]"
)
const CAPITALISED_IDENTIFIER: String = r"\b[A-Z][A-Za-z0-9_]*\b"

const MUST_MATCH: Array[String] = [
	"randi_range(0, 3)",
	"1.5 * speed",
	"sqrt(d2)",
	"RandomNumberGenerator.new()",
	"atan2(y, x)",
	"TAU",
	"var r: Rect2",
	"var m: Transform2D",
	"var v: Vector2 = p",
	"func _process(delta: int)",
	"var f: float",
	"var n: Node2D",
	"1e3",
	".5",
	"2.",
	"sin(a)",
	"var r: DetRng",
	"get_physics_process_delta_time()",
	"OS.get_ticks_msec()",
	'NodePath("a")',
	# Node classes by their own names, found through ClassDB.
	"extends CharacterBody2D",
	"extends Sprite2D",
	"var t: Timer",
	"var a: Area2D",
	'var n = get_node("A")',
	"queue_free()",
	"var tween := create_tween()",
	# Engine servers and singletons.
	"RenderingServer.canvas_item_create()",
	"DisplayServer.screen_get_size()",
	"PhysicsServer2D.body_create()",
	"NavigationServer2D.get_maps()",
	"Performance.get_monitor(0)",
	# Float containers and types.
	"var p: PackedVector2Array",
	"var p: PackedVector3Array",
	"var p: PackedVector4Array",
	"var p: PackedFloat32Array",
	"var p: PackedFloat64Array",
	"var p: PackedColorArray",
	"var c: Color",
	"var b: Basis",
	"var q: Quaternion",
	"var pl: Plane",
	"var box: AABB",
	"var pr: Projection",
	# Float builtins, also inside int().
	"int(lerpf(a, b, w))",
	"int(lerp(a, b, w))",
	"inverse_lerp(a, b, v)",
	"remap(v, 0, 1, 0, 9)",
	"floorf(x)",
	"ceilf(x)",
	"roundf(x)",
	"absf(x)",
	"clampf(x, 0, 1)",
	"signf(x)",
	"snappedf(x, 1)",
	"wrapf(x, 0, 9)",
	"roundi(fmod(a, b))",
	"fposmod(a, b)",
	"asin(v)",
	"acos(v)",
	"deg_to_rad(d)",
	"rad_to_deg(r)",
	"text.to_float()",
	"is_equal_approx(a, b)",
	"int(exp(n))",
	"int(log (n))",
	# A # inside a string is not a comment: the code after it still counts.
	'var s := "#"; var f: float',
	'var s := "#" + str(1.5)',
	# More float builtins and float-returning methods on integer vectors.
	"maxf(a, b)",
	"minf(a, b)",
	"move_toward(a, b, d)",
	"smoothstep(a, b, x)",
	"lerp_angle(a, b, w)",
	"angle_difference(a, b)",
	"rotate_toward(a, b, d)",
	"pingpong(t, 3)",
	"sinh(x)",
	"cosh(x)",
	"tanh(x)",
	"is_zero_approx(x)",
	"cubic_interpolate(a, b, c, d, w)",
	"bezier_interpolate(a, b, c, d, t)",
	"var d := cell.distance_to(other)",
	"var n := offset.length()",
	"var r := size.aspect()",
	"ease(x, 2)",
	"var data = JSON.parse_string(text)",
	# hash() is engine defined, as a function or as a method.
	"var h: int = hash(pos)",
	"var h := name.hash()",
	"var h := hash (value)",
	# Randomness through the global generator.
	"targets.pick_random()",
	"units.shuffle()",
]
const MUST_NOT_MATCH: Array[String] = [
	"var delta: int = a - b",
	"var v: Vector2i = Vector2i(1, 2)",
	"var r: Rect2i",
	'var s := "1.5 sin Node"',
	"var x := 3 # 1.5 float sin",
	"0x1e5",
	"arr[0].size()",
	"var rng: DetRandom",
	"cmd_queue",
	"input_count",
	"cos_table",
	"Vector2i(1000, 2000).x",
	"dir_to(dx, dy)",
	"tick_rate",
	"var seed: int = 5",
	"var exp: int = 0",
	"var log: Array = []",
	"record_log(cmd)",
	"var lerp_steps: int = 3",
	"var ids: PackedInt32Array",
	"var raw: PackedByteArray",
	"var names: PackedStringArray",
	"var team_color: int = 0",
	"var colors: Array[int] = []",
	"var node_count: int = 0",
	"var server_id: int = 0",
	"var queue: ServerQueue",
	"extends RefCounted",
	"extends Object",
	"extends Resource",
	"var res: Resource",
	"JSON.stringify(data)",
	"MAX_SPEED",
	'var s := "#"',
	'var s := "#" # float 1.5 Timer',
	"rng.shuffle(units)",
	"var target: int = rng.pick_random(ids)",
	"var d2: int = a.distance_squared_to(b)",
	"var ease_steps: int = 4",
	"var lengths: Array[int] = []",
	# The legal hash names: only a bare hash( is banned.
	"var h: int = world.state_hash()",
	"var d: int = world.defs_hash()",
	"var s: String = World.hash_hex(h)",
	"var parts: PackedInt64Array = world.hash_parts()",
	"var hash_count: int = 0",
	"var hash: int = 0",
]

## Rule 3 for game/ai: the only check there is randomness.
const RAND_MUST_MATCH: Array[String] = [
	"var roll: int = randi() % 6",
	"randf()",
	"randf_range(0, 1)",
	"randi_range(0, 3)",
	"randomize()",
	"RandomNumberGenerator.new()",
	"rand_from_seed(5)",
	"randfn(0, 1)",
	"var target: int = targets.pick_random()",
	"units.shuffle()",
]
const RAND_MUST_NOT_MATCH: Array[String] = [
	"var x: float = 1.5",
	"var n: Node2D",
	"rng.next_int(6)",
	"var random_target: int = 0",
	"var operand: int = 0",
	'var s := "randi()"',
	"var x := 3 # randi()",
	"rng.shuffle(units)",
	"var target: int = rng.pick_random(ids)",
]

## Run as the body of a loop. Each statement is matched by exactly one part of ALLOC_NAMES, so
## dropping an operator, a keyword or a call from it fails this list.
const LOOP_OPEN: String = "for row: int in range(3):\n\t"
const ALLOC_MUST_MATCH: Array[String] = [
	"x = [row]",
	"foo([row])",
	"foo(a, [row])",
	'"k": [row],',
	"x = ids[[row][0]]",
	"x = a + [row]",
	"x = a - [row]",
	"x = a * [row]",
	"x = a / [row]",
	'x = "%d" % [row]',
	"x = a & [row]",
	"x = a | [row]",
	"x = a ^ [row]",
	"x = a < [row]",
	"x = a > [row]",
	"x = ![row]",
	"x = ~[row]",
	"return [row]",
	"x = row in [1, 2]",
	"x = a and [row]",
	"x = a or [row]",
	"x = not [row]",
	"x = 1 if a else [row]",
	"if [row]:",
	"elif [row]:",
	"while [row].size() > 2:",
	"match [row, 1]:",
	"x = a.duplicate(true)",
	"x = a.duplicate_deep()",
]

const NODE_BASES: Array[String] = [
	"extends Node\n",
	"extends CharacterBody2D\n",
	"extends Timer\n",
	"extends Sprite2D\n",
]
const DATA_BASES: Array[String] = [
	"extends RefCounted\n",
	"extends Object\n",
	"extends Resource\n",
	'extends "res://tests/support/file_scan.gd"\n',
]

var _strings: RegEx
var _banned: RegEx
var _banned_calls: RegEx
var _rand: RegEx
var _floats: RegEx
var _identifiers: RegEx
var _alloc: RegEx
var _loop_header: RegEx


func before() -> void:
	_strings = _compile(STRING_LITERAL)
	_banned = _compile(BANNED_NAMES)
	_banned_calls = _compile(BANNED_CALLS)
	_rand = _compile(RAND_NAMES)
	_floats = _compile(FLOAT_LITERAL)
	_identifiers = _compile(CAPITALISED_IDENTIFIER)
	_alloc = _compile(ALLOC_NAMES)
	_loop_header = _compile(LOOP_HEADER)


func test_sim_sources_are_pure() -> void:
	var violations: Array[String] = []
	for path: String in FileScan.list_files(SIM_DIR, ".gd"):
		var source: String = FileAccess.get_file_as_string(path)
		violations.append_array(_sim_violations(source, path))
	assert_array(violations).is_empty()


func test_sim_sources_do_not_allocate_in_loops() -> void:
	var violations: Array[String] = []
	for path: String in FileScan.list_files(SIM_DIR, ".gd"):
		violations.append_array(_alloc_violations(FileAccess.get_file_as_string(path), path))
	assert_array(violations).is_empty()


func test_sim_scripts_do_not_extend_node() -> void:
	var offenders: Array[String] = []
	for path: String in FileScan.list_files(SIM_DIR, ".gd"):
		var script: Script = load(path) as Script
		if script == null:
			offenders.append("%s: cannot be loaded" % path)
			continue
		var problem: String = _base_problem(script)
		if not problem.is_empty():
			offenders.append("%s: %s" % [path, problem])
	assert_array(offenders).is_empty()


func test_ai_sources_use_no_unseeded_randomness() -> void:
	var violations: Array[String] = []
	for path: String in FileScan.list_files(AI_DIR, ".gd"):
		var source: String = FileAccess.get_file_as_string(path)
		violations.append_array(_violations(source, path, _is_rand_violation))
	assert_array(violations).is_empty()


## Pinned to the line numbers of the fixture: the lines in a loop body or a while condition that
## allocate and do not end with `# alloc-ok`. Legal: 4 to 6, 30 to 31, 36, 40, 46, 62 and 67
## (before and after a loop), 19 to 24 and 26 to 27 (comment, index expressions, strings,
## `# alloc-ok`), 43, 57 to 60 and 95 (a `for` header's own brackets), 50 and 51 (an index after
## a call or a string), 75 to 82 and 84 to 85 (an alias, a name `when`, match patterns), 87 (a
## lambda body is no loop) and 89 (a stray bracket in a docstring).
func test_alloc_guard_flags_exactly_the_allocations_in_loop_bodies() -> void:
	var source: String = FileAccess.get_file_as_string(LOOP_FIXTURE)
	assert_str(source).is_not_empty()
	var found: Array[String] = _alloc_violations(source, "fixture")
	var line_numbers: Array[int] = []
	for report: String in found:
		line_numbers.append(int(report.split(":")[1]))
	assert_array(line_numbers).contains_exactly(
		(
			[7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 25, 29, 33, 34, 35, 39, 45, 49, 52]
			+ [53, 55, 61, 71, 83, 93, 97]
		)
	)
	assert_str(found[0]).is_equal("fixture:7: var a: Array[int] = []")


func test_alloc_guard_flags_an_array_after_every_operator_and_keyword() -> void:
	var missed: Array[String] = []
	for statement: String in ALLOC_MUST_MATCH:
		if _alloc_violations(LOOP_OPEN + statement, "x").is_empty():
			missed.append(statement)
	assert_array(missed).is_empty()


## A source with CRLF line endings leaves a \r after the marker.
func test_alloc_ok_marker_holds_on_a_crlf_line() -> void:
	assert_array(_alloc_violations(LOOP_OPEN + "x = [row]  # alloc-ok\r", "x")).is_empty()


func test_banned_calls_tell_the_author_what_to_use() -> void:
	var length_report: Array[String] = _sim_violations("var n: int = name.length()", "a.gd")
	assert_array(length_report).contains_exactly(
		[
			(
				"a.gd:1: var n: int = name.length()"
				+ "  <- use len() for a String size; Vector2i.length() is a float"
			)
		]
	)
	var hash_report: Array[String] = _sim_violations("var h: int = hash(pos)", "a.gd")
	assert_str(hash_report[0]).contains("World.state_hash()")
	# A line that breaks another rule gets no hint, and a hint is looked for in code only.
	assert_array(_sim_violations("var f: float", "a.gd")).contains_exactly(["a.gd:1: var f: float"])
	assert_array(_sim_violations("var f: float  # hash(x)", "a.gd")).contains_exactly(
		["a.gd:1: var f: float  # hash(x)"]
	)


func test_guard_flags_every_banned_fixture() -> void:
	var missed: Array[String] = []
	for line: String in MUST_MATCH:
		if not _is_sim_violation(line):
			missed.append(line)
	assert_array(missed).is_empty()


func test_guard_accepts_every_legal_fixture() -> void:
	var wrongly_flagged: Array[String] = []
	for line: String in MUST_NOT_MATCH:
		if _is_sim_violation(line):
			wrongly_flagged.append(line)
	assert_array(wrongly_flagged).is_empty()


func test_ai_guard_flags_every_randomness_fixture() -> void:
	var missed: Array[String] = []
	for line: String in RAND_MUST_MATCH:
		if not _is_rand_violation(line):
			missed.append(line)
	assert_array(missed).is_empty()


func test_ai_guard_accepts_every_legal_fixture() -> void:
	var wrongly_flagged: Array[String] = []
	for line: String in RAND_MUST_NOT_MATCH:
		if _is_rand_violation(line):
			wrongly_flagged.append(line)
	assert_array(wrongly_flagged).is_empty()


func test_base_check_flags_scripts_that_extend_a_node() -> void:
	var missed: Array[String] = []
	for source: String in NODE_BASES:
		if _base_problem(_script_from(source)).is_empty():
			missed.append(source.strip_edges())
	assert_array(missed).is_empty()


## This suite extends GdUnitTestSuite, a user script whose native base is Node.
func test_base_check_follows_a_user_base_class_to_node() -> void:
	var script: Script = get_script()
	assert_str(_base_problem(script)).is_not_empty()


func test_base_check_accepts_scripts_that_hold_only_data() -> void:
	var wrongly_flagged: Array[String] = []
	for source: String in DATA_BASES:
		if not _base_problem(_script_from(source)).is_empty():
			wrongly_flagged.append(source.strip_edges())
	assert_array(wrongly_flagged).is_empty()


func test_scan_reports_file_and_line_of_each_violation() -> void:
	var source: String = (
		"\n"
		. join(
			[
				"class_name Example",
				"# a float in a comment is fine: 1.5",
				"var speed: int = 3",
				"var half: float = 0",
				'var label := "sin 2.5"',
				"func tick() -> void:",
				"\tvar roll: int = randi() % 6",
				"\tvar timer: Timer = null",
			]
		)
	)
	var found: Array[String] = _violations(source, "example.gd", _is_sim_violation)
	(
		assert_array(found)
		. contains_exactly(
			[
				"example.gd:4: var half: float = 0",
				"example.gd:7: var roll: int = randi() % 6",
				"example.gd:8: var timer: Timer = null",
			]
		)
	)


func _compile(pattern: String) -> RegEx:
	var regex: RegEx = RegEx.new()
	assert_int(regex.compile(pattern)).is_equal(OK)
	return regex


## The line without string literals and without the comment, which cannot hold code.
func _strip(line: String) -> String:
	var code: String = _strings.sub(line, '""', true)
	var comment_start: int = code.find("#")
	if comment_start >= 0:
		code = code.substr(0, comment_start)
	return code


func _is_sim_violation(line: String) -> bool:
	var code: String = _strip(line)
	return (
		_banned.search(code) != null
		or _banned_calls.search(code) != null
		or _rand.search(code) != null
		or _floats.search(code) != null
		or _names_engine_node_or_server(code)
	)


func _is_rand_violation(line: String) -> bool:
	return _rand.search(_strip(line)) != null


## True when the code names an engine class that is a Node or has Server in its name
## (RenderingServer, PhysicsServer2D, NavigationServer2D, ...). User classes are no engine
## classes, so ClassDB leaves them and built-in types such as Vector2i or Color alone.
func _names_engine_node_or_server(code: String) -> bool:
	for found: RegExMatch in _identifiers.search_all(code):
		var identifier: String = found.get_string()
		if not ClassDB.class_exists(identifier):
			continue
		if ClassDB.is_parent_class(identifier, &"Node") or identifier.contains("Server"):
			return true
	return false


## Why `script` may not live in game/sim, or "" when its base type is fine.
func _base_problem(script: Script) -> String:
	var base: StringName = script.get_instance_base_type()
	if base == &"":
		return "base type unknown, the script does not compile"
	if ClassDB.is_parent_class(base, &"Node"):
		return "extends %s, which is a Node" % base
	return ""


func _script_from(source: String) -> GDScript:
	var script: GDScript = GDScript.new()
	script.source_code = source
	assert_int(script.reload()).is_equal(OK)
	return script


## What test_sim_sources_are_pure reports for one file.
func _sim_violations(source: String, label: String) -> Array[String]:
	return _violations(source, label, _is_sim_violation, _hint)


func _violations(
	source: String, label: String, is_violation: Callable, hint: Callable = Callable()
) -> Array[String]:
	var found: Array[String] = []
	var lines: PackedStringArray = source.split("\n")
	for index: int in lines.size():
		var flagged: bool = is_violation.call(lines[index])
		if flagged:
			var report: String = "%s:%d: %s" % [label, index + 1, lines[index].strip_edges()]
			found.append(report + (hint.call(lines[index]) if hint.is_valid() else ""))
	return found


## "  <- advice" for the banned calls that have some, else "".
func _hint(line: String) -> String:
	var code: String = _strip(line)
	for pattern: String in HINTS:
		if _compile(pattern).search(code) != null:
			return "  <- " + HINTS[pattern]
	return ""


## Reports of allocations inside for and while bodies, and in a while condition, which runs on
## every pass. A loop owns the lines after its header that are indented deeper than the header;
## comment and blank lines do not count. A header whose brackets stay open past its line (a long
## `range(...)` call) starts its loop only when they close, so a `for` iterable, evaluated once,
## is not part of the body. Brackets are counted from the header's own depth, so a multi-line
## call around the loop or a stray bracket in a docstring cannot hide it.
func _alloc_violations(source: String, label: String) -> Array[String]:
	var found: Array[String] = []
	var loops: Array[int] = []
	var header: int = -1
	var header_depth: int = 0
	var each_pass: bool = false
	var open_brackets: int = 0
	var lines: PackedStringArray = source.split("\n")
	for index: int in lines.size():
		var code: String = _strip(lines[index])
		if code.strip_edges().is_empty():
			continue
		var indent: int = len(code) - len(code.lstrip(" \t"))
		while not loops.is_empty() and indent <= loops[-1]:
			loops.pop_back()
		var depth_before: int = open_brackets
		open_brackets += _bracket_balance(code)
		if header < 0 and _loop_header.search(code) != null:
			header = indent
			header_depth = depth_before
			each_pass = code.strip_edges().begins_with("while")
		var scanned: bool = not loops.is_empty() or (header >= 0 and each_pass)
		if scanned and not _is_match_pattern(code) and _alloc.search(code) != null:
			if not lines[index].strip_edges().ends_with(ALLOC_OK):
				found.append("%s:%d: %s" % [label, index + 1, lines[index].strip_edges()])
		if header >= 0 and open_brackets <= header_depth:
			loops.push_back(header)
			header = -1
	return found


## A pattern such as `[1, _]:` or `{"a": 1}:` under a match is compared, not built.
func _is_match_pattern(code: String) -> bool:
	var text: String = code.strip_edges()
	return text.ends_with(":") and (text.begins_with("[") or text.begins_with("{"))


func _bracket_balance(code: String) -> int:
	var opened: int = code.count("(") + code.count("[") + code.count("{")
	return opened - code.count(")") - code.count("]") - code.count("}")
