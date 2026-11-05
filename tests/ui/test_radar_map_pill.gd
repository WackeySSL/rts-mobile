extends GdUnitTestSuite
## The pinned full map beside the pill through a strike aim (plan P120c, ADR 0025 sections 2 and
## 7), in the main scene on the short landscape screens: the map follows the pill's real width,
## narrows to keep a gap right of it, and folds at the aim's start where it cannot fit (the pin
## kept); the fold's threshold lies between two screens a few dp apart. Player 1 owns a Deep Bore.
## The map's other places are test_radar_map's.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const BuildingRig: GDScript = preload("res://tests/view/support/building_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const RadarRig: GDScript = preload("res://tests/ui/support/radar_rig.gd")
const STRIKE_SPAWNS: Array[Array] = [
	[1, "fossil_strike", 6, 6], [1, "light_tank", 14, 14], [2, "renew_hq", 20, 20]
]
const BORE: int = 1  ## The Deep Bore of STRIKE_SPAWNS.
const TOLERANCE_PX: float = 1.5
## Window widths (px at 3 px per dp) either side of the pinned map's fold: the first keeps it.
const FOLD_WIDTHS: Array[int] = [2046, 2022]

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _aim: StrikeAim
var _feed: HudStateFeed
var _state: HudState
var _map: RadarMap


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	CommandQueue.clear()


func before_test() -> void:
	MenuRig.begin()


## Where the pinned map cannot fit beside the pill and the aim's row (a safe width under about 654
## dp) it folds when the aim begins, the pin kept, instead of covering the pill's end; opened again
## during the aim it folds again. On the narrower screen of the test above it stays.
func test_a_pinned_map_that_cannot_fit_beside_the_pill_folds_when_the_aim_begins() -> void:
	var spawns: Array[SpawnDef] = []
	for entry: Array in STRIKE_SPAWNS:
		spawns.append(BuildingRig.spawn(entry[0], entry[1], entry[2], entry[3]))
	var tiny: UiMetrics = RadarRig.tiny_short_landscape()
	for screen: UiMetrics in [RadarRig.narrow_short_landscape(), tiny]:
		await _open(screen.window_size, screen, BuildingRig.scenario(spawns))
		_feed.set_process(false)
		var why: String = str(screen.window_size)
		_state.open(HudState.Unfold.RADAR)
		_state.pinned = true
		await _settle()
		var snap: MatchSnapshot = _runner.snapshot
		snap.ready_tick[snap.index_of(BORE)] = snap.tick + 1
		_aim.refresh()
		assert_bool(_aim.begin()).override_failure_message(why).is_true()
		await _settle()
		await _settle()
		var folds: bool = screen.window_size == tiny.window_size
		assert_bool(_state.is_open(HudState.Unfold.RADAR)).override_failure_message(why).is_equal(
			not folds
		)
		assert_bool(_state.pinned).override_failure_message(why).is_true()
		assert_bool(_aim.active).override_failure_message(why).is_true()
		if folds:
			_state.open(HudState.Unfold.RADAR)  # Opened during the aim: folds again.
			await _settle()
			await _settle()
			(
				assert_bool(_state.is_open(HudState.Unfold.RADAR))
				. override_failure_message(why)
				. is_false()
			)
		else:
			var pill: Rect2 = _rect("EconomyPill")
			(
				assert_bool(_map.get_global_rect().intersects(pill))
				. override_failure_message(why)
				. is_false()
			)
		_state.pinned = false


