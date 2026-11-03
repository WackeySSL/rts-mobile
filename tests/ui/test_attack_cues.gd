extends GdUnitTestSuite
## The attack cues (plan P123, ADR 0025 section 8), in the main scene at the six sizes of
## ScreenSizes.ALL: a SHOT or IMPACT on an own row outside the view raises one cue (a toast, a rim
## wedge toward the hit or a ping inside the scope, a ping on the full map); a second hit within
## `attack_cue_area_tiles` inside `attack_cue_ms` raises none, one elsewhere replaces the cue; the
## cue ends after `attack_toast_ms`; no toast while the full map is open; the toast keeps clear of
## the pill, the scope and the top-left stack; a tap on it jumps the camera.
## Player 1 has a Headquarters, two light tanks, a Heavy Yard and a Bunkhouse.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
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


func test_a_hit_on_a_unit_out_of_view_raises_one_cue_with_a_toast() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	assert_bool(_toast.visible).is_false()
	_hit(_unit, _far())
	assert_bool(_cues.active).is_true()
	assert_str(_cues.title).is_equal("UNITS UNDER ATTACK")
	assert_bool(_toast.visible).is_true()
	var labels: Array[Node] = _toast.find_children("*", "Label", true, false)
	assert_str((labels[1] as Label).text).is_equal("Tap to jump there")


func test_a_building_is_named_and_an_impact_counts_like_a_shot() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_tick([World.Event.IMPACT, 1, _far().x, _far().y, _building, 0, 0, 0])
	var snap: MatchSnapshot = _runner.snapshot
	var type_name: String = snap.type_names[snap.type_index[snap.index_of(_building)]]
	assert_str(_cues.title).is_equal(type_name.to_upper() + " UNDER ATTACK")


func test_no_cue_for_a_hit_in_view_an_enemy_row_or_a_missing_target() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_hit(_unit, Vector2i(HOME.x * 1000 + 500, HOME.y * 1000 + 500))  # In view.
	_hit(_enemy, _far())
	_hit(0, _far())  # An impact on the ground has no target.
	_hit(987654, _far())  # A row that is gone.
	assert_bool(_cues.active).is_false()


func test_a_repeat_in_the_area_raises_none_and_one_elsewhere_replaces() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	var settings: InputSettings = _feed.state.settings
	var reach: int = settings.attack_cue_area_tiles * 1000
	_hit(_unit, _far())
	var first: Vector2 = _cues.point
	_hit(_unit, _far() + Vector2i(reach - 500, 0))  # Just inside the area.
	assert_vector(_cues.point).is_equal(first)
	var aside: Vector2i = _far() + Vector2i(reach + 500, 0)
	_hit(_unit, aside)  # Just outside it.
	assert_vector(_cues.point).is_not_equal(first)
	# Within the interval the area stays quiet; after it, the same area raises again.
	var second: Vector2 = _cues.point
	_hit(_unit, aside + Vector2i(1000, 0))
	assert_vector(_cues.point).is_equal(second)
	_cues.advance(settings.attack_cue_ms + 1.0)
	_hit(_unit, aside + Vector2i(1000, 0))
	assert_bool(_cues.active).is_true()
	assert_vector(_cues.point).is_not_equal(second)


func test_the_cue_ends_after_attack_toast_ms() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	var ms: float = float(_feed.state.settings.attack_toast_ms)
	_hit(_unit, _far())
	_cues.advance(ms - 1.0)
	assert_bool(_toast.visible).is_true()
	_cues.advance(2.0)
	assert_bool(_cues.active).is_false()
	assert_bool(_toast.visible).is_false()


func test_with_the_full_map_open_there_is_no_toast_but_a_ping() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_feed.state.open(HudState.Unfold.RADAR)
	await _settle()
	var draws: int = _minimap.draw_count()
	_hit(_unit, _edge())
	await _settle()
	assert_bool(_cues.active).is_true()
	assert_bool(_toast.visible).is_false()
	assert_int(_minimap.draw_count()).is_greater(draws)  # Drawn anew, with the ping.
	assert_bool(_minimap.box_rect().has_point(_minimap.world_to_local(_cues.point))).is_true()
	_feed.state.close(HudState.Unfold.RADAR)
	assert_bool(_toast.visible).is_true()  # Folded, the cue still stands.


