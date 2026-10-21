extends GdUnitTestSuite
## The view reads the published snapshot and nothing else (ADR 0012 section 3, "View rules", plan
## P50w). While a job runs on the worker, the runner's `world`, `loop`, `replay` and `probe` belong
## to it, so no production code of the view, the input or the UI may reach them. A source scan over
## every `.gd` file fails on:
## - `game/view`, `game/input` and `game/ui`: a member access `.world`, `.loop`, `.replay` or
##   `.probe` (`runner.world.pos_x`, `runner.probe = p`; the installer is `set_probe()`);
## - `game/ai`: `.loop`, `.replay` and `.probe`. Its World reads inside `ticked` are allowed and
##   guarded at runtime (ADR 0012 section 3), so `.world` is not scanned there;
## - all four folders: a member variable (a `var` at column 0, with its annotations or `static`)
##   typed `World`, alone or in an Array or as a Dictionary value, or made with `:= World.new(` or
##   `:= World.from_scenario(`. A World held between frames is a World read outside `ticked`.
## The scan takes comments out and blanks the strings first, and looks at the whole text, so a
## chain that gdformat wraps (`runner` and `. world` on two lines) is seen. A name that only starts
## with one of the four (`world_px`, `screen_to_world(`, `set_probe(`, `get_world_2d()`) is not.
## The scan is a line lint with documented gaps, not a proof. What it cannot see:
## - a name computed or given as a string: `runner.get("world")`, `runner["world"]`. The guarded
##   getters catch those at run time, in tests/scenes/test_worker_scenes.gd (the layers run while a
##   job is in flight there);
## - a World, loop, replay or probe that reaches the view through another object's property.
## Every rule has fixtures that it must flag and fixtures that it must leave alone, so a scan that
## matches nothing fails, and the folders must still hold the scripts the scan is about.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const VIEW_DIRS: Array[String] = ["res://game/view", "res://game/input", "res://game/ui"]
const AI_DIR: String = "res://game/ai"
## Scripts that read the runner's snapshot today, one per folder. A rename or a move fails the
## test, and the new place goes here, so the scan cannot pass by finding nothing.
const KNOWN_SCRIPTS: Array[String] = [
	"res://game/view/UnitLayer.gd",
	"res://game/view/FogLayer.gd",
	"res://game/input/PlayerController.gd",
	"res://game/ui/SelectionPanel.gd",
]

## A member access to one of the runner's guarded objects. White space or a `\` after the dot also
## reads the `. world` that gdformat writes in a wrapped chain, and a continued line.
const VIEW_MEMBER: String = r"\.[\s\\]*(?:world|loop|replay|probe)\b"
const AI_MEMBER: String = r"\.[\s\\]*(?:loop|replay|probe)\b"
## A member variable typed World: at column 0, after annotations or `static`. `World.Armour` and
## `World2D` are other types.
const WORLD_VAR: String = (
	r"(?m)^(?:(?:@\w+(?:\([^)]*\))?|static)[ \t]+)*var[ \t]+\w+[ \t]*"
	+ r"(?::[ \t]*(?:(?:Array|Dictionary)\[[^\]]*\bWorld(?![\w.])[^\]]*\]|World(?![\w.]))"
	+ r"|:=[ \t]*World\.(?:new|from_scenario)\()"
)
## What a comment or a string looks like, read from the left so that a comment hides the quote in
## it and a string hides the "#" in it.
const TOKEN: String = (
	r'(?s)"""(?:[^\\]|\\.)*?"""|'
	+ r"'''(?:[^\\]|\\.)*?'''|"
	+ r'"(?:[^"\\]|\\.)*"|'
	+ r"'(?:[^'\\]|\\.)*'|"
	+ r"#[^\n]*"
)

