extends GdUnitTestSuite
## Picker and PickSnapshot (ADR 0004 sections 4-5). The rules run on hand-built snapshots. The
## hit areas run on a snapshot filled by a real UnitLayer on data/scenarios/controls_test.tres:
## tank 1 (id 1, tile (8, 18)) has no unit above it, so a tap straight above it reaches only it.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
## Hit radius of tank 1 in base px at zoom [0.75, 1.0]: the larger of dp(24) and its art radius
## (500 milli = 32 px at zoom 1, 24 px at zoom 0.75).
const RADIUS: Dictionary[StringName, Array] = {
	&"android_6in": [42.0, 42.0],
	&"web_phone": [48.67, 48.67],
	&"web_phone_small": [56.84, 56.84],
	&"web_tablet": [30.0, 32.0],
	&"desktop": [24.0, 32.0],
}
const ZOOMS: Array[float] = [0.75, 1.0]

var _settings: InputSettings = load("res://data/input_settings.tres")
var _camera: RtsCamera
var _layer: UnitLayer


func before_test() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load("res://data/scenarios/controls_test.tres")
	runner.start()
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_layer = auto_free(UnitLayer.new())
	_layer.runner = runner
	_layer.camera = _camera
	add_child(_layer)
	_layer.set_process(false)


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()


func test_the_hit_area_is_48_dp_across_or_the_art_if_larger_at_every_profile_and_zoom() -> void:
	assert_float(_settings.hit_radius_dp).is_equal(24.0)
	for profile_name: StringName in RADIUS:
		var profile: UiMetrics = UiProfiles.by_name(profile_name)
		UiScale.set_override(profile)  # dp comes from the profile alone, not from the window.
		for z: int in 2:
			_camera.zoom = Vector2(ZOOMS[z], ZOOMS[z])
			var snap: PickSnapshot = _fill(PickSnapshot.new())
			var radius: float = RADIUS[profile_name][z]
			var where: String = "%s at zoom %s" % [profile_name, ZOOMS[z]]
			assert_float(snap.radius_px[0]).override_failure_message(where).is_equal_approx(
				radius, 0.01
			)
			var above: Callable = func(px: float) -> int:
				return Picker.pick(snap, snap.screen_pos[0] - Vector2(0, px), 1, false)
			# 25 dp misses unless the art is bigger than that (a tablet or desktop at zoom 1).
			var at_25: int = 0 if UiScale.dp(25.0) <= radius else -1
			var got: Array[int] = [above.call(UiScale.dp(23.0)), above.call(UiScale.dp(25.0))]
			got.append_array([above.call(radius - 0.5), above.call(radius + 0.5)])
			assert_array(got).override_failure_message(where).is_equal([0, at_25, 0, -1])


func test_the_closest_centre_wins_not_the_closest_edge_and_ties_go_to_the_lower_id() -> void:
	var a: Array = [4, 1, 0, Vector2(100, 100), 60.0]
	var b: Array = [9, 1, 0, Vector2(140, 100), 60.0]
	for order: Array in [[a, b], [b, a]]:
		var snap: PickSnapshot = _snap(order)
		var picked: Array[int] = []
		for x: int in [110, 130, 120]:
			picked.append(snap.ids[Picker.pick(snap, Vector2(x, 100), 1, false)])
		assert_array(picked).is_equal([4, 9, 4])  # The last one is a tie.
	# Id 1 has the bigger area and the lower id, but its centre is 40 away and id 2's is 10.
	var wide: PickSnapshot = _snap(
		[[1, 1, 0, Vector2(100, 100), 100.0], [2, 1, 0, Vector2(150, 100), 20.0]]
	)
	assert_int(Picker.pick(wide, Vector2(140, 100), 1, false)).is_equal(1)
	var edge: PickSnapshot = _snap([[1, 1, 0, Vector2(100, 100), 10.0]])  # Exactly 10 away hits.
	var at_edge: Array[int] = [Picker.pick(edge, Vector2(110, 100), 1, false)]
	assert_array(at_edge + [Picker.pick(edge, Vector2(111, 100), 1, false)]).is_equal([0, -1])


func test_an_enemy_is_ignored_without_a_selection_and_wins_with_one() -> void:
	var snap: PickSnapshot = _snap(
		[[1, 1, 0, Vector2(100, 100), 60.0], [2, 2, 0, Vector2(140, 100), 60.0]]
	)
	var near_own: Vector2 = Vector2(105, 100)  # Both are hit, the own unit is closer.
	assert_int(Picker.pick(snap, near_own, 1, false)).is_equal(0)
	assert_int(Picker.pick(snap, near_own, 1, true)).is_equal(1)
	assert_int(Picker.pick(snap, Vector2(190, 100), 1, false)).is_equal(-1)  # Only the enemy.
	assert_int(Picker.pick(snap, Vector2(190, 100), 1, true)).is_equal(1)
	assert_int(Picker.pick(snap, Vector2(50, 100), 1, true)).is_equal(0)  # Only the own unit.
	assert_int(Picker.pick(snap, near_own, 2, false)).is_equal(1)  # Player 2: the roles swap.
	assert_int(Picker.pick(snap, Vector2(135, 100), 2, true)).is_equal(0)  # Enemy first, own closer.
	assert_int(Picker.pick(PickSnapshot.new(), near_own, 1, true)).is_equal(-1)  # Nothing there.


