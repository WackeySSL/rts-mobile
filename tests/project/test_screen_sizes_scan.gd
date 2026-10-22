extends GdUnitTestSuite
## The six test sizes of ADR 0015 section 6 live in one list, `tests/support/screen_sizes.gd`, and
## no UI or layout suite stays landscape-only (plan P60). A UI or layout suite is a `.gd` file under
## `tests/ui`, `tests/scenes` or `tests/view`. A source scan, one line at a time with the comments
## taken out, fails on:
## - `literal_window_size`: a window size set from a literal (`get_window().size = Vector2i(1600,
##   720)`, `set_size(Vector2i(...))`). The size comes from ScreenSizes, from a profile of
##   ui_profiles.gd or from a constant the suite names;
## - `restated_screen_size`: a `Vector2i` literal that is one of the six sizes, wherever it stands
##   (a constant, a list entry, a dictionary key, an argument, a comparison). The suite then copies
##   the shared list where it should read it, and a size that is added to the list or turned into a
##   portrait pair is missed by that copy;
## - `landscape_only`: a suite that runs only landscape sizes without an entry in PORTRAIT_PENDING.
##   It reads the whole of `ScreenSizes.LANDSCAPE` (not one entry of it), calls `UiProfiles.all()`
##   or lists two of the landscape profiles by name, and reads none of `ScreenSizes.PORTRAIT`,
##   `ScreenSizes.ALL` and `UiProfiles.portrait()`.
## PORTRAIT_PENDING holds each suite that is landscape-only today, with the row that makes it run
## portrait too (P61 the HUD, P62 the camera and the view, P63 the dev scenes). An entry goes in the
## row that removes the suite's landscape-only part, and the scan fails on an entry whose suite
## already reads a portrait size. P64 (the orientation flip) requires the list to be empty.
## Every rule has fixture lines that it must flag and lines that it must leave alone, so a scan
## that matches nothing fails.
## The scan is a line lint with documented gaps, not a proof that every case runs portrait:
## - a size by arithmetic or through a variable (`Vector2i(w, h)`, `base + Vector2i(320, 0)`), and a
##   constant of the suite that holds an odd literal (`WIDE_SIZE`): neither is one of the six and
##   the constant is a name a reviewer sees;
## - a landscape sweep that goes through a table of the suite's own (a dictionary keyed by
##   `ScreenSizes.LANDSCAPE[0]`, `[1]` and `[2]` and no read of the whole list), and a list of
##   profile names split over lines or with a value after each name (`[&"desktop", 32]`): list the
##   suite by hand;
## - `tests/input`, `tests/core` and the other test folders: only the three above are read.
## What it still catches is the default way to write a new suite: a literal window size, a copy of
## the list, or a loop over the landscape sizes.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const SCANNED_DIRS: Array[String] = ["res://tests/ui", "res://tests/scenes", "res://tests/view"]
## The rows that may remove an entry (docs/plans/2026-10-19-portrait.md).
const ROWS: Array[String] = ["P61", "P62", "P63"]

## The suites that run only landscape sizes today, each with the row that makes it run portrait
## too. The plan's file lists name the P61 suites (the HUD, the theme and the main scene),
## test_rts_camera and test_controls_flow (P62, whose scene case is the view-only proof) and
## test_touch_probe (P63). The other view suites and the two perf arena suites are in no row's file
## list yet: they stand under the row of their layer (P62 the view, P63 the dev scenes) until the
## lead places them.
const PORTRAIT_PENDING: Dictionary[String, String] = {
	"res://tests/ui/test_army_bar.gd": "P61",
	"res://tests/ui/test_selection_panel.gd": "P61",
	"res://tests/ui/test_touch_target_sizes.gd": "P61",
	"res://tests/ui/test_ui_theme.gd": "P61",
	"res://tests/scenes/test_main_scene.gd": "P61",
	"res://tests/view/test_effects_layer_curves.gd": "P62",
	"res://tests/view/test_feedback.gd": "P62",
	"res://tests/view/test_fog_hiding.gd": "P62",
	"res://tests/view/test_fog_layer.gd": "P62",
	"res://tests/view/test_health_bar_squads.gd": "P62",
	"res://tests/view/test_health_bars.gd": "P62",
	"res://tests/view/test_projectile_layer.gd": "P62",
	"res://tests/scenes/test_controls_flow.gd": "P62",
	"res://tests/ui/test_touch_probe.gd": "P63",
	"res://tests/ui/test_perf_arena_layout.gd": "P63",
	"res://tests/ui/test_perf_hud_card.gd": "P63",
}

