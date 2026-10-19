extends GdUnitTestSuite
## The HUD's look lives in `game/ui/theme.tres` and nowhere else (plan row P58, Michael's decision
## of 2026-10-15: the game's look stays replaceable as a whole). A source scan over every `.gd`
## file in `game/ui` and over the `Hud` subtree of `scenes/main.tscn` fails on:
## - a Color literal: `Color(`, `Color8(`, `Color.` and a name (the constants such as
##   `Color.WHITE`, and `Color.from_hsv`, `Color.html`);
## - a colour by reference from `game/view`: `FeedbackStyle.OUTLINE` and `FeedbackStyle.FILL`;
## - a literal `modulate`, `self_modulate` or `color`, in code and as a scene key of the subtree;
## - a font: `FontFile`, `SystemFont`, `FontVariation`, a `.ttf`, `.otf`, `.woff`, `.woff2`, `.fnt`
##   or `.fontdata` path;
## - `LabelSettings`, the class and the `label_settings` scene key: a Label's own colour, font and
##   size, which the theme would not see;
## - a StyleBox made in code;
## - a theme override of a colour, font, font size or StyleBox, in code (`add_theme_*_override`,
##   or the `theme_override_*/` name given to `set`) and as a scene key (`theme_override_colors/`,
##   `_fonts/`, `_font_sizes/`, `_styles/`);
## - a Theme or a StyleBox written in code (`set_font_size`, `set_stylebox`, a content margin or a
##   corner radius setter), which only the dp step may do, on its scaled copy;
## - a colour or a font written in code (`set_color`, `set_font`): not even the dp step may. It
##   writes sizes, so its exception lists no such rule and a rule of this kind cannot be excepted.
## A constant override (`add_theme_constant_override`, `theme_override_constants/`) is layout,
## computed from the screen, and is allowed. The scan reads one line at a time, with the comments
## of a `.gd` file taken out first (a string stays: a font path is one). The developer scenes under
## `scenes/dev/` keep their own looks and are not scanned. A new `game/ui` script of a developer
## scene (`PerfHud.gd`, `perf_arena.gd`) is scanned like the others until it is listed in
## EXCEPTIONS with its reason. Every rule has fixture lines that it must flag, so a scan that
## matches nothing fails, and every exception must still be needed.
## Known gaps: a line scan sees no data flow. It does not flag a colour or a size that reaches a
## StyleBox through a variable (`style.bg_color = tint` on a box got from the theme), a Theme,
## StyleBox or Font loaded from another resource file, or a name computed at run time. They need a
## review of the diff, and a rule of their own once one is written.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const UI_DIR: String = "res://game/ui"
const MAIN_SCENE: String = "res://scenes/main.tscn"
const THEME_PATH: String = "res://game/ui/theme.tres"
const GD: String = "gd"
const TSCN: String = "tscn"

## A `modulate`, `self_modulate` or `color` (or one channel of it) set to a number, a string or a
## Color. A variable on the right is fine: the colour then comes from somewhere else.
const LITERAL_MODULATE: String = (
	r"\b(?:modulate|self_modulate|color)(?:\.[rgba])?\s*=(?!=)" + r"\s*(?:[-+]?\d|[\"']|Color\b)"
)
const THEME_WRITE: String = (
	r"\.(?:set_font_size|set_stylebox|set_content_margin(?:_all)?|"
	+ r"set_corner_radius(?:_all)?)\s*\("
)
## A colour or a font put into a Theme (or any other object) in code.
const LOOK_WRITE: String = r"\.(?:set_color|set_font)\s*\("
## A font class, or the path of a font file (a bitmap font is `.fnt`, a font made by the editor
## `.fontdata`).
const FONT_FILE: String = (
	r"\b(?:FontFile|SystemFont|FontVariation)\b|" + r"\.(?:ttf|otf|woff2?|fnt|fontdata)\b"
)