func test_rect_queries_return_ascending_ids_of_own_units_and_replace_the_output() -> void:
	var snap: PickSnapshot = _snap(
		[
			[9, 1, 0, Vector2(10, 10), 5.0],
			[3, 1, 1, Vector2(20, 20), 5.0],
			[7, 1, 0, Vector2(30, 30), 5.0],
			[5, 2, 0, Vector2(15, 15), 5.0],  # An enemy.
			[1, 1, 0, Vector2(200, 200), 5.0],  # Outside the rect.
		]
	)
	var rect: Rect2 = Rect2(0, 0, 100, 100)
	var out: PackedInt32Array = PackedInt32Array([99])
	Picker.own_in_rect(snap, rect, 1, out)
	assert_array(out).is_equal([3, 7, 9])
	Picker.own_of_type_in_rect(snap, 0, rect, 1, out)
	assert_array(out).is_equal([7, 9])
	Picker.own_of_type_in_rect(snap, 2, rect, 1, out)
	assert_array(out).is_empty()
	Picker.own_in_rect(snap, rect, 2, out)
	assert_array(out).is_equal([5])


func test_filling_a_snapshot_writes_the_rows_in_place_and_keeps_the_sizes() -> void:
	UiScale.set_override(UiProfiles.by_name(&"desktop"))  # dp(24) = 24 px, whatever the window is.
	_camera.position = Vector2(500, 1100)
	var snap: PickSnapshot = PickSnapshot.new()
	snap.ids.resize(100)  # Stale rows beyond the 40 units are dropped.
	_fill(snap)
	var sizes: Array[int] = [snap.ids.size(), snap.owners.size(), snap.type_index.size()]
	sizes.append_array([snap.screen_pos.size(), snap.radius_px.size(), snap.size()])
	assert_array(sizes).is_equal([40, 40, 40, 40, 40, 40])
	assert_array(snap.ids).is_equal(PackedInt32Array(range(1, 41)))
	var counts: Array[int] = [snap.owners.count(1), snap.owners.count(2), snap.type_index.count(0)]
	assert_array(counts).is_equal([30, 10, 40])
	assert_that(snap.screen_pos[0]).is_equal(_camera.world_to_screen(Vector2(544, 1184)))
	assert_that(snap.screen_pos[30]).is_equal(_layer.unit_screen_position(30))
	assert_float(snap.radius_px[0]).is_equal(32.0)  # Art 32 px at zoom 1 beats dp(24) = 24 px.
	var world: World = _layer.runner.world  # A second type, 1000 milli = 64 px, for row 5.
	world.type_selection_radius.append(1000)
	world.type_index[5] = 1
	_fill(snap)
	var row_5: Array = [snap.type_index[5], snap.radius_px[5], snap.radius_px.count(32.0)]
	assert_array(row_5).is_equal([1, 64.0, 39])  # The other 39 rows keep their 32 px.
	var held: Array = [snap.ids, snap.owners, snap.type_index, snap.screen_pos, snap.radius_px]
	for array: Variant in held:
		array.clear()  # In place, so the snapshot's own arrays are empty now.
	_camera.position = Vector2(600, 1100)
	_camera.zoom = Vector2(1.5, 1.5)
	_fill(snap)
	# A fill that replaced an array would leave the held one empty.
	assert_bool(held.all(func(a: Variant) -> bool: return a.size() == 40)).is_true()
	assert_that(held[3][0]).is_equal(_camera.world_to_screen(Vector2(544, 1184)))
	assert_float(snap.radius_px[0]).is_equal(48.0)  # Art 32 px * 1.5.


func _fill(snap: PickSnapshot) -> PickSnapshot:
	_layer.fill_pick_snapshot(snap, UiScale.dp(_settings.hit_radius_dp))
	return snap


## Rows are [id, owner, type_index, centre, radius_px].
func _snap(rows: Array) -> PickSnapshot:
	var snap: PickSnapshot = PickSnapshot.new()
	for row: Array in rows:
		snap.ids.append(row[0])
		snap.owners.append(row[1])
		snap.type_index.append(row[2])
		snap.screen_pos.append(row[3])
		snap.radius_px.append(row[4])
	return snap