## A window size assigned from a literal: `size = Vector2i(<digits>` or `set_size(Vector2i(<digits>`
## (also `window_set_size`). `content_scale_size` and `min_size` have no word boundary before
## `size`, and a comparison (`size == Vector2i(...)`) has a second `=`.
const LITERAL_WINDOW_SIZE: String = (
	r"\b(?:size\s*=\s*|(?:window_)?set_size\s*\(\s*)" + r"Vector2i\s*\(\s*\d"
)
## The whole list read, not one entry of it: `ScreenSizes.LANDSCAPE` not followed by `[`.
const LANDSCAPE_LIST: String = r"\bScreenSizes\.LANDSCAPE\b(?!\s*\[)"
const PROFILES_ALL: String = r"\bUiProfiles\.all\s*\("
const PORTRAIT_READ: String = r"\bScreenSizes\.(?:PORTRAIT|ALL)\b|\bUiProfiles\.portrait\s*\("

## One rule per kind of line: `name`, the `regex` applied to a line of code, the `fixtures` (lines
## it must flag) and the `clean` lines (lines it must leave alone).
const WINDOW_SIZE_RULE: Dictionary = {
	"name": "literal_window_size",
	"regex": LITERAL_WINDOW_SIZE,
	"fixtures":
	[
		"\tget_window().size = Vector2i(1280, 720)",
		"get_window().size = Vector2i(1600, 720)",
		"get_tree().root.size = Vector2i(2400, 1080)",
		"get_window().size=Vector2i(1000,700)",
		"\twindow.size = Vector2i( 2400 , 932 )",
		"get_window().set_size(Vector2i(1080, 2100))",
		"DisplayServer.window_set_size(Vector2i(720, 1280))",
	],
	"clean":
	[
		"get_window().size = ScreenSizes.LANDSCAPE[0]",
		"get_window().size = size",
		"get_window().size = metrics.window_size",
		"get_window().size = BASE_SIZE",
		"get_window().size = BASE_SIZE + Vector2i(320, 0)",
		'get_window().size = UiProfiles.by_name(&"web_phone").window_size',
		"get_window().set_size(size)",
		"if get_window().size == Vector2i(1000, 1000):",
		"get_window().content_scale_size = Vector2i(1000, 1000)",
		"var size: Vector2i = Vector2i(1000, 700)",
		"const WIDE_SIZE: Vector2i = Vector2i(1600, 720)",
		"_window_size_before = Vector2i(1000, 700)",
		"panel.min_size = Vector2i(1000, 700)",
		'UiMetrics.create("Android", 420, 1.0, 1.5, Vector2i(2424, 1080), Rect2i())',
	],
}
## A `Vector2i` literal that is one of the six sizes. Its regex is built from ScreenSizes.ALL, so
## the scan cannot drift from the list.
const RESTATED_FIXTURES: Array[String] = [
	"const BASE_SIZE: Vector2i = Vector2i(1280, 720)",
	"\tVector2i(2400, 1080),",
	"\tVector2i(2048, 1536): Vector2(640, 480),",
	"var pair: Array = [Vector2i(1080, 2400), Vector2i(720, 1280)]",
	"assert_that(size).is_equal(Vector2i(1536, 2048))",
	'var xhdpi: UiMetrics = UiMetrics.create("Android", 320, 1.0, 1.0, Vector2i(1280, 720), Rect2i())',
	"get_window().size = Vector2i(1280, 720)",
	"Vector2i(1280,720)",
	"Vector2i( 1280 , 720 )",
	"\tVector2i(\n1280, 720)",
]
const RESTATED_CLEAN: Array[String] = [
	"Vector2i(2424, 1080)",
	"Vector2i(12800, 720)",
	"Vector2i(1280, 7200)",
	"Vector2i(11280, 720)",
	"Vector2i(1280, 721)",
	"Vector2i(720, 1281)",
	"Vector2i(1000, 1000)",
	"Vector2i(1280, 720.0)",
	"Vector2(1280, 720)",
	"Vector2(2400, 1080)",
	"Vector2i(width, height)",
	"var size: Vector2i = ScreenSizes.ALL[1]",
	"const BASE_SIZE: Vector2i = ScreenSizes.LANDSCAPE[0]",
	"Rect2i(1280, 720, 100, 100)",
]
## Sources that `landscape_only` must flag, one text each.
const LANDSCAPE_ONLY_FIXTURES: Array[String] = [
	"for size: Vector2i in ScreenSizes.LANDSCAPE:\n\tget_window().size = size\n",
	"const TARGET_SIZES: Array[Vector2i] = ScreenSizes.LANDSCAPE\n",
	"for index: int in ScreenSizes.LANDSCAPE.size():\n\tpass\n",
	"for name: StringName in UiProfiles.all():\n\tpass\n",
	"var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()\n",
	'const PROFILES: Array[StringName] = [&"desktop", &"android_6in", &"web_tablet"]\n',
	'for profile: StringName in [&"desktop", &"android_6in"]:\n\tpass\n',
	'for profile: StringName in [&"android_6in", &"web_phone_small"]:\n\tpass\n',
	"for a in ScreenSizes.LANDSCAPE:\n\tpass\nvar one: Vector2i = ScreenSizes.LANDSCAPE[1]\n",
	'const PROFILES: Array = [["android_6in"], ["web_phone"]]\n',
	'const PROFILES: Array[String] = ["desktop", "web_tablet"]\n',
]
## Sources that it must leave alone.
const LANDSCAPE_ONLY_CLEAN: Array[String] = [
	"for size: Vector2i in ScreenSizes.ALL:\n\tpass\n",
	"for a in ScreenSizes.LANDSCAPE:\n\tpass\nfor b in ScreenSizes.PORTRAIT:\n\tpass\n",
	"var profiles: Dictionary = UiProfiles.all()\nprofiles.merge(UiProfiles.portrait())\n",
	"for a: Vector2i in ScreenSizes.LANDSCAPE:\n\tpass\nvar b: Vector2i = ScreenSizes.PORTRAIT[1]\n",
	"get_window().size = ScreenSizes.LANDSCAPE[1]\n",
	"const BASE_SIZE: Vector2i = ScreenSizes.LANDSCAPE[0]\n",
	'var phone: UiMetrics = UiProfiles.by_name(&"android_6in")\n',
	'for pair: Array in [[&"android_6in_portrait", &"android_6in", 32]]:\n\tpass\n',
	'var one: Array[StringName] = [&"desktop"]\n',
	'var both: Array[StringName] = [&"desktop_portrait", &"desktop"]\n',
	'const WIDTHS: Dictionary[String, float] = {"android_6in": 1600.0, "web_phone": 1854.0}\n',
	'const PROFILES: Array = [["android_6in"]]\n',
	'const PROFILES: Array = [["android_6in_portrait"], ["android_6in"]]\n',
	"# in ScreenSizes.LANDSCAPE:\n## UiProfiles.all()\nvar x: int = 1  # UiProfiles.all()\n",
	'var s: String = "x"\n',
]

