extends GdUnitTestSuite
## The view reads the published snapshot and nothing else (ADR 0012 section 3, "View rules", plan
## P50w). While a job runs on the worker, the runner's `world`, `loop`, `replay` and `probe` belong
## to it, so no production code of the view, the input or the UI may reach them. A source scan over
## every `.gd` file fails on:
## - `game/view`, `game/input` and `game/ui`: a member access `.world`, `.loop`, `.replay` or
##   `.probe` (`runner.world.pos_x`, `runner.probe = p`; the installer is `set_probe()`);
## - `game/ai`: the same four, `.world` too, and the name `World` itself, as a type, as `World.Tab`
##   or as `World.new(`. ADR 0020 section 3 moved the AI into the tick job, where it reads the
##   match through `PlayerView` and never names the World (`PlayerView` re-exports `Tab`,
##   `HarvestMode`, `Order`, `TABS`, `MILLI_PER_TILE` and `TILE_CENTRE`; `Placement.Reason` may be
##   named), so the allowance of `.world` that ADR 0012 section 3 gave it is gone;
## - all four folders: a member variable (a `var` at column 0, with its annotations or `static`)
##   typed `World`, alone or in an Array or as a Dictionary value, or made with `:= World.new(` or
##   `:= World.from_scenario(`. A World held between frames is a World read outside `ticked`.
## The scan takes comments out and blanks the strings first, and looks at the whole text, so a
## chain that gdformat wraps (`runner` and `. world` on two lines) is seen. A name that only starts
## with one of the four (`world_px`, `screen_to_world(`, `set_probe(`, `get_world_2d()`) is not.
## The scan is a line lint with documented gaps, not a proof. What it cannot see:
## - a name computed or given as a string: `runner.get("world")`, `runner["world"]`. The guarded
##   getters catch those at run time, in tests/scenes/test_worker_scenes.gd (the layers run while a
##   job is in flight there). game/ai cannot build the name from a string either: test_sim_purity
##   bans `ClassDB`, `load(` and `preload(` there;
## - a World, loop, replay or probe that reaches the view through another object's property.
## Every rule has fixtures that it must flag and fixtures that it must leave alone, so a scan that
## matches nothing fails, and the folders must still hold the scripts the scan is about. game/ai
## may be empty, so its rules also run through the function that scans a folder on two fixture
## files: one that breaks each of them and one controller that keeps them.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const VIEW_DIRS: Array[String] = ["res://game/view", "res://game/input", "res://game/ui"]
const AI_DIR: String = "res://game/ai"
## Read as text and never loaded, so no scan of game/ and no import step meets them.
const BREAKING_FIXTURE: String = "res://tests/project/fixtures/ai_reads_world.txt"
const CONTROLLER_FIXTURE: String = "res://tests/project/fixtures/ai_legal_controller.txt"
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
## The name `World` as a whole word, which game/ai may not use: `World2D`, `WorldLoad`, `newWorld`
## and `world_px` are other names, and `world` is no type.
const WORLD_NAME: String = r"\bWorld\b"
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
## The same for WORLD_NAME, which only game/ai gets: one name in each flagged source.
const WORLD_NAME_FLAGGED: Array[String] = [
	"var world: World",
	"var held: World = null",
	"func think(view: PlayerView, world: World) -> void:",
	"var tab: int = World.Tab.STRUCTURES",
	"var per_tile: int = World.MILLI_PER_TILE",
	"var kinds: Array[World.Event] = []",
	"var by_id: Dictionary[int, World] = {}",
	"var w := World.new()",
	"var ok: bool = view is World",
	"var w = view as World",
	"extends World",
	"const W: Script = World",
	"var x: int = (\n\tWorld\n\t.EVENT_STRIDE\n)",
]
const WORLD_NAME_CLEAN: Array[String] = [
	"var view: PlayerView",
	"var tab: int = PlayerView.Tab.STRUCTURES",
	"var per_tile: int = PlayerView.MILLI_PER_TILE",
	"var reason: int = Placement.Reason.OK",
	"var layer: World2D = null",
	"var loader: WorldLoad = null",
	"var world_px: int = 0",
	"var worlds: int = 0",
	"var newWorld: int = 0",
	"var MyWorld: int = 0",
	"var WORLD: int = 0",
	"var world: PlayerView = view",
	"# var world: World",
	"## World is never named here",
	'var s: String = "World"',
	"var s: String = 'World.Tab'",
	'"""\nWorld\n"""',
	'var t: String = "a # b"  # World',
]
## The rules of game/ai (ADR 0020 section 3): the pattern, what a hit tells the author, and the
## lines of BREAKING_FIXTURE that it must flag. The member rule is the view's, so `.world` is
## flagged there too (lines 13 to 16 and the wrapped `. world` of line 19); the name rule flags a
## member, a parameter and two uses of the type (7, 8, 11, 12) and the typed-member rule the two
## members. Lines 22 to 28 stay clean: the legal names, World2D, WorldLoad, world_px, a comment and
## a string with the words. The folder test and the fixture tests both read this list.
const AI_RULES: Array[Dictionary] = [
	{
		"pattern": VIEW_MEMBER,
		"advice":
		(
			"the AI runs in the tick job and reads the match through PlayerView, never the "
			+ "runner's `world`, `loop`, `replay` or `probe`"
		),
		"lines": [13, 14, 15, 16, 19],
	},
	{
		"pattern": WORLD_NAME,
		"advice":
		(
			"game/ai never names World; PlayerView re-exports Tab, HarvestMode, Order, TABS, "
			+ "MILLI_PER_TILE and TILE_CENTRE"
		),
		"lines": [7, 8, 11, 12],
	},
	{
		"pattern": WORLD_VAR,
		"advice": "a World held in a member outlives its think; read the match through PlayerView",
		"lines": [7, 8],
	},
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


func test_no_ai_script_reads_the_runner_or_names_world() -> void:
	var found: Array[String] = []
	for rule: Dictionary in AI_RULES:
		var pattern: String = rule["pattern"]
		var hits: Array[String] = _scan_dir(AI_DIR, pattern)
		if not hits.is_empty():
			found.append("%s (ADR 0020 section 3):\n%s" % [rule["advice"], "\n".join(hits)])
	assert_array(found).override_failure_message("\n".join(found)).is_empty()


func test_no_member_variable_of_the_view_input_or_ui_is_typed_world() -> void:
	var found: Array[String] = []
	for dir: String in VIEW_DIRS:
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
		WORLD_VAR: [WORLD_FLAGGED, WORLD_CLEAN],
		WORLD_NAME: [WORLD_NAME_FLAGGED, WORLD_NAME_CLEAN],
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


## The three rules of game/ai flag the lines of BREAKING_FIXTURE that AI_RULES lists, and no other,
## through the function that scans a folder. `.world` is among them: game/ai has no allowance.
func test_the_ai_rules_flag_exactly_the_lines_of_a_controller_that_breaks_them() -> void:
	for rule: Dictionary in AI_RULES:
		var pattern: String = rule["pattern"]
		var lines: Array[int] = []
		for hit: String in _scan_files([BREAKING_FIXTURE], pattern):
			lines.append(int(hit.split(":")[2]))
		assert_array(lines).override_failure_message(pattern).is_equal(rule["lines"])


## A controller that reads the match through PlayerView, names Placement.Reason and keeps the words
## of the bans in comments, strings and look-alike names is flagged by no rule of game/ai.
func test_the_ai_rules_leave_a_legal_controller_alone() -> void:
	var source: String = FileAccess.get_file_as_string(CONTROLLER_FIXTURE)
	assert_int(source.split("\n").size()).is_greater(60)
	assert_str(source).contains("PlayerView.Tab").contains("Placement.Reason")
	for rule: Dictionary in AI_RULES:
		var pattern: String = rule["pattern"]
		(
			assert_array(_scan_files([CONTROLLER_FIXTURE], pattern))
			. override_failure_message(pattern)
			. is_empty()
		)


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
	return _scan_files(FileScan.list_files(dir, ".gd"), pattern)


## The same for the files at `paths`.
func _scan_files(paths: Array[String], pattern: String) -> Array[String]:
	var found: Array[String] = []
	for path: String in paths:
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