func test_the_rim_wedge_points_the_way_the_screen_does() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	var draws: int = _scope.draw_count()
	# West of home on the ground (-x) is up and left on the screen.
	_hit(_unit, Vector2i(HOME.x * 1000 - 30000, HOME.y * 1000))
	await _settle()
	assert_int(_scope.draw_count()).is_greater(draws)
	assert_bool(_scope.cue_on_rim()).is_true()
	assert_float(_scope.cue_offset().x).is_less(0.0)
	assert_float(_scope.cue_offset().y).is_less(0.0)
	_cues.dismiss()
	assert_vector(_scope.cue_offset()).is_equal(Vector2.ZERO)


func test_a_tap_on_the_toast_jumps_the_camera_and_closes_the_drawer() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_feed.state.open(HudState.Unfold.DRAWER)
	_hit(_unit, _edge())
	assert_bool(_toast.visible).is_true()
	var point: Vector2 = _cues.point
	var at: Vector2 = _toast.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	await _settle()
	assert_vector(_camera.position).is_equal_approx(point, Vector2.ONE * 2.0)
	assert_bool(_cues.active).is_false()
	assert_bool(_feed.state.is_open(HudState.Unfold.DRAWER)).is_false()


func test_the_toast_keeps_clear_of_the_pill_the_scope_and_the_stack_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		_hit(_unit, _far())
		await _settle()
		var why: String = "size %s" % size
		var toast: Rect2 = _toast.get_global_rect()
		var gap: float = UiScale.dp(HudCorners.GAP_DP) - 0.5
		var scope: Rect2 = _scope.get_global_rect()
		var stack: Rect2 = (_hud("TopLeft") as Control).get_global_rect()
		var pill: Rect2 = (_hud("EconomyPill") as Control).get_global_rect()
		assert_bool(toast.size.y >= UiScale.dp(48.0) - 0.5).override_failure_message(why).is_true()
		assert_bool(toast.grow(gap).intersects(scope)).override_failure_message(why).is_false()
		assert_bool(toast.grow(gap).intersects(pill)).override_failure_message(why).is_false()
		assert_bool(toast.intersects(stack)).override_failure_message(why).is_false()
		var safe: Rect2 = SafeAreaMargin.rect_inside(
			get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
		)
		assert_bool(safe.grow(0.5).encloses(toast)).override_failure_message(why).is_true()


func test_the_portrait_toast_stands_under_the_taller_top_left_stack() -> void:
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	shown.toast = true
	shown.left_taken = 56.0
	shown.left_height = 104.0
	var safe: Rect2 = Rect2(0.0, 0.0, 336.0, 676.0)
	var rects: Dictionary[StringName, Rect2] = HudCorners.place(safe, true, 1.0, false, shown)
	assert_float(rects[HudCorners.TOAST].position.y).is_equal(112.0)
	shown.left_height = 0.0
	rects = HudCorners.place(safe, true, 1.0, false, shown)
	assert_float(rects[HudCorners.TOAST].position.y).is_equal(64.0)  # A gap under the scope.


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


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


func _open(size: Vector2i) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
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
	_feed = _hud("HudStateFeed") as HudStateFeed
	_cues = _hud("AttackCues") as AttackCues
	_toast = _hud("AttackToast") as AttackToast
	_scope = _hud("RadarScope") as RadarScope
	_minimap = _hud("Minimap") as Minimap
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
		elif snap.owner[row] == 1 and building and _building == 0:
			_building = snap.unit_id[row]
		elif snap.owner[row] != 1 and _enemy == 0:
			_enemy = snap.unit_id[row]
	assert_int(_unit).is_greater(0)
	assert_int(_building).is_greater(0)
	assert_int(_enemy).is_greater(0)
