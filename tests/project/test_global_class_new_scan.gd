extends GdUnitTestSuite
## `GlobalClass.new` used as a value (a Callable, no call parentheses) must not appear in the game
## (P451). The web release template's GDScript analyzer finds no `new` member on a global class
## written like that ("Cannot find member "new" in base ..."): the script that holds it fails to
## compile in the export, so `MenuRoot.gd` could not load and the main menu was dead with any
## non-empty save. The editor, a desktop `godot --headless` run, a pack run with the editor binary
## and the web debug template all accept it, so no test that runs the code can see it; this source
## scan is what catches it. The call `GlobalClass.new()` is fine, and so is `.new` on a preloaded
## script constant (`const FooScript: GDScript = preload(...)`, then `FooScript.new`), which is how
## `MenuRoutesDefaults` registers its screens.
## Comments and string contents are taken out first. Gaps: a call split from its parentheses by a
## line break, and a global class reached through an alias variable.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const SCANNED_DIRS: Array[String] = ["res://game", "res://scenes", "res://tools"]
## An uppercase name that does not end in `Script` (the project's name for a preloaded script
## constant), `.new`, and no `(` after it.
const NEW_AS_VALUE: String = r"\b[A-Z]\w*(?<!Script)\.new\b(?!\s*\()"
const STRING_CONTENT: String = r'"[^"\n]*"'

## Lines the rule must flag and lines it must leave alone, so a rule that matches nothing fails.
const FLAGGED: Array[String] = [
	"\troutes.register(MenuRoutes.HOW_TO_PLAY, HowToPlayScreen.new)",
	"\tvar factory: Callable = MapSelect.new",
	"\tfactories.append(DpMinSize.new)",
]
const CLEAN: Array[String] = [
	"\tvar main: MainMenu = MainMenu.new()",
	"\troutes.register(MenuRoutes.HOW_TO_PLAY, HowToPlayScript.new)",
	"\tvar node := Sprite2D.new ()",
	'\tpush_warning("needs a standard Callable (X.new), not a lambda")',
]


func test_the_rule_flags_its_fixtures_and_spares_the_clean_lines() -> void:
	for line: String in FLAGGED:
		assert_bool(_hits(line)).override_failure_message("not flagged: " + line).is_true()
	for line: String in CLEAN:
		assert_bool(_hits(line)).override_failure_message("flagged: " + line).is_false()


func test_no_global_class_new_is_used_as_a_value() -> void:
	var found: Array[String] = []
	var scanned: int = 0
	for dir: String in SCANNED_DIRS:
		for path: String in FileScan.list_files(dir, ".gd"):
			scanned += 1
			var lines: PackedStringArray = FileScan.code_lines(FileAccess.get_file_as_string(path))
			for i: int in lines.size():
				if _hits(lines[i]):
					found.append("%s:%d: %s" % [path, i + 1, lines[i].strip_edges()])
	assert_int(scanned).is_greater(100)
	(
		assert_array(found)
		. override_failure_message(
			(
				"GlobalClass.new without () fails in the web release export (P451); use `ScriptConst.new`:\n"
				+ "\n".join(found)
			)
		)
		. is_empty()
	)


func _hits(line: String) -> bool:
	var regex: RegEx = RegEx.create_from_string(NEW_AS_VALUE)
	var strings: RegEx = RegEx.create_from_string(STRING_CONTENT)
	var code: String = strings.sub(line, '""', true)
	return regex.search(code) != null
