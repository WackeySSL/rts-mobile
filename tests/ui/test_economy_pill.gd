extends GdUnitTestSuite
## The economy pill (plan P119, ADR 0025 section 3), read from crafted snapshots in the main scene:
## the credits and the power bar of the local player, the low-power look (a word, a shape and a
## colour), the fixed digit slots, the tap areas and the pill's place at the six sizes and after a
## turn. The match is paused, so only the snapshots a test writes are on show, and the Commands the
## player controller would send are caught: reading the numbers sends none. Where the pill stands
## among the other parts is test_hud_corners.gd's, and the build menu's layout is its own suites'.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ICONS: String = "res://assets/art/svg/icons/%s.svg"
## Another player's numbers sit beside the local player's (player 1): a read of the wrong index
## shows them.
const OTHER_CREDITS: int = 9000
const OTHER_POWER: int = 777
## WCAG 2.1 AA: 4.5 for text, 3 for large text (18 pt or 14 pt bold).
const AA_TEXT: float = 4.5
const AA_LARGE_TEXT: float = 3.0

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _pill: EconomyPill
var _controller: PlayerController
var _sent: Array[Command] = []
var _tick: int = 0


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()


## The menu's slide is off for the test (tests/support/menu_rig.gd).
func before_test() -> void:
	MenuRig.begin()


func test_it_shows_the_local_players_credits_and_power_and_nobody_elses() -> void:
	await _open()
	_publish(1500, 100, 40)
	assert_str(_credits().text).is_equal("1500")
	var bar: ProgressBar = _node("PowerBar")
	assert_float(bar.max_value).is_equal(100.0)
	assert_float(bar.value).is_equal(40.0)
	assert_str(_numbers().text).is_equal("40/100")
	assert_bool(_low()).is_false()
	var other: ScenarioDef = _runner.scenario.duplicate() as ScenarioDef  # The file stays as it is.
	other.local_player = 2
	_runner.scenario = other
	_publish(1500, 100, 40)
	assert_str(_credits().text).is_equal(str(OTHER_CREDITS))
	assert_float(bar.value).is_equal(float(OTHER_POWER))  # Used 777 against 777 made: full.
	assert_bool(_low()).is_false()
	assert_array(_sent).is_empty()


## Low power is more used than made (ADR 0018 section 4), and the bar says so with a shape as well
## as with a colour: the warning triangle for the bolt, and the red bar, full.
func test_low_power_is_more_used_than_made_and_shows_a_triangle_and_a_full_bar() -> void:
	await _open()
	_publish(0, 100, 100)  # Exactly enough is not low.
	assert_bool(_low()).is_false()
	assert_float((_node("PowerBar") as ProgressBar).value).is_equal(100.0)
	_publish(0, 100, 101)
	assert_bool(_low()).is_true()
	assert_str(_glyph("PowerGlyph")).is_equal(ICONS % "glyph_low_power")
	assert_str(str((_node("PowerBar") as Control).theme_type_variation)).is_equal("PowerBarLow")
	assert_str(str(_pill.theme_type_variation)).is_equal("EconomyPillLow")  # The red edge.
	assert_float((_node("PowerBar") as ProgressBar).value).is_equal(100.0)
	assert_str(_numbers().text).is_equal("101/100")
	_publish(0, 0, 5)  # Nothing made at all: full, with a bar that can hold it.
	assert_bool(_low()).is_true()
	assert_float((_node("PowerBar") as ProgressBar).value).is_equal(
		(_node("PowerBar") as ProgressBar).max_value
	)
	_publish(0, 100, 30)  # Power back: the look goes back with it.
	assert_bool(_low()).is_false()
	assert_str(_glyph("PowerGlyph")).is_equal(ICONS % "glyph_power")
	assert_str(str((_node("PowerBar") as Control).theme_type_variation)).is_equal("PowerBar")
	assert_str(str(_pill.theme_type_variation)).is_equal("EconomyPill")
	assert_float((_node("PowerBar") as ProgressBar).value).is_equal(30.0)


func test_a_player_with_no_buildings_has_an_empty_bar_that_is_not_low() -> void:
	await _open()
	_publish(2000, 0, 0)
	assert_bool(_low()).is_false()
	assert_float((_node("PowerBar") as ProgressBar).value).is_equal(0.0)
	assert_str(_numbers().text).is_equal("0/0")


