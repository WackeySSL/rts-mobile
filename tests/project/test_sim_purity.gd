extends GdUnitTestSuite
## Purity guard for game/sim (CLAUDE.md architecture rules 1 to 3): no Node, no engine time or
## input, no floats, no randomness except through a DetRandom passed in, no autoload.
## String literals and comments are stripped before the patterns run.
##
## The scan over game/sim is vacuous until Phase 2 adds sim code. The fixture tests are not: they
## prove the patterns catch what they must and leave legal integer code alone.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const SIM_DIR: String = "res://game/sim"

const STRING_LITERAL: String = r"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'"
const BANNED_NAMES: String = (
	r"\b(Node[A-Za-z0-9]*|SceneTree|Input|OS|Time|Engine|RandomNumberGenerator"
	+ r"|rand(i|f|i_range|f_range|fn|_from_seed|omize)|float|sin|cos|tan|sqrt|atan2?|pow"
	+ r"|PI|TAU|INF|NAN|Vector[234]|Rect2|Transform[23]D|get_tree|DetRng|CommandQueue"
	+ r"|_process|_physics_process|get_(physics_)?process_delta_time)\b"
)
const FLOAT_LITERAL: String = (
	r"(?<![A-Za-z0-9_.])[0-9][0-9_]*\.[0-9]|(?<![A-Za-z0-9_])\.[0-9]"
	+ r"|(?<![A-Za-z0-9_.])[0-9][0-9_]*\.(?![0-9A-Za-z_])|\b[0-9]+[eE][+-]?[0-9]"
)

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
]

var _strings: RegEx
var _banned: RegEx
var _floats: RegEx


func before() -> void:
	_strings = _compile(STRING_LITERAL)
	_banned = _compile(BANNED_NAMES)
	_floats = _compile(FLOAT_LITERAL)


func test_sim_sources_are_pure() -> void:
	var violations: Array[String] = []
	for path: String in FileScan.list_files(SIM_DIR, ".gd"):
		violations.append_array(_violations(FileAccess.get_file_as_string(path), path))
	assert_array(violations).is_empty()


func test_guard_flags_every_banned_fixture() -> void:
	var missed: Array[String] = []
	for line: String in MUST_MATCH:
		if not _is_violation(line):
			missed.append(line)
	assert_array(missed).is_empty()


func test_guard_accepts_every_legal_fixture() -> void:
	var wrongly_flagged: Array[String] = []
	for line: String in MUST_NOT_MATCH:
		if _is_violation(line):
			wrongly_flagged.append(line)
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
			]
		)
	)
	var found: Array[String] = _violations(source, "example.gd")
	(
		assert_array(found)
		. contains_exactly(
			[
				"example.gd:4: var half: float = 0",
				"example.gd:7: var roll: int = randi() % 6",
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


func _is_violation(line: String) -> bool:
	var code: String = _strip(line)
	return _banned.search(code) != null or _floats.search(code) != null


func _violations(source: String, label: String) -> Array[String]:
	var found: Array[String] = []
	var lines: PackedStringArray = source.split("\n")
	for index: int in lines.size():
		if _is_violation(lines[index]):
			found.append("%s:%d: %s" % [label, index + 1, lines[index].strip_edges()])
	return found