var _rules: Array[Dictionary] = []  ## The line rules.
var _line_regexes: Array[RegEx] = []  ## One per entry of _rules.
var _sweeps: Array[RegEx] = []  ## What makes a suite sweep landscape sizes.
var _portrait_read: RegEx


func before() -> void:
	_rules = [WINDOW_SIZE_RULE, _restated_rule()]
	for rule: Dictionary in _rules:
		var regex: RegEx = RegEx.create_from_string(rule["regex"])
		assert_bool(regex.is_valid()).override_failure_message(str(rule["name"])).is_true()
		_line_regexes.append(regex)
	_sweeps = [
		RegEx.create_from_string(LANDSCAPE_LIST),
		RegEx.create_from_string(PROFILES_ALL),
		RegEx.create_from_string(_profile_pair_pattern()),
	]
	for sweep: RegEx in _sweeps:
		assert_bool(sweep.is_valid()).is_true()
	_portrait_read = RegEx.create_from_string(PORTRAIT_READ)
	assert_bool(_portrait_read.is_valid()).is_true()


func test_every_line_rule_flags_its_fixture_lines_and_leaves_its_clean_lines_alone() -> void:
	for rule: Dictionary in _rules:
		assert_array(rule["fixtures"]).override_failure_message(str(rule["name"])).is_not_empty()
		assert_array(rule["clean"]).override_failure_message(str(rule["name"])).is_not_empty()
		for line: String in rule["fixtures"]:
			var flagged: Array[String] = _rules_hit(line)
			var why: String = "%s must flag: %s" % [rule["name"], line]
			assert_array(flagged).override_failure_message(why).contains([rule["name"]])
		for line: String in rule["clean"]:
			var why: String = "%s must leave alone: %s" % [rule["name"], line]
			assert_array(_rules_hit(line)).override_failure_message(why).not_contains(
				[rule["name"]]
			)