func test_the_glyphs_have_their_icons_and_their_tints_from_the_theme() -> void:
	await _open()
	_publish(0, 100, 40)
	assert_str(_glyph("CreditsGlyph")).is_equal(ICONS % "glyph_credits")
	assert_str(_glyph("PowerGlyph")).is_equal(ICONS % "glyph_power")
	var money: Color = _pill.get_theme_color(&"money", &"HudTokens")
	var danger: Color = _pill.get_theme_color(&"danger", &"HudTokens")
	assert_that((_node("CreditsGlyph") as Control).modulate).is_equal(money)
	assert_that((_node("PowerGlyph") as Control).modulate).is_equal(money)
	_publish(0, 100, 140)
	assert_that((_node("PowerGlyph") as Control).modulate).is_equal(danger)
	assert_that(money).is_not_equal(danger)
	assert_that(_pill.get_theme_stylebox(&"panel", &"EconomyPillLow")).is_not_equal(
		_pill.get_theme_stylebox(&"panel", &"EconomyPill")
	)
	var edge: StyleBoxFlat = _pill.get_theme_stylebox(&"panel", &"EconomyPillLow") as StyleBoxFlat
	assert_that(edge.border_color).is_equal(danger)
	(
		assert_that((_node("PowerBar") as ProgressBar).get_theme_stylebox(&"fill") as StyleBoxFlat)
		. is_not_null()
	)
	var fill: StyleBoxFlat = (
		(_node("PowerBar") as Control).get_theme_stylebox(&"fill") as StyleBoxFlat
	)
	assert_that(fill.bg_color).is_equal(danger)  # The bar turns danger red too.


## Low power is a word as well: "LOW POWER" takes the numbers' place in the bar, and the numbers
## come back with the power. The bar (and with it the pill, as far as the layout has room) is wide
## enough for the word at every profile of both orientations.
func test_low_power_shows_the_word_in_the_bar_at_every_size() -> void:
	await _open()
	var word: Label = _node("PowerWord")
	assert_bool(word.uppercase).is_true()
	assert_str(word.text.to_upper()).is_equal("LOW POWER")
	for profile: StringName in _every_profile():
		await _turn(profile)
		_publish(0, 6, 4)
		await await_idle_frame()
		var rest: float = _pill.size.x
		assert_bool(word.visible).override_failure_message(str(profile)).is_false()
		_publish(0, 6, 9)
		await await_idle_frame()
		await await_idle_frame()
		var room: float = _rect("PowerBar").size.x - 2.0 * UiScale.dp(2.0)
		var why: String = "%s: word %s in a bar of %s" % [profile, word.size.x, room]
		if (
			_pill.size.x >= UiScale.dp(HudCorners.PILL_MAX_DP) - 0.5
			and (word.get_combined_minimum_size().x > room)
		):
			# The pill is at its 320 dp cap and the menu button (P124) took the bar's room: the word
			# drops, as ADR 0025 section 3 has it; the triangle and the red edge speak alone.
			assert_bool(word.visible).override_failure_message(why).is_false()
			_publish(0, 6, 4)
			await await_idle_frame()
			continue
		assert_bool(word.visible).override_failure_message(why).is_true()
		assert_bool(_node("PowerText").visible).is_false()  # The word has the place.
		var needs: float = word.get_combined_minimum_size().x
		assert_float(needs).override_failure_message(why).is_less_equal(room)
		assert_float(_pill.size.x).is_greater_equal(rest)  # The pill grew for it, never shrank.
		var safe: Rect2 = SafeAreaMargin.rect_inside(
			get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
		)
		var inside: bool = safe.grow(0.5).encloses(_pill.get_global_rect())
		assert_bool(inside).override_failure_message(why).is_true()
		_publish(0, 6, 4)
		await await_idle_frame()
		await await_idle_frame()
		assert_bool(word.visible).override_failure_message(str(profile)).is_false()
		assert_bool(_node("PowerText").visible).override_failure_message(str(profile)).is_true()
		assert_float(_pill.size.x).is_equal_approx(rest, 0.5)  # And back to its width.


## The numbers are the pill's to show (ADR 0025 section 2: the pill is as wide as its content and
## the bar takes what is left): the pill asks the layout for the width they need beyond its least,
## so the numbers of a first power plant, "120/200", show on the 6-inch phone sideways and upright,
## on the web phone and on the tablet, in a pill wider than its 200 dp least.
func test_the_numbers_of_a_power_plant_show_where_the_layout_has_room_for_them() -> void:
	await _open()
	for profile: StringName in [
		&"android_6in", &"android_6in_portrait", &"web_phone", &"web_tablet"
	]:
		await _turn(profile)
		_publish(2000, 200, 120)
		await await_idle_frame()
		await await_idle_frame()
		var text: Control = _node("PowerText")
		var why: String = "%s: numbers %s, bar %s" % [profile, text.size, _rect("PowerBar")]
		assert_bool(text.visible).override_failure_message(why).is_true()
		assert_str(_numbers().text).is_equal("120/200")
		assert_bool(_rect("PowerBar").grow(0.5).encloses(text.get_global_rect())).is_true()
		assert_bool(_node("PowerWord").visible).is_false()
		assert_float(_pill.size.x).override_failure_message(why).is_greater(UiScale.dp(200.0) + 2.0)
		assert_float(_pill.size.x).is_less_equal(UiScale.dp(HudCorners.PILL_MAX_DP) + 0.5)


