extends GdUnitTestSuite
## Fixtures of the attack cue suites (plan P123, ADR 0025 section 8): the main scene with player 1
## (a Headquarters, two light tanks, a Heavy Yard and a Bunkhouse), the crafted events and the
## toast's placement check. Not a suite itself.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const RadarRig: GDScript = preload("res://tests/ui/support/radar_rig.gd")
const ROSTER: Array = ["power_plant", "barracks", "vehicle_factory", "defence_turret", "light_tank"]
const MORE: Array = [["light_tank", 12, 10], ["light_tank", 13, 10]]
const HOME: Vector2i = Vector2i(11, 7)

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _feed: HudStateFeed
var _cues: AttackCues
var _toast: AttackToast
var _scope: RadarScope
var _minimap: Minimap
var _controller: PlayerController
var _touch: TouchInput
var _placement: PlacementController
var _sent: Array[Command] = []
var _told: int = 0  ## `map_gesture`s: a touch on the toast is none.
var _emitted: int = 0  ## `cue_changed`s since the scene opened.
var _unit_type: int = 0
var _building_type: int = 0
var _unit: int = 0  ## Ids of an own unit, an own building and an enemy row.
var _building: int = 0
var _enemy: int = 0


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	if is_instance_valid(_main):
		_main.free()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF
	CommandQueue.clear()
	get_window().size = _window_size_before


## The toast's rect is `HudCorners.place`'s for the screen in force, inside the safe rect and clear
## of the scope and the pill by the 8 dp gap and of the stack and the selection panel.
func _expect_toast_placed(why: String) -> void:
	var dp: float = UiScale.base_px_per_dp()
	var toast: Rect2 = _toast.get_global_rect()
	var scope: Rect2 = _scope.get_global_rect()
	var stack: Control = _hud("TopLeft") as Control
	var pill: Rect2 = (_hud("EconomyPill") as Control).get_global_rect()
	var panel: Control = _hud("SelectionPanel") as Control
	var safe: Rect2 = SafeAreaMargin.rect_inside(
		get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
	)
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	shown.toast = true
	shown.pill_width = (_hud("EconomyPill") as Control).size.x / dp
	shown.left_taken = HudLayout.first_visible_width(stack) / dp
	shown.left_height = stack.get_combined_minimum_size().y / dp
	if HudLayout.is_portrait() and panel.is_visible_in_tree():
		var below: float = (panel.get_global_rect().end.y - safe.position.y) / dp
		shown.left_height = maxf(shown.left_height, below)
	var placed: Dictionary[StringName, Rect2] = HudCorners.place(
		safe, HudLayout.is_portrait(), dp, false, shown
	)
	var want: Rect2 = placed[HudCorners.TOAST]
	var at: String = "%s: toast %s, wanted %s" % [why, toast, want]
	assert_bool(_toast.visible).override_failure_message(at).is_true()
	assert_vector(toast.position).override_failure_message(at).is_equal_approx(
		want.position, Vector2.ONE
	)
	assert_vector(toast.size).override_failure_message(at).is_equal_approx(want.size, Vector2.ONE)
	assert_float(toast.size.y).override_failure_message(at).is_greater_equal(UiScale.dp(48.0) - 0.5)
	var gap: float = UiScale.dp(HudCorners.GAP_DP) - 0.5
	assert_bool(safe.grow(0.5).encloses(toast)).override_failure_message(at).is_true()
	assert_bool(toast.grow(gap).intersects(scope)).override_failure_message(at).is_false()
	assert_bool(toast.grow(gap).intersects(pill)).override_failure_message(at).is_false()
	assert_bool(toast.intersects(stack.get_global_rect())).override_failure_message(at).is_false()
	if panel.is_visible_in_tree():
		var panel_at: String = "%s, panel %s" % [at, panel.get_global_rect()]
		(
			assert_bool(toast.intersects(panel.get_global_rect()))
			. override_failure_message(panel_at)
			. is_false()
		)


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _rect(node_name: String) -> Rect2:
	return (_hud(node_name) as Control).get_global_rect()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## A point near the map's east corner, outside the view at every size (milli-tiles), inside the map.
func _edge() -> Vector2i:
	var cols: int = _minimap.picture().cols()
	return Vector2i((cols - 3) * 1000 + 500, 3500)


## A crafted point a long way off the map, outside any view (milli-tiles).
func _far() -> Vector2i:
	return Vector2i((_minimap.picture().cols() + 60) * 1000 + 500, 3500)


## A SHOT at `target` landing at `ground`.
func _hit(target: int, ground: Vector2i) -> void:
	_tick([World.Event.SHOT, 1, 0, 0, target, 0, ground.x, ground.y])


func _tick(record: Array) -> void:
	var events: PackedInt32Array = PackedInt32Array()
	events.append_array(PackedInt32Array(record))
	_runner.snapshot.events = events
	_runner.ticked.emit(_runner.snapshot.tick)


func _open(size: Vector2i, metrics: UiMetrics = null) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	if metrics != null:
		UiScale.set_override(metrics)
	else:
		UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_runner = _main.get_node("MatchRunner")
	_runner.scenario = Rig.scenario_for(1, "headquarters", MORE, ROSTER)
	_runner.paused = true
	add_child(_main)
	await await_idle_frame()
	_camera = _main.get_node("Camera")
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_placement = _main.get_node("PlacementController")
	_feed = _hud("HudStateFeed") as HudStateFeed
	_cues = _hud("AttackCues") as AttackCues
	_toast = _hud("AttackToast") as AttackToast
	_scope = _hud("RadarScope") as RadarScope
	_minimap = _hud("Minimap") as Minimap
	_sent.clear()
	_told = 0
	_emitted = 0
	_cues.cue_changed.connect(func() -> void: _emitted += 1)
	_touch.vibrate = func(_ms: int) -> void: pass
	_touch.map_gesture.connect(func() -> void: _told += 1)
	_controller.vibrate = func(_ms: int) -> void: pass
	_controller.command_sink = func(command: Command) -> void:
		_sent.append(command)
		CommandQueue.submit(command)
	# The cue clock is the test's: no frame time enters it, and it stands on a whole ms, so that
	# sums and differences of whole-ms steps are exact (a fractional clock rounds a 4000 ms
	# difference to 3999.9999999999995 on about one start in five).
	_cues.set_process(false)
	_cues.advance(ceilf(_cues.clock_ms()) - _cues.clock_ms())
	_camera.zoom = Vector2.ONE
	_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))
	Rig.explore(_runner.snapshot)
	await _settle()
	_unit = 0
	_building = 0
	_enemy = 0
	var snap: MatchSnapshot = _runner.snapshot
	for row: int in snap.unit_count():
		var building: bool = snap.type_foot_w[snap.type_index[row]] > 0
		if snap.owner[row] == 1 and not building and _unit == 0:
			_unit = snap.unit_id[row]
			_unit_type = snap.type_index[row]
		elif snap.owner[row] == 1 and building and _building == 0:
			_building = snap.unit_id[row]
			_building_type = snap.type_index[row]
		elif snap.owner[row] != 1 and _enemy == 0:
			_enemy = snap.unit_id[row]
	assert_int(_unit).is_greater(0)
	assert_int(_building).is_greater(0)
	assert_int(_enemy).is_greater(0)
