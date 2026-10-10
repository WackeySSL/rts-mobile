extends GdUnitTestSuite
## Purity guard for game/sim (CLAUDE.md architecture rules 1 to 3): no Node, no engine time or
## input, no floats, no randomness except through a DetRandom passed in, no autoload.
##
## Three layers guard game/sim:
## - Name and literal patterns on each line, after string literals and comments are stripped.
## - An identifier scan that asks ClassDB whether a capitalised word is an engine Node class or
##   a *Server singleton. Names alone cannot list the 200 Node classes.
## - A base type check: no sim script may extend a Node, directly or through a user base class.
## game/ai is scanned for randomness only (rule 3).
##
## The scans over game/sim and game/ai are vacuous until those folders hold code. The fixture
## tests are not: they prove each pattern catches what it must and leaves legal integer code
## alone.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const SIM_DIR: String = "res://game/sim"
const AI_DIR: String = "res://game/ai"

const STRING_LITERAL: String = r"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'"
const RAND_NAMES: String = (
	r"\b(RandomNumberGenerator" + r"|rand(i|f|i_range|f_range|fn|_from_seed|omize))\b"
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
	+ r"|get_node|queue_free|create_tween)\b"
)
## exp and log only as calls: `var exp: int` (veterancy) and `var log: Array` (command log)
## are legal names in the sim.
const BANNED_CALLS: String = r"\b(exp|log)\s*\("
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
]
const RAND_MUST_NOT_MATCH: Array[String] = [
	"var x: float = 1.5",
	"var n: Node2D",
	"rng.next_int(6)",
	"var random_target: int = 0",
	"var operand: int = 0",
	'var s := "randi()"',
	"var x := 3 # randi()",
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


func before() -> void:
	_strings = _compile(STRING_LITERAL)
	_banned = _compile(BANNED_NAMES)
	_banned_calls = _compile(BANNED_CALLS)
	_rand = _compile(RAND_NAMES)
	_floats = _compile(FLOAT_LITERAL)
	_identifiers = _compile(CAPITALISED_IDENTIFIER)


func test_sim_sources_are_pure() -> void:
	var violations: Array[String] = []
	for path: String in FileScan.list_files(SIM_DIR, ".gd"):
		var source: String = FileAccess.get_file_as_string(path)
		violations.append_array(_violations(source, path, _is_sim_violation))
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


func _violations(source: String, label: String, is_violation: Callable) -> Array[String]:
	var found: Array[String] = []
	var lines: PackedStringArray = source.split("\n")
	for index: int in lines.size():
		var flagged: bool = is_violation.call(lines[index])
		if flagged:
			found.append("%s:%d: %s" % [label, index + 1, lines[index].strip_edges()])
	return found
