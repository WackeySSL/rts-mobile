extends GdUnitTestSuite
## The build sidebar's credits line and power bar (plan P85c, ADR 0019 section 1), read from
## crafted snapshots in the main scene. The match is paused, so only the snapshots a test writes
## are on show, and the Commands the player controller would send are caught: reading the numbers
## sends none. The zone and the layout are in test_build_sidebar_layout.

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
var _sidebar: BuildSidebar
var _controller: PlayerController
var _sent: Array[Command] = []
var _tick: int = 0


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()


func test_it_shows_the_local_players_credits_and_power_and_nobody_elses() -> void:
	await _open()
	_publish(1500, 100, 40)
	assert_str(_credits().text).is_equal("1500")
	var bar: ProgressBar = _node("PowerBar")
	assert_float(bar.max_value).is_equal(100.0)
	assert_float(bar.value).is_equal(40.0)
	assert_str((_node("PowerText") as Label).text).is_equal("40/100")
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
## as with a colour: the warning triangle for the bolt, and the amber bar, full.
func test_low_power_is_more_used_than_made_and_shows_a_triangle_and_a_full_bar() -> void:
	await _open()
	_publish(0, 100, 100)  # Exactly enough is not low.
	assert_bool(_low()).is_false()
	assert_float((_node("PowerBar") as ProgressBar).value).is_equal(100.0)
	_publish(0, 100, 101)
	assert_bool(_low()).is_true()
	assert_str(_glyph("PowerGlyph")).is_equal(ICONS % "glyph_low_power")
	assert_str(str((_node("PowerBar") as Control).theme_type_variation)).is_equal("PowerBarLow")
	assert_float((_node("PowerBar") as ProgressBar).value).is_equal(100.0)
	assert_str((_node("PowerText") as Label).text).is_equal("101/100")
	_publish(0, 0, 5)  # Nothing made at all: full, with a bar that can hold it.
	assert_bool(_low()).is_true()
	assert_float((_node("PowerBar") as ProgressBar).value).is_equal(
		(_node("PowerBar") as ProgressBar).max_value
	)
	_publish(0, 100, 30)  # Power back: the look goes back with it.
	assert_bool(_low()).is_false()
	assert_str(_glyph("PowerGlyph")).is_equal(ICONS % "glyph_power")
	assert_str(str((_node("PowerBar") as Control).theme_type_variation)).is_equal("PowerBar")
	assert_float((_node("PowerBar") as ProgressBar).value).is_equal(30.0)


func test_a_player_with_no_buildings_has_an_empty_bar_that_is_not_low() -> void:
	await _open()
	_publish(2000, 0, 0)
	assert_bool(_low()).is_false()
	assert_float((_node("PowerBar") as ProgressBar).value).is_equal(0.0)
	assert_str((_node("PowerText") as Label).text).is_equal("0/0")


func test_the_glyphs_have_their_icons_and_their_tints_from_the_theme() -> void:
	await _open()
	_publish(0, 100, 40)
	assert_str(_glyph("CreditsGlyph")).is_equal(ICONS % "glyph_credits")
	assert_str(_glyph("PowerGlyph")).is_equal(ICONS % "glyph_power")
	var credits: Color = _sidebar.get_theme_color(&"credits", &"BuildSidebar")
	var power: Color = _sidebar.get_theme_color(&"power", &"BuildSidebar")
	var warning: Color = _sidebar.get_theme_color(&"warning", &"BuildSidebar")
	assert_that((_node("CreditsGlyph") as Control).modulate).is_equal(credits)
	assert_that((_node("PowerGlyph") as Control).modulate).is_equal(power)
	_publish(0, 100, 140)
	assert_that((_node("PowerGlyph") as Control).modulate).is_equal(warning)
	assert_that(credits).is_not_equal(power)
	assert_that(power).is_not_equal(warning)


## The numbers are in the bar where it is wide enough for them and left out where it is not: the
## bar and the glyph still say it. A bar follows its line, so a frame runs before the look is read.
## The credits keep a five-digit slot, so on the 6-inch phone in landscape "40/60" fits and
## "40/100" does not.
func test_the_numbers_are_in_the_bar_only_where_it_is_wide_enough() -> void:
	await _open()
	_publish(2000, 60, 40)
	await await_idle_frame()
	assert_bool((_node("PowerText") as Control).visible).is_true()
	_publish(2000, 99999, 99999)
	await await_idle_frame()
	assert_bool((_node("PowerText") as Control).visible).is_false()
	_publish(2000, 60, 40)
	await await_idle_frame()
	assert_bool((_node("PowerText") as Control).visible).is_true()