## Where the layout has no room the numbers drop (and then the word; the triangle and the red edge
## stay), and the pill never reaches the scope's corner: on the narrowest portrait screen (360 dp,
## the pill in the corner) it ends at least 64 dp before the safe rect's end, normal and on
## low power, with the menu button shown or not, and is 48 dp high.
func test_on_the_narrowest_portrait_the_pill_ends_before_the_scopes_corner() -> void:
	await _open()
	await _turn(&"web_phone_portrait")
	var states: Array[Vector3i] = [Vector3i(2000, 200, 120), Vector3i(2000, 6, 9)]
	states.append(Vector3i(99999, 99999, 79999))
	for menu: bool in [false, true]:
		_pill.set_menu_shown(menu)
		for state: Vector3i in states:
			_publish(state.x, state.y, state.z)
			await await_idle_frame()
			await await_idle_frame()
			var dp: float = UiScale.base_px_per_dp()
			var safe: Rect2 = SafeAreaMargin.rect_inside(
				get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
			)
			var rect: Rect2 = _pill.get_global_rect()
			var why: String = "menu %s, %s: pill %s, safe %s" % [menu, state, rect, safe]
			assert_float(rect.end.x).override_failure_message(why).is_less_equal(
				safe.end.x - 64.0 * dp + 0.5
			)
			assert_bool(safe.grow(0.5).encloses(rect)).override_failure_message(why).is_true()
			assert_float(rect.size.y / dp).override_failure_message(why).is_between(47.5, 49.0)
			assert_bool(_low()).override_failure_message(why).is_equal(state.y < state.z)
			for text: String in ["PowerText", "PowerWord"]:  # What shows fits the bar.
				var part: Control = _node(text)
				if part.visible:
					var inside: bool = _rect("PowerBar").grow(0.5).encloses(part.get_global_rect())
					assert_bool(inside).override_failure_message(why + text).is_true()


## A turn changes the bar's width without a new snapshot, so the bar's own `resized` makes the
## numbers follow it (a container sorts a frame after the handlers). At every profile the numbers
## show exactly where they fit the bar.
func test_the_numbers_follow_the_bar_when_a_turn_changes_its_width() -> void:
	await _open()
	var shown: Dictionary[bool, int] = {true: 0, false: 0}
	for profile: StringName in _every_profile():
		await _turn(profile)
		for made: int in [60, 99999]:
			_publish(2000, made, made - 20)
			await await_idle_frame()
			var text: Control = _node("PowerText")
			var fits: bool = (
				text.get_combined_minimum_size().x + 2.0 * UiScale.dp(EconomyPill.TEXT_PAD_DP)
				<= ((_node("PowerBar") as Control).size.x)
			)
			(
				assert_bool(text.visible)
				. override_failure_message("%s, %d made" % [profile, made])
				. is_equal(fits)
			)
			shown[text.visible] += 1
	assert_int(shown[true]).is_greater(0)  # Not vacuous: some bars hold the numbers, some not.
	assert_int(shown[false]).is_greater(0)  # The 360 dp portrait has no room for 11 digits.


## The numbers are in the middle of the bar, not hanging from its top: a line of text is taller
## than the bar's inside, so a label that grew only downwards rested on the bottom border. Their
## rect is inside the bar's and has the same centre, in both states and on every screen; on low
## power the word has the same place.
func test_the_numbers_and_the_word_sit_inside_the_bar_and_centred_in_it_at_every_size() -> void:
	await _open()
	for profile: StringName in _every_profile():
		await _turn(profile)
		for used: int in [4, 9]:  # Of 6 made: power to spare, then low power.
			_publish(2000, 6, used)
			await await_idle_frame()
			await await_idle_frame()
			var why: String = "%s, %d/6 (%s)" % [profile, used, get_window().size]
			var shown: Control = _node("PowerText" if used < 6 else "PowerWord")
			assert_bool(shown.visible).override_failure_message(why + ": hidden").is_true()
			var bar: Rect2 = _rect("PowerBar")
			var rect: Rect2 = shown.get_global_rect()
			var inside: String = "%s: %s in the bar %s" % [why, rect, bar]
			assert_bool(bar.grow(0.5).encloses(rect)).override_failure_message(inside).is_true()
			var off: float = absf(rect.get_center().y - bar.get_center().y)
			var centred: String = "%s: %s px off the bar's middle" % [why, off]
			assert_float(off).override_failure_message(centred).is_less_equal(UiScale.dp(1.0))