## One rule per kind of file it reads: `name`, `kind`, the `regex` applied to a line, and the
## `fixtures`, lines that it must flag.
const RULES: Array[Dictionary] = [
	{
		"name": "colour_literal",
		"kind": GD,
		"regex": r"\bColor8?\s*\(|\bColor\.[A-Za-z_]",
		"fixtures":
		[
			"const BACKGROUND: Color = Color(0.11, 0.13, 0.15)",
			"var c: Color = Color8(12, 34, 56)",
			"draw_circle(at, radius, Color.WHITE, false, 2.0)",
			"var c: Color = Color.from_hsv(0.5, 1.0, 1.0)",
			'var c: Color = Color.html("ff0000")',
			'const DARK: Color = Color("1C2127")',
		],
	},
	{
		"name": "colour_literal",
		"kind": TSCN,
		"regex": r"\bColor8?\s*\(|\bColor\.[A-Za-z_]",
		"fixtures": ["color = Color(0.1, 0.2, 0.3, 1)", "modulate = Color(1, 1, 1, 0.5)"],
	},
	{
		"name": "view_colour",
		"kind": GD,
		"regex": r"\bFeedbackStyle\.(?:OUTLINE|FILL)\b",
		"fixtures":
		[
			"draw_circle(anchor, radius, FeedbackStyle.FILL)",
			"draw_rect(line, FeedbackStyle.OUTLINE, false, 3.0, true)",
		],
	},
	{
		"name": "literal_modulate",
		"kind": GD,
		"regex": LITERAL_MODULATE,
		"fixtures":
		[
			"modulate = Color(1, 1, 1, 0.5)",
			"self_modulate.a = 0.5",
			"icon.color = Color.RED",
			"self_modulate = 1",
			'rect.modulate = "ff0000"',
		],
	},
	{
		"name": "literal_modulate",
		"kind": TSCN,
		"regex": r"^\s*(?:modulate|self_modulate|color)\s*=",
		"fixtures":
		["color = Color(0.1, 0.2, 0.3, 1)", "modulate = Color(1, 1, 1, 0.5)", "self_modulate = X"],
	},
	{
		"name": "font",
		"kind": GD,
		"regex": FONT_FILE,
		"fixtures":
		[
			"var font: FontFile = FontFile.new()",
			"var font: SystemFont = SystemFont.new()",
			"var font: FontVariation = FontVariation.new()",
			'var font: Font = load("res://assets/art/fonts/a.ttf")',
			'var font: Font = preload("res://assets/art/fonts/a.otf")',
			'var font: Font = load("res://assets/art/fonts/a.woff")',
			'var font: Font = load("res://assets/art/fonts/a.woff2")',
			'var font: Font = load("res://assets/art/fonts/a.fnt")',
			'var font: Font = load("res://assets/art/fonts/a.fontdata")',
		],
	},
	{
		"name": "font",
		"kind": TSCN,
		"regex": FONT_FILE,
		"fixtures":
		[
			'font = SubResource("FontVariation")',
			'theme_override_fonts/font = ExtResource("a") ; res://a.ttf',
			'font = ExtResource("a") ; res://assets/art/fonts/a.fnt',
		],
	},
	{
		"name": "label_settings",
		"kind": GD,
		"regex": r"\bLabelSettings\b|\blabel_settings\s*=(?!=)",
		"fixtures":
		[
			"var look: LabelSettings = LabelSettings.new()",
			"label.label_settings = look",
			"label_settings = null",
		],
	},
	{
		"name": "label_settings",
		"kind": TSCN,
		"regex": r"^\s*label_settings\s*=|\bLabelSettings\b",
		"fixtures": ['label_settings = SubResource("LabelSettings_a")', "label_settings = null"],
	},
	{
		"name": "stylebox_in_code",
		"kind": GD,
		"regex": r"\bStyleBox\w*\.new\b",
		"fixtures":
		[
			"var style: StyleBoxFlat = StyleBoxFlat.new()",
			"var style: StyleBoxTexture = StyleBoxTexture.new()",
			"var style: StyleBoxEmpty = StyleBoxEmpty.new()",
			"var style: StyleBoxLine = StyleBoxLine.new()",
		],
	},
	{
		"name": "theme_override",
		"kind": GD,
		"regex":
		(
			r"\badd_theme_(?:color|font|font_size|stylebox)_override\b|"
			+ r"\btheme_override_(?:colors|fonts|font_sizes|styles)/"
		),
		"fixtures":
		[
			'add_theme_color_override("font_color", tint)',
			'add_theme_font_override("font", font)',
			'add_theme_font_size_override("font_size", 18)',
			'add_theme_stylebox_override("panel", style)',
			'set("theme_override_font_sizes/font_size", 18)',
			'label.set("theme_override_colors/font_color", tint)',
		],
	},
	{
		"name": "theme_override",
		"kind": TSCN,
		"regex": r"^\s*theme_override_(?:colors|fonts|font_sizes|styles)/",
		"fixtures":
		[
			"theme_override_colors/font_color = X",
			"theme_override_fonts/font = X",
			"theme_override_font_sizes/font_size = 40",
			"theme_override_styles/panel = X",
		],
	},
	{
		"name": "theme_written_in_code",
		"kind": GD,
		"regex": THEME_WRITE,
		"fixtures":
		[
			'out.set_font_size("font_size", "Label", 28)',
			'out.set_stylebox("panel", "SelectionPanel", box)',
			"box.set_content_margin(SIDE_LEFT, 14.0)",
			"box.set_content_margin_all(14.0)",
			"flat.set_corner_radius(CORNER_TOP_LEFT, 14)",
			"flat.set_corner_radius_all(14)",
		],
	},
	{
		"name": "look_written_in_code",
		"kind": GD,
		"regex": LOOK_WRITE,
		"fixtures":
		[
			'out.set_color("font_color", "Label", tint)',
			'out.set_font("font", "Label", font)',
			'\tout.set_color(&"font_color", &"Label", out.get_color(&"outline", &"BoxOverlay"))',
			'\tout.set_font(&"font", &"Label", ThemeDB.fallback_font)',
			'theme.set_color (&"fill", &"BoxOverlay", tint)',
		],
	},
]
## Rules that no exception may list: the dp step writes sizes, never a look.
const NEVER_EXCEPTED: Array[String] = ["look_written_in_code"]
## Lines the theme allows, by kind: layout constants, a modulate from a variable, the theme's own
## entries and a type variation, and text that only looks like a rule inside a comment (`.gd`).
const CLEAN_GD: Array[String] = [
	'add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))',
	"layers[UnitLayer.TEAM_LAYER].modulate = tint",
	"modulate = tint",
	"if modulate == tint:",
	'colors[item] = get_theme_color(item, &"BoxOverlay")',
	"var colors: Dictionary[StringName, Color] = {}",
	"func show_type(id: StringName, label: String, number: int, tint: Color) -> void:",
	"var palette: PackedColorArray = PackedColorArray()",
	'theme_type_variation = &"NumberLabel"',
	'var font: Font = title.get_theme_font(&"font")',
	'var font_px: int = title.get_theme_font_size(&"font_size")',
	"# Color(1, 0, 0) and Color.WHITE and FontFile in a comment",
	"## FeedbackStyle.FILL, add_theme_font_size_override, StyleBoxFlat.new() in a doc comment",
	"var n: int = 3  # modulate = Color(1, 1, 1) and a .ttf path in a trailing comment",
	'var s: String = "#" + "x"',
	"var color_count: int = 3",
	"var ring_color: Color = tint",
	'const KEY: StringName = &"set_font_size"',
	"var node_color: int = 3",
	"var label_settings_count: int = 3",
	'add_theme_constant_override("outline_size", 2)',
	'const KEY: String = "theme_override_constants/separation"',
	"if label_settings == other:",
	"var font_name: String = path.get_file()",
	'theme.set_constant(&"separation", &"Box", 4)',
	'var tint: Color = out.get_color(&"fill", &"BoxOverlay")',
	'var font: Font = out.get_font(&"font", &"Label")',
	"func set_color_scheme(scheme: int) -> void:",
	'const KEY: StringName = &"set_color"',
]
const CLEAN_TSCN: Array[String] = [
	"theme_override_constants/separation = 8",
	'theme = ExtResource("16_theme")',
	'theme_type_variation = &"DevButton"',
	"mouse_filter = 2",
	"size_flags_horizontal = 0",
	'script = ExtResource("12_box")',
	'text = "Dev"',
	"anchor_right = 1.0",
	"colorful = 1",
	"label_text = 1",
]