## Source text that VIEW_MEMBER must flag: the four reads of the plan, a chain that gdformat wraps,
## a read before a comment and one inside an expression.
const VIEW_FLAGGED: Array[String] = [
	"var x: int = runner.world.pos_x[0]",
	"var w: World = runner.world",
	"var h: int = runner.replay.checkpoint_hashes[0]",
	"runner.probe = p",
	"var l: MatchLoop = runner.loop",
	"var w: World = $MatchRunner.world",
	'var w: World = get_node("MatchRunner").world',
	"var w: World = runner.world  # the world",
	"var x: int = (runner.world).tick",
	"var x: int = (\n\trunner\n\t. world\n\t. pos_x[0]\n)",
	"var x: int = runner.\\\nloop.last_hash",
]
## Source text that VIEW_MEMBER must leave alone.
const VIEW_CLEAN: Array[String] = [
	"var world_px: Vector2 = camera.screen_to_world(at)",
	"var screen: Vector2 = camera.world_to_screen(at)",
	"runner.set_probe(p)",
	"var x: int = runner.snapshot.pos_x[0]",
	"var f: FogGrid = runner.snapshot.fog",
	"var p: int = runner.scenario.local_player",
	"var a: float = runner.alpha()",
	"var c: World2D = get_world_2d()",
	"var e: int = World.Event.DIED",
	"# runner.world.pos_x is read in ticked only",
	"## The probe is runner.probe, set through set_probe().",
	'var s: String = "runner.world and runner.replay"',
	"var s: String = 'runner.loop'",
	'var t: String = "a # b"  # runner.probe',
	'"""\nrunner.world\n"""',
	"var looped: bool = animation_loop",
	"var probe_count: int = hud.probe_total",
]
## The same for AI_MEMBER: the three it flags, and `.world`, which it allows.
const AI_FLAGGED: Array[String] = [
	"var l: MatchLoop = runner.loop",
	"var r: Replay = runner.replay",
	"runner.probe = p",
]
const AI_CLEAN: Array[String] = [
	"var w: World = runner.world",
	"var t: int = runner.world.tick",
	"runner.set_probe(p)",
	"# runner.loop",
]
## The same for WORLD_VAR.
const WORLD_FLAGGED: Array[String] = [
	"var world: World",
	"var _world: World = null",
	"var _world: World  # the match",
	"@export var world: World",
	"@onready var world: World = null",
	"@export_range(0, 1) var world: World",
	"static var cached: World",
	"@warning_ignore('unused_private_class_variable') var _w: World",
	"var worlds: Array[World] = []",
	"var by_id: Dictionary[int, World] = {}",
	"var by_world: Dictionary[World, int] = {}",
	"var w := World.new()",
	"var w := World.from_scenario(scenario, rng)",
]
const WORLD_CLEAN: Array[String] = [
	"\tvar world: World = runner.world",
	"\t\tvar worlds: Array[World] = []",
	"var world_px: Vector2",
	"var plane: World2D",
	"var armour: World.Armour = World.Armour.INFANTRY",
	"var kinds: Array[World.Event] = []",
	"var w: int = World.EVENT_STRIDE",
	"# var world: World",
	'var s: String = "var world: World"',
	"func f(world: World) -> void:",
	"const WORLD: Script = World",
]

var _token: RegEx


func before() -> void:
	_token = RegEx.create_from_string(TOKEN)


func test_no_view_input_or_ui_script_reads_the_runners_world_loop_replay_or_probe() -> void:
	var found: Array[String] = []
	for dir: String in VIEW_DIRS:
		found.append_array(_scan_dir(dir, VIEW_MEMBER))
	(
		assert_array(found)
		. override_failure_message(
			(
				"The view reads the snapshot (ADR 0012 section 3); `world`, `loop`, `replay` and "
				+ "`probe` belong to the worker while a job runs:\n%s" % "\n".join(found)
			)
		)
		. is_empty()
	)


func test_no_ai_script_reads_the_runners_loop_replay_or_probe() -> void:
	var found: Array[String] = _scan_dir(AI_DIR, AI_MEMBER)
	(
		assert_array(found)
		. override_failure_message(
			(
				"The AI may read the World inside `ticked` only, and never `loop`, `replay` or "
				+ "`probe` (ADR 0012 section 3):\n%s" % "\n".join(found)
			)
		)
		. is_empty()
	)


func test_no_member_variable_of_the_view_input_ui_or_ai_is_typed_world() -> void:
	var found: Array[String] = []
	for dir: String in VIEW_DIRS + [AI_DIR]:
		found.append_array(_scan_dir(dir, WORLD_VAR))
	(
		assert_array(found)
		. override_failure_message(
			(
				"A member typed World keeps a World between frames; read it inside `ticked` into "
				+ "a local:\n%s" % "\n".join(found)
			)
		)
		. is_empty()
	)


