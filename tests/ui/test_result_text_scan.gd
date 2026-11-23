extends GdUnitTestSuite
## P444: the result screen's player-facing text lives in `ResultText` and reaches the labels
## through `tr()`. A source scan of `ResultScreen.gd`: comments are cut quote-aware, the
## `preload`/`res://` paths and `push_warning`/`push_error` calls are removed (and only they; the
## rest of their line is still scanned), then every double or single quoted literal left must be an
## id (theme or node name, a result word), a `xp_view` key used as a dictionary key, or the tween
## property. A literal as the text argument of `add_label`/`add_button`, or in `.text = ...`, fails
## whatever it says (the empty string aside).

const SCREEN_PATH: String = "res://game/ui/ResultScreen.gd"
## Ids that are never shown, allowed anywhere.
const IDS: PackedStringArray = [
	"",
	"draw",
	"victory",
	"defeat",
	"CapsBigTitle",
	"CapsTitle",
	"NumberLabel",
	"Label",
	"XpBox",
	"XpBar",
	"RankUp",
	"PlayAgainButton",
	"BackButton",
	"ResultScreen",
	"separation",
	"h_separation",
	"integer_division",
	"*",
	"DpMinSize",
	"ui_cue",
	"ui_back",
]
## `xp_view`'s keys: allowed only as `"key":` or `["key"]`.
const DICT_KEYS: PackedStringArray = [
	"old",
	"total",
	"old_rank",
	"new_rank",
	"rank_up",
	"from_floor",
	"from_next",
	"floor",
	"next",
	"top",
]
const LITERAL: String = "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'"
const RES_PATH: String = "\"res://[^\"]*\"|'res://[^']*'"
const PUSH_CALL: String = (
	"push_(?:warning|error)\\(" + "(?:\"[^\"]*\"|'[^']*'|\\([^()]*\\)|[^()\"'])*\\)"
)
const TEXT_ARG: String = "add_(?:label|button)\\([^,]+,\\s*[\"'](?![\"'])"
const TEXT_SET: String = "\\.text\\s*=\\s*[\"'](?![\"'])"
const TWEEN_VALUE: String = "tween_property\\([^,]+,\\s*$"


## The problems found in `source`: each is the offending line.
static func scan(source: String) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var literal: RegEx = RegEx.create_from_string(LITERAL)
	var res_path: RegEx = RegEx.create_from_string(RES_PATH)
	var push_call: RegEx = RegEx.create_from_string(PUSH_CALL)
	var text_arg: RegEx = RegEx.create_from_string(TEXT_ARG)
	var text_set: RegEx = RegEx.create_from_string(TEXT_SET)
	var tween_value: RegEx = RegEx.create_from_string(TWEEN_VALUE)
	for raw: String in source.split("\n"):
		var code: String = _strip_comment(raw)
		code = push_call.sub(code, "0", true)
		code = res_path.sub(code, "0", true)
		if text_arg.search(code) != null or text_set.search(code) != null:
			problems.append(raw.strip_edges())
			continue
		for hit: RegExMatch in literal.search_all(code):
			var text: String = hit.get_string().substr(1, hit.get_string().length() - 2)
			var before: String = code.substr(0, hit.get_start())
			var after: String = code.substr(hit.get_end()).strip_edges()
			var is_key: bool = (
				after.begins_with(":") or (before.ends_with("[") and after.begins_with("]"))
			)
			var ok: bool = IDS.has(text)
			ok = ok or (DICT_KEYS.has(text) and is_key)
			ok = ok or (text == "value" and tween_value.search(before) != null)
			if not ok:
				problems.append(raw.strip_edges())
	return problems


## `line` up to a `#` that is not inside a string.
static func _strip_comment(line: String) -> String:
	var quote: String = ""
	var index: int = 0
	while index < line.length():
		var c: String = line[index]
		if quote != "":
			if c == "\\":
				index += 1
			elif c == quote:
				quote = ""
		elif c == '"' or c == "'":
			quote = c
		elif c == "#":
			return line.substr(0, index)
		index += 1
	return line


func test_result_screen_has_no_player_facing_literal() -> void:
	var problems: PackedStringArray = scan(FileAccess.get_file_as_string(SCREEN_PATH))
	assert_array(problems).override_failure_message("literals: %s" % [problems]).is_empty()


func test_the_scan_catches_planted_literals() -> void:
	for planted: String in [
		'add_label(x, "total", &"Label")',
		"add_button(row, 'Go', _go)",
		'_title.text = "Hello"',
		"_title.text = 'Hello'",
		'var a: String = "Rank #%d"',
		'var b: String = "total"',
		'var c: int = _view["Oops"]',
		"push_warning(\"x (%s)\" % error_string(e)); add('Oops')",
		'tween.tween_property(bar, "total", 1.0, 2.0)',
	]:
		assert_int(scan(planted).size()).override_failure_message(planted).is_equal(1)


func test_the_scan_passes_ids_keys_and_cut_parts() -> void:
	for fine: String in [
		'add_label(_grid, "", &"Label")',
		"_title.text = tr(ResultText.BACK)",
		'var d: Dictionary = {"old": 1, "next": 2}',
		'var e: int = _view["total"]',
		'fade.tween_property(bar, "value", 1.0, 2.0)',
		'const S: GDScript = preload("res://game/a.gd")',
		'push_warning("restart refused (%s)" % error_string(error))',
		'var f: int = 1  # "Hello" in a comment',
		"# 'Hello'",
		'var g: String = "draw" if x else "victory"  # "Rank #%d"',
	]:
		assert_array(scan(fine)).override_failure_message(fine).is_empty()


func test_every_key_has_english_text_and_the_screen_uses_it() -> void:
	var source: String = FileAccess.get_file_as_string(SCREEN_PATH)
	for key: StringName in ResultText.ENGLISH:
		assert_bool(ResultText.ENGLISH[key].is_empty()).is_false()
	for name: String in [
		"BACK",
		"PLAY_AGAIN",
		"RANK_UP",
		"MATCH_TIME",
		"YOU",
		"ENEMY",
		"PLAYER_N",
		"STAT_KEYS",
		"XP_GAINED",
		"RANK_LINE",
		"XP_TOTAL",
		"XP_PROGRESS",
		"title_key",
	]:
		assert_bool(source.contains("ResultText." + name)).override_failure_message(name).is_true()


func test_the_table_holds_the_unchanged_english_words() -> void:
	ResultText.register()
	assert_str(tr(ResultText.PLAY_AGAIN)).is_equal("PLAY AGAIN")
	assert_str(tr(ResultText.title_key("victory"))).is_equal("VICTORY")
	assert_str(tr(ResultText.title_key("defeat"))).is_equal("DEFEAT")
	assert_str(tr(ResultText.title_key("draw"))).is_equal("DRAW")
	(
		assert_array(
			ResultText.STAT_KEYS.map(func(k: StringName) -> String: return ResultText.ENGLISH[k])
		)
		. is_equal(["Units built", "Units lost", "Buildings lost", "Credits harvested"])
	)