## Files that may break a rule, each with the rules and the reason. The scan fails when one of the
## listed rules no longer finds anything in its file: an exception that is not needed goes.
const EXCEPTIONS: Dictionary[String, Dictionary] = {
	"res://game/ui/touch_probe.gd":
	{
		"rules": ["colour_literal", "theme_override"],
		"reason":
		(
			"The touch probe is a developer scene (scenes/dev/touch_probe.tscn) with its own look: "
			+ "BACKGROUND, TOUCH_FILL, its Color.WHITE touch rings and its dp font size override."
		),
	},
	"res://game/ui/HudTheme.gd":
	{
		"rules": ["theme_written_in_code"],
		"reason":
		(
			"The dp step writes font sizes, StyleBoxes and their margins and radii on the scaled "
			+ "copy of the theme (set_font_size, set_stylebox, the StyleBox setters). It sets no "
			+ "node override, no colour and no font: look_written_in_code is never excepted."
		),
	},
}

## What a comment or a string looks like, read from the left so that a comment hides the quote in
## it and a string hides the "#" in it. Group-free: the whole match is the token.
const TOKEN: String = (
	r'(?s)"""(?:[^\\]|\\.)*?"""|'
	+ r"'''(?:[^\\]|\\.)*?'''|"
	+ r'"(?:[^"\\]|\\.)*"|'
	+ r"'(?:[^'\\]|\\.)*'|"
	+ r"#[^\n]*"
)
const HUD_HEADER: String = '[node name="Hud" type="CanvasLayer" parent="."]'
## The header of a node of a scene: its name and, when there is one, its parent.
const NODE_HEADER: String = r'^\[node name="([^"]*)"(?:[^\]]*?\sparent="([^"]*)")?'