## The restated-size rule reads each of the six sizes in both spacings, so a size that the list
## gains is caught without a change here.
func test_the_restated_size_rule_flags_each_size_of_the_list_however_it_is_spaced() -> void:
	assert_int(ScreenSizes.ALL.size()).is_equal(6)
	for size: Vector2i in ScreenSizes.ALL:
		for line: String in [
			"Vector2i(%d, %d)" % [size.x, size.y],
			"Vector2i(%d,%d)" % [size.x, size.y],
			"get_window().size = Vector2i( %d , %d )" % [size.x, size.y],
		]:
			var why: String = "restated_screen_size must flag: " + line
			assert_array(_rules_hit(line)).override_failure_message(why).contains(
				["restated_screen_size"]
			)
		var near: String = "Vector2i(%d, %d)" % [size.x + 1, size.y]  # Next to a size, not one.
		assert_array(_rules_hit(near)).override_failure_message(near).not_contains(
			["restated_screen_size"]
		)


func test_the_landscape_only_rule_flags_its_fixtures_and_leaves_the_clean_sources_alone() -> void:
	for source: String in LANDSCAPE_ONLY_FIXTURES:
		assert_bool(_landscape_only(source)).override_failure_message(source).is_true()
	for source: String in LANDSCAPE_ONLY_CLEAN:
		assert_bool(_landscape_only(source)).override_failure_message(source).is_false()


## A comment is not code, and a string is.
func test_the_scan_takes_comments_out_and_keeps_line_numbers() -> void:
	var source: String = (
		"# get_window().size = Vector2i(1280, 720)\n"
		+ "var a: int = 1  # Vector2i(2400, 1080)\n"
		+ "## Vector2i(2048, 1536)\n"
		+ 'var s: String = "# Vector2i(720, 1280)"\n'
		+ "get_window().size = Vector2i(1080, 2400)\n"
	)
	var hits: Array[String] = []
	for hit: Dictionary in _violations(FileScan.code_lines(source)):
		hits.append("%s@%d" % [hit["rule"], hit["line"]])
	(
		assert_array(hits)
		. is_equal(
			[
				"restated_screen_size@4",
				"literal_window_size@5",
				"restated_screen_size@5",
			]
		)
	)
	assert_bool(_landscape_only("# ScreenSizes.LANDSCAPE\n## UiProfiles.all()\n")).is_false()


