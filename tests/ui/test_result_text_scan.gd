extends GdUnitTestSuite
## P444: the result screen's player-facing text lives in `ResultText` and reaches the labels
## through `tr()`. A source scan: the only quoted literals left in `ResultScreen.gd` are internal
## ids (the result words the emblem, theme colour and sting key on, the `xp_view` dictionary keys,
## theme type and node names, theme constants, the tween property) and the debug warning.

const SCREEN_PATH: String = "res://game/ui/ResultScreen.gd"
## Quoted strings that are ids, never shown.
const ALLOWED: PackedStringArray = [
	"",
	"draw",
	"victory",
	"defeat",
	"value",
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
]


func _literals(path: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var quoted: RegEx = RegEx.create_from_string('"([^"\\\\]*)"')
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var code: String = line.strip_edges()
		if code.begins_with("#") or code.contains("push_warning(") or code.contains("preload("):
			continue
		var hash_at: int = code.find(" #")  # A trailing comment holds no literal.
		if hash_at >= 0:
			code = code.substr(0, hash_at)
		if code.contains("res://"):  # A resource path is not text.
			continue
		for hit: RegExMatch in quoted.search_all(code):
			found.append(hit.get_string(1))
	return found


func test_result_screen_has_no_player_facing_literal() -> void:
	for text: String in _literals(SCREEN_PATH):
		assert_bool(ALLOWED.has(text)).override_failure_message('literal "%s"' % text).is_true()


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