var _regexes: Array[RegEx] = []  ## One per entry of RULES.
var _token: RegEx
var _node_header: RegEx


func before() -> void:
	for rule: Dictionary in RULES:
		var regex: RegEx = RegEx.create_from_string(rule["regex"])
		assert_bool(regex.is_valid()).override_failure_message(str(rule["name"])).is_true()
		_regexes.append(regex)
	_token = RegEx.create_from_string(TOKEN)
	_node_header = RegEx.create_from_string(NODE_HEADER)


func test_every_rule_flags_each_of_its_fixture_lines() -> void:
	for rule: Dictionary in RULES:
		var fixtures: Array = rule["fixtures"]
		assert_array(fixtures).override_failure_message(str(rule["name"])).is_not_empty()
		for fixture: String in fixtures:
			var why: String = "%s (%s) must flag: %s" % [rule["name"], rule["kind"], fixture]
			assert_array(_rules_hit(fixture, rule["kind"])).override_failure_message(why).contains(
				[rule["name"]]
			)


func test_lines_the_theme_allows_are_not_flagged() -> void:
	for line: String in CLEAN_GD:
		assert_array(_rules_hit(line, GD)).override_failure_message(line).is_empty()
	for line: String in CLEAN_TSCN:
		assert_array(_rules_hit(line, TSCN)).override_failure_message(line).is_empty()


## A comment is not code, and a string is: a font path in a string is a font.
func test_the_scan_takes_comments_out_and_keeps_strings_and_line_numbers() -> void:
	var source: String = (
		'# Color.WHITE\nvar a: int = 1  # Color(1, 0, 0)\nvar s: String = "# not a comment"\n'
		+ 'var f: Font = load("res://a.ttf")  # ok\n"""\nColor.RED\n"""\n# last\n'
	)
	var lines: PackedStringArray = _code_lines(source)
	assert_int(lines.size()).is_equal(source.split("\n").size())
	assert_str(lines[0]).is_empty()
	assert_str(lines[1].strip_edges()).is_equal("var a: int = 1")
	assert_str(lines[2]).is_equal('var s: String = "# not a comment"')
	assert_str(lines[3].strip_edges()).is_equal('var f: Font = load("res://a.ttf")')
	var hits: Array[Dictionary] = _violations(source, GD)
	(
		assert_array(
			hits.map(func(hit: Dictionary) -> String: return "%s@%d" % [hit.rule, hit.line])
		)
		. is_equal(["font@4", "colour_literal@6"])
	)