## A turn changes the bar's width without a new snapshot, so only the bar's own `resized` makes
## the numbers follow it (the fit at the end of `_apply_dp` still reads the old width, as a
## container sorts later). Portrait gives the bar room for numbers that landscape has none for.
func test_the_numbers_follow_the_bar_when_a_turn_changes_its_width() -> void:
	await _open()
	_publish(2000, 99999, 99999)
	await await_idle_frame()
	var landscape_px: float = (_node("PowerBar") as Control).size.x
	assert_bool((_node("PowerText") as Control).visible).is_false()
	await _turn(&"android_6in_portrait")
	var portrait_px: float = (_node("PowerBar") as Control).size.x
	assert_float(portrait_px).is_greater(landscape_px)  # The turn moved the bar: not vacuous.
	assert_bool((_node("PowerText") as Control).visible).is_true()
	await _turn(&"android_6in")
	assert_float((_node("PowerBar") as Control).size.x).is_equal_approx(landscape_px, 1.0)
	assert_bool((_node("PowerText") as Control).visible).is_false()


## The numbers are in the middle of the bar, not hanging from its top: a line of text is taller
## than the bar's inside, so a label that grew only downwards rested on the bottom border. Their
## rect is inside the bar's and has the same centre, in both states and on every screen.
func test_the_numbers_sit_inside_the_bar_and_centred_in_it_at_every_size() -> void:
	await _open()
	for profile: StringName in _every_profile():
		await _turn(profile)
		for used: int in [4, 9]:  # Of 6 made: power to spare, then low power.
			_publish(2000, 6, used)
			await await_idle_frame()
			var why: String = "%s, %d/6 (%s)" % [profile, used, get_window().size]
			var text: Control = _node("PowerText")
			assert_bool(text.visible).override_failure_message(why + ": hidden").is_true()
			var bar: Rect2 = _rect("PowerBar")
			var numbers: Rect2 = _rect("PowerText")
			var inside: String = "%s: numbers %s in the bar %s" % [why, numbers, bar]
			assert_bool(bar.grow(0.5).encloses(numbers)).override_failure_message(inside).is_true()
			var off: float = absf(numbers.get_center().y - bar.get_center().y)
			var centred: String = "%s: numbers %s px off the bar's middle" % [why, off]
			assert_float(off).override_failure_message(centred).is_less_equal(UiScale.dp(1.0))


## The numbers' colours are the theme's and read against what is under them (WCAG): on the amber
## of low power the bar is full, so all of the text is on amber and is dark; on the green bar the
## text crosses the fill and the dark track, so it is white with a dark edge that reads on both.
func test_the_numbers_read_on_the_amber_and_on_the_green() -> void:
	await _open()
	var bar: ProgressBar = _node("PowerBar")
	var text: Label = _node("PowerText")
	_publish(0, 100, 130)
	var amber: Color = (bar.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color
	var dark: Color = text.get_theme_color(&"font_color")
	assert_float(_contrast(dark, amber)).is_greater_equal(AA_TEXT)
	assert_float(text.get_theme_color(&"font_outline_color").a).is_equal(0.0)  # No edge on amber.
	_publish(0, 100, 40)
	var green: Color = (bar.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color
	var track: Color = (bar.get_theme_stylebox(&"background") as StyleBoxFlat).bg_color
	var white: Color = text.get_theme_color(&"font_color")
	var edge: Color = text.get_theme_color(&"font_outline_color")
	assert_that(green).is_not_equal(amber)  # The look did change with the state.
	assert_float(_contrast(white, green)).is_greater_equal(AA_LARGE_TEXT)
	assert_float(_contrast(white, track)).is_greater_equal(AA_TEXT)
	assert_float(_contrast(edge, white)).is_greater_equal(AA_TEXT)
	assert_float(_contrast(edge, green)).is_greater_equal(AA_TEXT)
	assert_float(edge.a).is_equal(1.0)
	assert_int(text.get_theme_constant(&"outline_size")).is_greater_equal(1)


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
	_sidebar.refresh()
	assert_str(_credits().text).is_equal("0")
	assert_str((_node("PowerText") as Label).text).is_equal("0/0")
	_sidebar.runner = null  # No match at all: nothing is read, nothing breaks.
	_sidebar.refresh()
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


## The numbers of one crafted tick: three players' columns, the local player's in index 1.
func _craft(credits: int, made: int, used: int) -> MatchSnapshot:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.credits = PackedInt32Array([0, credits, OTHER_CREDITS])
	snap.power_made = PackedInt32Array([0, made, OTHER_POWER])
	snap.power_used = PackedInt32Array([0, used, OTHER_POWER])
	_tick += 1
	snap.tick = _tick
	return snap


## Publishes a crafted tick and reads it at once.
func _publish(credits: int, made: int, used: int) -> void:
	_runner.snapshot = _craft(credits, made, used)
	_sidebar.refresh()


## The rects of the status line's pieces, by name.
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


func _credits() -> Label:
	return _node("Credits")


func _node(node_name: String) -> Node:
	return _sidebar.find_child(node_name, true, false)


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
	_sidebar = _main.get_node("Hud").find_child("BuildSidebar", true, false)
	_controller = _main.get_node("PlayerController")
	_sent.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