func test_no_ui_or_layout_suite_spells_a_window_size_out() -> void:
	var problems: Array[String] = []
	for path: String in _scanned_files():
		var lines: PackedStringArray = FileScan.code_lines(FileAccess.get_file_as_string(path))
		for hit: Dictionary in _violations(lines):
			problems.append("%s:%d: %s" % [path, hit["line"], hit["rule"]])
	(
		assert_array(problems)
		. override_failure_message(
			(
				"A window size spelled out in a UI or layout suite (read ScreenSizes or a profile):\n%s"
				% "\n".join(problems)
			)
		)
		. is_empty()
	)


func test_no_suite_runs_landscape_sizes_only_unless_it_is_pending() -> void:
	var unlisted: Array[String] = []
	for path: String in _suites():
		if _landscape_only(FileAccess.get_file_as_string(path)) and not PORTRAIT_PENDING.has(path):
			unlisted.append(path)
	(
		assert_array(unlisted)
		. override_failure_message(
			(
				"A suite that runs only landscape sizes (read ScreenSizes.ALL, or add the portrait "
				+ (
					"sizes, or list it in PORTRAIT_PENDING with the row that does):\n%s"
					% "\n".join(unlisted)
				)
			)
		)
		. is_empty()
	)


func test_each_pending_entry_names_its_row_and_its_suite_has_no_portrait_size_yet() -> void:
	var suites: Array[String] = _suites()
	for path: String in PORTRAIT_PENDING:
		assert_array(suites).override_failure_message("not a suite: " + path).contains([path])
		var row: String = PORTRAIT_PENDING[path]
		assert_array(ROWS).override_failure_message("%s names %s" % [path, row]).contains([row])
		var source: String = FileAccess.get_file_as_string(path)
		var done: String = "%s reads a portrait size now: drop its entry (%s)" % [path, row]
		assert_bool(_covers_portrait(source)).override_failure_message(done).is_false()


## A scan that reads nothing passes everything.
func test_the_scan_reads_the_folders_and_suites_it_should() -> void:
	var files: Array[String] = _scanned_files()
	assert_int(files.size()).is_greater_equal(50)
	for path: String in [
		"res://tests/ui/test_ui_scale.gd",
		"res://tests/ui/test_army_bar.gd",
		"res://tests/scenes/test_main_scene.gd",
		"res://tests/view/test_rts_camera.gd",
		"res://tests/ui/support/arena_rig.gd",
		"res://tests/view/support/fog_rig.gd",
	]:
		assert_array(files).override_failure_message(path).contains([path])
	assert_array(files).not_contains(["res://tests/project/test_screen_sizes_scan.gd"])
	assert_array(files).not_contains(["res://tests/support/screen_sizes.gd"])
	var suites: Array[String] = _suites()
	assert_int(suites.size()).is_greater_equal(45)
	assert_array(suites).not_contains(["res://tests/ui/support/arena_rig.gd"])


## The list is ADR 0015 section 6: three landscape sizes, their three transposes, and all six.
func test_the_list_holds_the_six_sizes_of_adr_0015() -> void:
	var landscape: Array[Vector2i] = [
		Vector2i(1280, 720), Vector2i(2400, 1080), Vector2i(2048, 1536)
	]
	var portrait: Array[Vector2i] = [
		Vector2i(720, 1280), Vector2i(1080, 2400), Vector2i(1536, 2048)
	]
	assert_array(ScreenSizes.LANDSCAPE).is_equal(landscape)
	assert_array(ScreenSizes.PORTRAIT).is_equal(portrait)
	assert_array(ScreenSizes.ALL).is_equal(landscape + portrait)
	for index: int in landscape.size():  # PORTRAIT[i] is LANDSCAPE[i] turned.
		var size: Vector2i = ScreenSizes.LANDSCAPE[index]
		assert_that(ScreenSizes.PORTRAIT[index]).is_equal(Vector2i(size.y, size.x))
		assert_bool(UiScale.is_portrait_size(ScreenSizes.LANDSCAPE[index])).is_false()
		assert_bool(UiScale.is_portrait_size(ScreenSizes.PORTRAIT[index])).is_true()
	var distinct: Dictionary = {}
	for size: Vector2i in ScreenSizes.ALL:
		distinct[size] = true
	assert_int(distinct.size()).is_equal(6)