## Only the nodes of the Hud and below are read, and a scene line keeps its number.
func test_the_scene_scan_reads_the_hud_subtree_and_nothing_else() -> void:
	var scene: String = (
		'[gd_scene format=3]\n\n[node name="Main" type="Node2D"]\ncolor = Color(1, 0, 0, 1)\n\n'
		+ '[node name="Tint" type="ColorRect" parent="."]\ncolor = Color(1, 0, 0, 1)\n\n'
		+ '[node name="Hud" type="CanvasLayer" parent="."]\n\n'
		+ '[node name="Bar" type="Control" parent="Hud"]\nmodulate = Color(1, 1, 1, 0.5)\n\n'
		+ '[node name="Button" type="Button" parent="Hud/Bar" node_paths=PackedStringArray("a")]\n'
		+ "theme_override_font_sizes/font_size = 40\n\n"
		+ '[node name="Hud2" type="Control" parent="."]\ncolor = Color(1, 0, 0, 1)\n\n'
		+ '[node name="Hud" type="Control" parent="Other"]\ncolor = Color(1, 0, 0, 1)\n\n'
		+ '[node name="Panel" type="Control" parent="Hud2/Hud"]\ncolor = Color(1, 0, 0, 1)\n\n'
		+ '[connection signal="x" from="Hud" to="." method="y"]\n'
	)
	var hits: Array[String] = []
	for hit: Dictionary in _violations(scene, TSCN):
		hits.append("%s@%d" % [hit["rule"], hit["line"]])
	(
		assert_array(hits)
		. is_equal(
			[
				"colour_literal@12",
				"literal_modulate@12",
				"theme_override@15",
			]
		)
	)
	assert_array(_hud_node_names(scene)).is_equal(["Hud", "Bar", "Button"])


func test_the_hud_look_is_in_the_theme_alone() -> void:
	var problems: Array[String] = []
	for path: String in _scanned_files():
		for hit: Dictionary in _unexcused(path, _scan(path)):
			problems.append("%s:%d: %s" % [path, hit["line"], hit["rule"]])
	(
		assert_array(problems)
		. override_failure_message(
			(
				"A colour, font, font size, StyleBox or override outside game/ui/theme.tres:\n%s"
				% "\n".join(problems)
			)
		)
		. is_empty()
	)


## A scan that reads nothing passes everything.
func test_the_scan_reads_the_scripts_and_the_hud_nodes_it_should() -> void:
	var files: Array[String] = _scanned_files()
	for script_name: String in [
		"SelectionPanel", "ArmyBar", "BoxOverlay", "HudTheme", "touch_probe"
	]:
		assert_array(files).contains(["%s/%s.gd" % [UI_DIR, script_name]])
	assert_array(files).contains([MAIN_SCENE])
	assert_int(files.size()).is_greater_equal(14)
	var names: Array[String] = _hud_node_names(FileAccess.get_file_as_string(MAIN_SCENE))
	for node_name: String in ["Hud", "BoxOverlay", "SafeArea", "DevButton", "ArmyBar"]:
		assert_array(names).contains([node_name])
	assert_array(names).contains(["SelectionPanel"])
	assert_array(names).not_contains(["MatchRunner", "UnitLayer", "MarkerLayer", "Camera"])
	# The subtree holds a theme on its roots and a variation on the Dev button: lines it reads.
	var scene: String = "\n".join(_hud_lines(FileAccess.get_file_as_string(MAIN_SCENE)))
	assert_str(scene).contains('theme = ExtResource("16_theme")')
	assert_str(scene).contains('theme_type_variation = &"DevButton"')


func test_each_exception_has_a_reason_and_is_still_needed() -> void:
	var known: Array[String] = []
	for rule: Dictionary in RULES:
		known.append(rule["name"])
	for path: String in EXCEPTIONS:
		var exception: Dictionary = EXCEPTIONS[path]
		assert_bool(FileAccess.file_exists(path)).override_failure_message(path).is_true()
		assert_str(exception["reason"]).override_failure_message(path).is_not_empty()
		var hit_rules: Array[String] = []
		for hit: Dictionary in _scan(path):
			hit_rules.append(hit["rule"])
		for rule: String in exception["rules"]:
			assert_array(known).override_failure_message(rule).contains([rule])
			assert_array(NEVER_EXCEPTED).override_failure_message(path).not_contains([rule])
			(
				assert_array(hit_rules)
				. override_failure_message(
					"%s no longer breaks %s: drop the exception" % [path, rule]
				)
				. contains([rule])
			)
		assert_array(exception["rules"]).is_not_empty()


## The dp step may write a size on its copy and nothing else: a colour or a font that it writes
## (the text colour, a font) is a violation of the look, whatever the exception for its sizes.
func test_the_dp_steps_exception_covers_its_sizes_and_never_a_colour_or_a_font() -> void:
	var path: String = "res://game/ui/HudTheme.gd"
	var source: String = FileAccess.get_file_as_string(path)
	assert_array(_unexcused(path, _violations(source, GD))).is_empty()
	var size_write: String = '\tout.set_font_size(&"font_size", &"Label", 28)'
	assert_array(_unexcused(path, _violations(source + "\n" + size_write, GD))).is_empty()
	for line: String in [
		'\tout.set_color(&"font_color", &"Label", out.get_color(&"outline", &"BoxOverlay"))',
		'\tout.set_font(&"font", &"Label", ThemeDB.fallback_font)',
	]:
		var rules: Array[String] = []
		for hit: Dictionary in _unexcused(path, _violations(source + "\n" + line, GD)):
			rules.append(hit["rule"])
		assert_array(rules).override_failure_message(line).is_equal(["look_written_in_code"])