## The numbers' colours are the theme's and read against what is under them (WCAG): on the danger
## red of low power the bar is full, so all of the text is on red and is dark; on the green bar the
## text crosses the fill and the dark track, so it is white with a dark edge that reads on both.
func test_the_numbers_read_on_the_red_and_on_the_green() -> void:
	await _open()
	var bar: ProgressBar = _node("PowerBar")
	_publish(0, 100, 130)
	var red: Color = (bar.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color
	var dark: Color = _pill.get_theme_color(&"font_color", &"PowerNumberLow")
	assert_float(_contrast(dark, red)).is_greater_equal(AA_TEXT)
	assert_float(_pill.get_theme_color(&"font_outline_color", &"PowerNumberLow").a).is_equal(0.0)
	var word: Color = _pill.get_theme_color(&"font_color", &"PillWord")
	assert_float(_contrast(word, red)).is_greater_equal(AA_TEXT)  # The word is on the red too.
	_publish(0, 100, 40)
	var green: Color = (bar.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color
	var track: Color = (bar.get_theme_stylebox(&"background") as StyleBoxFlat).bg_color
	var white: Color = _pill.get_theme_color(&"font_color", &"PowerNumber")
	var edge: Color = _pill.get_theme_color(&"font_outline_color", &"PowerNumber")
	assert_that(green).is_not_equal(red)  # The look did change with the state.
	assert_float(_contrast(white, green)).is_greater_equal(AA_LARGE_TEXT)
	assert_float(_contrast(white, track)).is_greater_equal(AA_TEXT)
	assert_float(_contrast(edge, white)).is_greater_equal(AA_TEXT)
	assert_float(_contrast(edge, green)).is_greater_equal(AA_TEXT)
	assert_float(edge.a).is_equal(1.0)
	var digit: Label = _numbers().get_child(0) as Label  # The edge size is in dp, set per label.
	assert_int(digit.get_theme_constant(&"outline_size")).is_greater_equal(1)
	assert_str(str(digit.theme_type_variation)).is_equal("PowerNumber")


## The credits keep one width, so the bar does not move when they gain or lose a digit.
func test_the_bar_does_not_move_when_the_credits_gain_a_digit() -> void:
	await _open()
	for profile: StringName in [&"android_6in", &"web_tablet", &"android_6in_portrait"]:
		await _turn(profile)
		for pair: Vector2i in [
			Vector2i(999, 1000), Vector2i(9999, 10000), Vector2i(1, 99999), Vector2i(0, 12345)
		]:
			_publish(pair.x, 100, 40)
			await await_idle_frame()
			var before: Dictionary[String, Rect2] = _status_rects()
			_publish(pair.y, 100, 40)
			await await_idle_frame()
			assert_str(_credits().text).is_equal(str(pair.y))  # The number did change.
			var after: Dictionary[String, Rect2] = _status_rects()
			for node_name: String in before:
				var why: String = "%s: %s from %d to %d" % [profile, node_name, pair.x, pair.y]
				assert_that(after[node_name]).override_failure_message(why).is_equal(
					before[node_name]
				)


func test_a_snapshot_without_player_columns_shows_zeros() -> void:
	await _open()
	_runner.snapshot = MatchSnapshot.new()
	_pill.refresh()
	assert_str(_credits().text).is_equal("0")
	assert_str(_numbers().text).is_equal("0/0")
	_pill.runner = null  # No match at all: nothing is read, nothing breaks.
	_pill.refresh()
	await await_idle_frame()
	assert_str(_credits().text).is_equal("0")


## A frame reads a snapshot once: a new tick is read, the same tick again is not.
func test_a_new_tick_is_read_on_the_next_frame_and_the_same_one_is_not_read_again() -> void:
	await _open()
	var snap: MatchSnapshot = _craft(1200, 100, 10)
	_runner.snapshot = snap
	await await_idle_frame()
	assert_str(_credits().text).is_equal("1200")
	snap.credits[1] = 1300  # A published snapshot is never written; this one would go unseen.
	await await_idle_frame()
	assert_str(_credits().text).is_equal("1200")
	var next: MatchSnapshot = _craft(1300, 100, 10)
	next.tick = snap.tick + 1
	_runner.snapshot = next
	await await_idle_frame()
	assert_str(_credits().text).is_equal("1300")
	var again: MatchSnapshot = _craft(50, 100, 10)  # A new match starts again at tick 0.
	again.match_serial = next.match_serial + 1
	again.tick = next.tick
	_runner.snapshot = again
	await await_idle_frame()
	assert_str(_credits().text).is_equal("50")


## The pulse runs in a match: a published low-power tick read by `refresh()` and then plain frames
## (`_process`, the engine's path, not `_pulse`) breathe the pill and the triangle, and enough
## power brings them back to full (plan P89).
func test_the_pulse_runs_from_the_frame_loop_on_low_power_and_stops_when_power_is_enough() -> void:
	await _open()
	_runner.snapshot = _craft(1000, 60, 100)
	_pill.refresh()
	_pill._process(0.7)  # Half a period: the dimmest step.
	assert_int(_pill.pulse_step()).is_greater(0)
	assert_float(_pill.self_modulate.a).is_less(1.0)
	assert_float((_node("PowerGlyph") as TextureRect).self_modulate.a).is_less(1.0)
	_runner.snapshot = _craft(1000, 100, 40)
	_pill.refresh()
	_pill._process(0.016)
	assert_int(_pill.pulse_step()).is_equal(0)
	assert_float(_pill.self_modulate.a).is_equal(1.0)


## The numbers of one crafted tick: three players' columns, the local player's in index 1.
func _craft(credits: int, made: int, used: int) -> MatchSnapshot:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.credits = PackedInt32Array([0, credits, OTHER_CREDITS])
	snap.power_made = PackedInt32Array([0, made, OTHER_POWER])
	snap.power_used = PackedInt32Array([0, used, OTHER_POWER])
	_tick += 1
	snap.tick = _tick
	return snap


## Publishes a crafted tick and reads it at once. A fall in the credits counts down for
## `economy_flash_ms` (P119b, test_economy_flash.gd), so the time passes here: the number shows at
## once, as these tests read it.
func _publish(credits: int, made: int, used: int) -> void:
	_runner.snapshot = _craft(credits, made, used)
	_pill.refresh()
	_pill._process(10.0)


## The rects of the pill's pieces, by name.
func _status_rects() -> Dictionary[String, Rect2]:
	var rects: Dictionary[String, Rect2] = {}
	for node_name: String in ["CreditsGlyph", "Credits", "PowerGlyph", "PowerBar"]:
		rects[node_name] = _rect(node_name)
	return rects


func _rect(node_name: String) -> Rect2:
	return (_node(node_name) as Control).get_global_rect()


## Every device profile, landscape and then portrait.
func _every_profile() -> Array[StringName]:
	var names: Array[StringName] = []
	for profile: StringName in UiProfiles.all():
		names.append(profile)
	for profile: StringName in UiProfiles.portrait():
		names.append(profile)
	return names


## WCAG 2.1 relative luminance of an sRGB colour.
static func _luminance(color: Color) -> float:
	var linear: Array[float] = []
	for channel: float in [color.r, color.g, color.b]:
		linear.append(
			channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)
		)
	return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


## WCAG 2.1 contrast ratio of two colours, 1 to 21.
static func _contrast(first: Color, second: Color) -> float:
	var light: float = maxf(_luminance(first), _luminance(second))
	var dark: float = minf(_luminance(first), _luminance(second))
	return (light + 0.05) / (dark + 0.05)


func _low() -> bool:
	return _glyph("PowerGlyph") == ICONS % "glyph_low_power"


func _glyph(node_name: String) -> String:
	return (_node(node_name) as TextureRect).texture.resource_path


func _credits() -> DigitRow:
	return _node("Credits")


func _numbers() -> DigitRow:
	return _node("PowerText")


## By name from the HUD.
func _node(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


## Turns the window to a profile's size, with its metrics, and lets the handlers and the
## containers settle: a turn runs its handlers twice and the containers sort a frame later.
func _turn(profile_name: StringName) -> void:
	var metrics: UiMetrics = UiProfiles.by_name(profile_name)
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	await await_idle_frame()


## A new main scene on the 6-inch phone, its match paused, with the Commands caught.
func _open() -> void:
	var metrics: UiMetrics = UiProfiles.by_name(&"android_6in")
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	_runner = _main.get_node("MatchRunner")
	_pill = _main.get_node("Hud/EconomyPill")
	_controller = _main.get_node("PlayerController")
	_sent.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
