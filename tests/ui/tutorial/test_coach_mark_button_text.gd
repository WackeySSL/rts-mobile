extends "res://tests/ui/tutorial/support/coach_mark_suite.gd"
## The guide card's Skip and Next show their whole words (plan row P589b): a Button with an overrun
## mode drops its text from its minimum size, so the row once sized them to the 48 dp floor and the
## ellipsis cut them to "S" and "N". On a first card, at the six sizes and the two small real
## phones, every visible card button is as wide as its text plus its stylebox's margins and its text
## is not trimmed, unless it is stacked across the card and the text is truly longer than the card.

const LESSON_DIR: String = "res://data/tutorial/"
const EXTRA_PROFILES: Array[StringName] = [&"web_phone_small", &"web_phone_portrait"]


func _profiles() -> Array[UiMetrics]:
	var found: Array[UiMetrics] = []
	for size: Vector2i in ScreenSizes.ALL:
		found.append(_profile(size))
	for profile_name: StringName in EXTRA_PROFILES:
		found.append(UiProfiles.by_name(profile_name))
	return found


## The first card of lesson file `file_name`, anchored on the suite's own target.
func _first_beat(file_name: String) -> TutorialBeatDef:
	var lesson: TutorialLessonDef = load(LESSON_DIR + file_name) as TutorialLessonDef
	var beat: TutorialBeatDef = lesson.beats[0].duplicate() as TutorialBeatDef
	beat.delay_ticks = 0
	beat.after_ai_step = &""
	beat.pause = false
	beat.kind = NEXT  # A Next card, so Skip and Next both show.
	beat.anchor = TutorialBeatDef.Anchor.CONTROL
	beat.anchor_control = &"CoachTarget"
	return beat


## What is wrong with the visible card buttons now, one line each; `widths` collects their widths.
func _problems(label: String, widths: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var shown: int = 0
	for button_name: String in ["Skip", "Next"]:
		var button: Button = _mark.find_child(button_name, true, false) as Button
		if not button.is_visible_in_tree():
			continue
		shown += 1
		widths[button_name] = button.size.x
		var font: Font = button.get_theme_font(&"font")
		var text: float = (
			font
			. get_string_size(
				button.text,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				button.get_theme_font_size(&"font_size")
			)
			. x
		)
		var need: float = text + button.get_theme_stylebox(&"normal").get_minimum_size().x
		var tag: String = "%s %s" % [label, button_name]
		if need > button.size.x + TOLERANCE_PX and not button.clip_text:
			found.append(
				(
					"%s: text %.1f px and margins need %.1f, rect %.1f"
					% [tag, text, need, button.size.x]
				)
			)
		if button.clip_text and need <= _mark.card_rect().size.x:
			found.append("%s: trimmed though the text fits the card" % tag)
		if button.size.y < UiScale.dp(48.0) - TOLERANCE_PX:
			found.append("%s: under 48 dp tall" % tag)
	if shown < 2:
		found.append("%s: Skip and Next do not both show" % label)
	return found


func test_skip_and_next_show_their_whole_text_on_a_first_card_at_every_size() -> void:
	var names: PackedStringArray = DirAccess.get_files_at(LESSON_DIR)
	names.sort()
	var checked: int = 0
	var found: Array[String] = []
	for file_name: String in names:
		if (
			not file_name.ends_with(".tres")
			or file_name.contains("settings")
			or file_name.contains("text")
		):
			continue
		if not load(LESSON_DIR + file_name) is TutorialLessonDef:
			continue
		for profile: UiMetrics in _profiles():
			await _open(profile, _first_beat(file_name))
			var label: String = "%s %s" % [file_name, profile.window_size]
			found.append_array(_problems(label, {}))
			checked += 1
			_close()
	assert_int(checked).is_greater_equal(8 * 4)
	assert_array(found).override_failure_message("\n".join(found)).is_empty()


func test_the_strikes_lesson_first_card_in_portrait_sizes_skip_and_next_to_their_text() -> void:
	var profile: UiMetrics = UiProfiles.by_name(&"web_phone_portrait")
	await _open(profile, _first_beat("strikes.tres"))
	var widths: Dictionary = {}
	assert_array(_problems("strikes portrait", widths)).is_empty()
	print("P589b WIDTHS web_phone_portrait strikes: ", widths, " dp ", UiScale.dp(1.0))
	assert_float(float(widths["Skip"])).is_greater(UiScale.dp(48.0) + 1.0)
	assert_float(float(widths["Next"])).is_greater(UiScale.dp(48.0) + 1.0)
	_close()