## The project theme stays unset: it would restyle the developer scenes, which keep their looks.
## The HUD roots carry the theme instead (tests/ui/test_ui_theme.gd).
func test_the_project_sets_no_theme_and_the_hud_theme_is_a_theme_resource() -> void:
	assert_str(str(ProjectSettings.get_setting("gui/theme/custom", ""))).is_empty()
	assert_str(str(ProjectSettings.get_setting("gui/theme/custom_font", ""))).is_empty()
	assert_object(load(THEME_PATH)).is_instanceof(Theme)


## The scripts of game/ui and the main scene.
func _scanned_files() -> Array[String]:
	var files: Array[String] = FileScan.list_files(UI_DIR, ".gd")
	files.append(MAIN_SCENE)
	return files


## The violations of one file: its code, or the Hud subtree of a scene.
func _scan(path: String) -> Array[Dictionary]:
	var kind: String = TSCN if path.ends_with(".tscn") else GD
	return _violations(FileAccess.get_file_as_string(path), kind)


## The violations in `hits` of the file at `path` that none of its exceptions covers.
func _unexcused(path: String, hits: Array[Dictionary]) -> Array[Dictionary]:
	var allowed: Array = EXCEPTIONS.get(path, {}).get("rules", [])
	var found: Array[Dictionary] = []
	for hit: Dictionary in hits:
		if not allowed.has(hit["rule"]):
			found.append(hit)
	return found


## The violations in `text` of a `kind` of file: dictionaries with the `rule` and the `line`
## (counted from 1).
func _violations(text: String, kind: String) -> Array[Dictionary]:
	var lines: PackedStringArray = _code_lines(text) if kind == GD else _hud_lines(text)
	var found: Array[Dictionary] = []
	for index: int in lines.size():
		for rule_index: int in RULES.size():
			var rule: Dictionary = RULES[rule_index]
			if rule["kind"] == kind and _regexes[rule_index].search(lines[index]) != null:
				found.append({"rule": rule["name"], "line": index + 1})
	return found


## The rule names that flag `line`, as a line of a file of `kind`. A scene line is read as a line of
## a node of the Hud, the only nodes the scan reads.
func _rules_hit(line: String, kind: String) -> Array[String]:
	var names: Array[String] = []
	var text: String = line if kind == GD else HUD_HEADER + "\n" + line
	for hit: Dictionary in _violations(text, kind):
		names.append(hit["rule"])
	return names


## The lines of a script with its comments taken out. A string stays, and so does every line break.
func _code_lines(text: String) -> PackedStringArray:
	var out: String = ""
	var at: int = 0
	for token: RegExMatch in _token.search_all(text):
		out += text.substr(at, token.get_start() - at)
		if not token.get_string().begins_with("#"):
			out += token.get_string()
		at = token.get_end()
	return (out + text.substr(at)).split("\n")


## The lines of a scene that belong to the nodes of the Hud and below. Every other line is empty,
## so a line keeps its number.
func _hud_lines(scene: String) -> PackedStringArray:
	var kept: PackedStringArray = PackedStringArray()
	var inside: bool = false
	for line: String in scene.split("\n"):
		if line.begins_with("["):
			inside = _is_hud_node(line)
		kept.append(line if inside else "")
	return kept


func _is_hud_node(header: String) -> bool:
	var found: RegExMatch = _node_header.search(header)
	if found == null:
		return false  # A resource, a connection or the scene header.
	var node_name: String = found.get_string(1)
	var parent: String = found.get_string(2)
	return (node_name == "Hud" and parent == ".") or parent == "Hud" or parent.begins_with("Hud/")


func _hud_node_names(scene: String) -> Array[String]:
	var names: Array[String] = []
	for line: String in scene.split("\n"):
		if _is_hud_node(line):
			names.append(_node_header.search(line).get_string(1))
	return names