## The map follows the pill's real width: on the narrow short screen, pinned through an aim, the
## pill widens (low power's word, then 300 dp by hand) and the map narrows to keep a gap right of
## its end; where it cannot, it folds. A map that ignored the pill's width, or did not place again
## when the pill is resized, would stand over it.
func test_the_pinned_map_keeps_a_gap_right_of_the_pill_as_the_pill_widens() -> void:
	var spawns: Array[SpawnDef] = []
	for entry: Array in STRIKE_SPAWNS:
		spawns.append(BuildingRig.spawn(entry[0], entry[1], entry[2], entry[3]))
	var screen: UiMetrics = RadarRig.narrow_short_landscape()
	await _open(screen.window_size, screen, BuildingRig.scenario(spawns))
	_feed.set_process(false)
	_state.open(HudState.Unfold.RADAR)
	_state.pinned = true
	await _settle()
	var snap: MatchSnapshot = _runner.snapshot
	snap.ready_tick[snap.index_of(BORE)] = snap.tick + 1
	_aim.refresh()
	assert_bool(_aim.begin()).is_true()
	await _settle()
	var pill: Control = _hud("EconomyPill") as Control
	var dp: float = UiScale.dp(1.0)
	var before: Rect2 = _map.get_global_rect()
	assert_bool(_state.is_open(HudState.Unfold.RADAR)).is_true()
	# Low power: the pill asks for a few dp more.
	snap.power_used[1] = snap.power_made[1] + 10
	snap.tick += 1
	(pill as EconomyPill).refresh()
	await _settle()
	await _settle()
	var wide: Rect2 = pill.get_global_rect()
	assert_float(wide.size.x).is_greater(200.0 * dp)
	var map: Rect2 = _map.get_global_rect()
	var why: String = "pill %s, map %s (before %s)" % [wide, map, before]
	assert_bool(_state.is_open(HudState.Unfold.RADAR)).override_failure_message(why).is_true()
	assert_float(map.position.x - wide.end.x).override_failure_message(why).is_greater_equal(
		8.0 * dp - TOLERANCE_PX
	)
	assert_float(map.size.x).override_failure_message(why).is_less(before.size.x - 1.0)
	# By hand to 300 dp: it cannot fit beside the pill and the row, so the pinned map folds.
	pill.size = Vector2(300.0 * dp, pill.size.y)
	await _settle()
	await _settle()
	assert_bool(_state.is_open(HudState.Unfold.RADAR)).is_false()
	assert_bool(_state.pinned).is_true()
	_state.pinned = false


## The fold's threshold: a screen a few dp over it keeps the pinned map open through the aim, one
## a few dp under it folds the map at the aim's start.
func test_the_fold_threshold_sits_between_two_screens_a_few_dp_apart() -> void:
	var spawns: Array[SpawnDef] = []
	for entry: Array in STRIKE_SPAWNS:
		spawns.append(BuildingRig.spawn(entry[0], entry[1], entry[2], entry[3]))
	for width: int in FOLD_WIDTHS:
		var screen: UiMetrics = UiMetrics.create(
			"Web", 288, 3.0, 880.0 / 720.0, Vector2i(width, 880), Rect2i()
		)
		await _open(screen.window_size, screen, BuildingRig.scenario(spawns))
		_feed.set_process(false)
		_state.open(HudState.Unfold.RADAR)
		_state.pinned = true
		await _settle()
		var snap: MatchSnapshot = _runner.snapshot
		snap.ready_tick[snap.index_of(BORE)] = snap.tick + 1
		_aim.refresh()
		assert_bool(_aim.begin()).is_true()
		await _settle()
		await _settle()
		var open: bool = _state.is_open(HudState.Unfold.RADAR)
		var why: String = (
			"%d px wide: map %s, pill %s" % [width, _map.get_global_rect(), _rect("EconomyPill")]
		)
		assert_bool(open).override_failure_message(why).is_equal(width >= FOLD_WIDTHS[0])
		if open:
			var apart: float = _map.get_global_rect().position.x - _rect("EconomyPill").end.x
			assert_float(apart).override_failure_message(why).is_greater_equal(
				UiScale.dp(8.0) - TOLERANCE_PX
			)
		_state.pinned = false


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _rect(node_name: String) -> Rect2:
	return (_hud(node_name) as Control).get_global_rect()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## A new main scene at `size`, under `metrics`, the match paused, the map ready.
func _open(size: Vector2i, metrics: UiMetrics, scenario: ScenarioDef) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	UiScale.set_override(metrics)
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_runner = _main.get_node("MatchRunner")
	_runner.scenario = scenario
	_runner.paused = true
	add_child(_main)
	await await_idle_frame()
	_aim = _main.get_node("StrikeAim")
	_feed = _hud("HudStateFeed") as HudStateFeed
	_state = _feed.state
	_map = _hud("RadarMap") as RadarMap
	await _settle()