## The profiles that have a size in the list have that window, so a suite that reads one or the
## other gets the same screen.
func test_the_list_matches_the_windows_of_the_profiles_that_share_its_screens() -> void:
	var twins: Array[Array] = [
		[&"desktop", &"desktop_portrait"],
		[&"android_6in", &"android_6in_portrait"],
		[&"web_tablet", &"web_tablet_portrait"],
	]
	for index: int in twins.size():
		var landscape: UiMetrics = UiProfiles.by_name(twins[index][0])
		var portrait: UiMetrics = UiProfiles.by_name(twins[index][1])
		assert_that(landscape.window_size).is_equal(ScreenSizes.LANDSCAPE[index])
		assert_that(portrait.window_size).is_equal(ScreenSizes.PORTRAIT[index])


## The line rules applied to one line of code (a comment is not taken out here).
func _rules_hit(line: String) -> Array[String]:
	var names: Array[String] = []
	for hit: Dictionary in _violations(PackedStringArray([line])):
		names.append(hit["rule"])
	return names


## The violations of the line rules in `lines`: dictionaries with the `rule` and the `line`
## (counted from 1).
func _violations(lines: PackedStringArray) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for index: int in lines.size():
		for rule_index: int in _rules.size():
			if _line_regexes[rule_index].search(lines[index]) != null:
				found.append({"rule": _rules[rule_index]["name"], "line": index + 1})
	return found


## Whether a suite's `source` sweeps the landscape sizes and reads no portrait one.
func _landscape_only(source: String) -> bool:
	var code: String = "\n".join(FileScan.code_lines(source))
	var sweeps: bool = false
	for sweep: RegEx in _sweeps:
		sweeps = sweeps or sweep.search(code) != null
	return sweeps and not _covers_portrait(source)


func _covers_portrait(source: String) -> bool:
	return _portrait_read.search("\n".join(FileScan.code_lines(source))) != null


## The rule for a `Vector2i` literal that is one of the six sizes, from the list itself.
func _restated_rule() -> Dictionary:
	var sizes: PackedStringArray = PackedStringArray()
	for size: Vector2i in ScreenSizes.ALL:
		sizes.append("%d\\s*,\\s*%d" % [size.x, size.y])
	return {
		"name": "restated_screen_size",
		"regex": "\\bVector2i\\s*\\(\\s*(?:%s)\\s*\\)" % "|".join(sizes),
		"fixtures": RESTATED_FIXTURES,
		"clean": RESTATED_CLEAN,
	}


## Two landscape profiles named side by side in one list: `&"desktop", &"android_6in"`, the same in
## plain strings, or as one-name rows (`["android_6in"], ["web_phone"]`).
func _profile_pair_pattern() -> String:
	var names: PackedStringArray = PackedStringArray()
	for profile_name: StringName in UiProfiles.all():
		names.append(str(profile_name))
	var one: String = '&?"(?:%s)"' % "|".join(names)
	return one + "\\s*\\]?\\s*,\\s*\\[?\\s*" + one


## Every `.gd` file under the scanned folders, rigs included.
func _scanned_files() -> Array[String]:
	var files: Array[String] = []
	for dir: String in SCANNED_DIRS:
		files.append_array(FileScan.list_files(dir, ".gd"))
	return files


## The suites among them: a file named `test_*.gd`.
func _suites() -> Array[String]:
	var suites: Array[String] = []
	for path: String in _scanned_files():
		if path.get_file().begins_with("test_"):
			suites.append(path)
	return suites
