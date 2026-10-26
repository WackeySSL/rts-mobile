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
func test_the_numbers_are_in_the_bar_only_where_it_is_wide_enough() -> void:
	await _open()
	_publish(2000, 100, 40)
	await await_idle_frame()
	assert_bool((_node("PowerText") as Control).visible).is_true()
	_publish(2000, 99999, 99999)
	await await_idle_frame()
	assert_bool((_node("PowerText") as Control).visible).is_false()
	_publish(2000, 100, 40)
	await await_idle_frame()
	assert_bool((_node("PowerText") as Control).visible).is_true()


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


func _low() -> bool:
	return _glyph("PowerGlyph") == ICONS % "glyph_low_power"


func _glyph(node_name: String) -> String:
	return (_node(node_name) as TextureRect).texture.resource_path


func _credits() -> Label:
	return _node("Credits")


func _node(node_name: String) -> Node:
	return _sidebar.find_child(node_name, true, false)


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