func test_each_member_rule_flags_its_fixtures_and_spares_the_clean_ones() -> void:
	var rules: Dictionary[String, Array] = {
		VIEW_MEMBER: [VIEW_FLAGGED, VIEW_CLEAN],
		AI_MEMBER: [AI_FLAGGED, AI_CLEAN],
		WORLD_VAR: [WORLD_FLAGGED, WORLD_CLEAN],
	}
	for pattern: String in rules:
		assert_bool(RegEx.create_from_string(pattern).is_valid()).is_true()
		var pair: Array = rules[pattern]
		for source: String in pair[0]:
			(
				assert_array(_hits(source, pattern))
				. override_failure_message("not flagged: %s" % source.c_escape())
				. has_size(1)
			)
		for source: String in pair[1]:
			(
				assert_array(_hits(source, pattern))
				. override_failure_message("flagged: %s" % source.c_escape())
				. is_empty()
			)


## The AI rule leaves `.world` to the runtime guard; the view rule does not.
func test_the_ai_rule_allows_world_and_the_view_rule_does_not() -> void:
	for source: String in ["var w: World = runner.world", "var t: int = runner.world.tick"]:
		assert_array(_hits(source, AI_MEMBER)).is_empty()
		assert_array(_hits(source, VIEW_MEMBER)).has_size(1)
	for source: String in AI_FLAGGED:
		assert_array(_hits(source, VIEW_MEMBER)).has_size(1)


## A hit is reported at its own line, also when the chain is wrapped, and a comment or a string
## that holds the name does not move it.
func test_a_hit_is_reported_with_its_line_number_after_comments_and_strings() -> void:
	var source: String = (
		'# runner.world\nvar a: int = 1  # runner.loop\n"""\nrunner.replay\n"""\n'
		+ 'var s: String = "runner.probe"\nvar x: int = (\n\trunner\n\t. world\n\t. tick\n)\n'
		+ "runner.probe = p\n"
	)
	assert_array(_hits(source, VIEW_MEMBER, "res://a.gd")).is_equal(
		["res://a.gd:9: . world", "res://a.gd:12: runner.probe = p"]
	)
	assert_int(_code_of(source).split("\n").size()).is_equal(source.split("\n").size())


## A scan that reads nothing passes everything.
func test_the_scan_reads_the_folders_and_the_scripts_it_should() -> void:
	for dir: String in VIEW_DIRS:
		assert_array(FileScan.list_files(dir, ".gd")).override_failure_message(dir).is_not_empty()
	var scanned: Array[String] = []
	for dir: String in VIEW_DIRS + [AI_DIR]:
		scanned.append_array(FileScan.list_files(dir, ".gd"))
	assert_array(scanned).contains(KNOWN_SCRIPTS)
	assert_bool(DirAccess.dir_exists_absolute(AI_DIR)).is_true()


## "path:line: text" for each match of `pattern` in every script below `dir`.
func _scan_dir(dir: String, pattern: String) -> Array[String]:
	var found: Array[String] = []
	for path: String in FileScan.list_files(dir, ".gd"):
		found.append_array(_hits(FileAccess.get_file_as_string(path), pattern, path))
	return found


## "path:line: text" for each match of `pattern` in the code of `source`: the line of the match's
## start, as the file has it.
func _hits(source: String, pattern: String, path: String = "") -> Array[String]:
	var code: String = _code_of(source)
	var lines: PackedStringArray = source.split("\n")
	var found: Array[String] = []
	for hit: RegExMatch in RegEx.create_from_string(pattern).search_all(code):
		var line: int = code.substr(0, hit.get_start()).count("\n")
		found.append("%s:%d: %s" % [path, line + 1, lines[line].strip_edges()])
	return found


## `source` with each comment taken out and each string reduced to "" (its line breaks stay), so
## every line keeps its number.
func _code_of(source: String) -> String:
	var out: String = ""
	var at: int = 0
	for token: RegExMatch in _token.search_all(source):
		out += source.substr(at, token.get_start() - at)
		var text: String = token.get_string()
		if not text.begins_with("#"):
			out += '""' + "\n".repeat(text.count("\n"))
		at = token.get_end()
	return out + source.substr(at)
