extends GdUnitTestSuite
## Picker and PickSnapshot (ADR 0004 sections 4-5). The rules run on hand-built snapshots. The
## hit areas run on a snapshot filled by a real UnitLayer on data/scenarios/controls_test.tres:
## tank 1 (id 1, tile (8, 18)) has no unit above it, so a tap straight above it reaches only it.
## `pickable` (P47p) is 0 for an enemy the fog hides: the hand-built cases set it by hand, and the
## fill cases read what a real UnitLayer writes at tick 0 (the red tanks, rows 30-39, are hidden).

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Rig: GDScript = preload("res://tests/view/support/fog_rig.gd")
const Lifts: GDScript = preload("res://tests/view/support/lifts.gd")
## Hit radius of tank 1 in base px at zoom [0.75, 1.0, 1.5]: the larger of dp(24) and the horizontal
## semi-axis of its ground ellipse (500 milli: 22.63 px at zoom 1, ADR 0023 section 3), so only a
## desktop or a tablet at zoom 1.5 reaches past the 48 dp across (33.94 px).
const RADIUS: Dictionary[StringName, Array] = {
	&"android_6in": [42.0, 42.0, 42.0],
	&"web_phone": [48.67, 48.67, 48.67],
	&"web_phone_small": [56.84, 56.84, 56.84],
	&"web_tablet": [30.0, 30.0, 33.94],
	&"desktop": [24.0, 24.0, 33.94],
}
const ZOOMS: Array[float] = [0.75, 1.0, 1.5]

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
		for z: int in ZOOMS.size():
			_camera.zoom = Vector2(ZOOMS[z], ZOOMS[z])
			var snap: PickSnapshot = _fill(PickSnapshot.new())
			var radius: float = RADIUS[profile_name][z]
			var where: String = "%s at zoom %s" % [profile_name, ZOOMS[z]]
			assert_float(snap.radius_px[0]).override_failure_message(where).is_equal_approx(
				radius, 0.01
			)
			var above: Callable = func(px: float) -> int:
				return Picker.pick(snap, snap.screen_pos[0] - Vector2(0, px), 1, false)
			# 25 dp misses unless the art is bigger than that (a tablet or desktop at zoom 1.5).
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


func test_unpickable_rows_are_skipped_by_pick_even_at_distance_0_and_the_index_is_the_row() -> void:
	var snap: PickSnapshot = _snap(
		[
			[1, 1, 0, Vector2(100, 100), 60.0],  # Own.
			[5, 2, 0, Vector2(300, 100), 60.0],  # An enemy the fog hides.
			[6, 2, 0, Vector2(340, 100), 60.0],  # An enemy in sight, 40 px right of it.
		]
	)
	snap.pickable = PackedByteArray([1, 0, 1])
	# On the hidden enemy's centre the visible one is picked, and it is row 2: the row of the
	# snapshot, not its place among the pickable rows (that would be 1).
	assert_int(Picker.pick(snap, Vector2(300, 100), 1, true)).is_equal(2)
	# Where only the hidden enemy is hit, nothing is, with a selection too.
	assert_int(Picker.pick(snap, Vector2(250, 100), 1, true)).is_equal(-1)
	assert_int(Picker.pick(snap, Vector2(300, 100), 1, false)).is_equal(-1)
	snap.pickable = PackedByteArray([1, 1, 0])  # The other way round: the nearer enemy is shown.
	assert_int(Picker.pick(snap, Vector2(330, 100), 1, true)).is_equal(1)
	assert_int(Picker.pick(snap, Vector2(380, 100), 1, true)).is_equal(-1)
	# The roles swap for player 2. A marked enemy and a marked own row are both skipped at distance 0.
	snap.pickable = PackedByteArray([0, 1, 1])
	assert_int(Picker.pick(snap, Vector2(100, 100), 2, true)).is_equal(-1)
	snap.pickable = PackedByteArray([1, 0, 1])
	assert_int(Picker.pick(snap, Vector2(300, 100), 2, false)).is_equal(2)  # Own row 1 is marked.
	# Rows past the end of `pickable` have no entry and are pickable, as in a hand-built snapshot.
	snap.pickable = PackedByteArray([0])
	assert_int(Picker.pick(snap, Vector2(100, 100), 1, true)).is_equal(-1)  # Row 0 is skipped.
	assert_int(Picker.pick(snap, Vector2(270, 100), 1, true)).is_equal(1)
	assert_int(Picker.pick(snap, Vector2(330, 100), 1, true)).is_equal(2)
	snap.pickable = PackedByteArray()
	assert_int(Picker.pick(snap, Vector2(100, 100), 1, true)).is_equal(0)
	assert_int(Picker.pick(snap, Vector2(300, 100), 1, true)).is_equal(1)  # Closer than row 2.


func test_the_box_queries_skip_unpickable_rows_and_keep_ascending_ids() -> void:
	var snap: PickSnapshot = _snap(
		[
			[9, 1, 0, Vector2(10, 10), 5.0],
			[3, 1, 1, Vector2(20, 20), 5.0],
			[7, 1, 0, Vector2(30, 30), 5.0],  # Marked 0.
			[5, 2, 0, Vector2(15, 15), 5.0],  # An enemy, marked 0.
			[4, 1, 0, Vector2(40, 40), 5.0],
		]
	)
	var rect: Rect2 = Rect2(0, 0, 100, 100)
	var out: PackedInt32Array = PackedInt32Array([99])
	snap.pickable = PackedByteArray([1, 1, 0, 0, 1])
	Picker.own_in_rect(snap, rect, 1, out)
	assert_array(out).is_equal([3, 4, 9])
	Picker.own_of_type_in_rect(snap, 0, rect, 1, out)
	assert_array(out).is_equal([4, 9])
	Picker.own_in_rect(snap, rect, 2, out)  # Player 2: its only unit is the marked one.
	assert_array(out).is_empty()
	snap.pickable = PackedByteArray([1, 1, 0])  # Rows 3 and 4 have no entry: pickable.
	Picker.own_in_rect(snap, rect, 1, out)
	assert_array(out).is_equal([3, 4, 9])
	Picker.own_in_rect(snap, rect, 2, out)
	assert_array(out).is_equal([5])
	snap.pickable = PackedByteArray()
	Picker.own_in_rect(snap, rect, 1, out)
	assert_array(out).is_equal([3, 4, 7, 9])


func test_the_fill_marks_exactly_the_enemies_that_is_shown_denies_and_reads_the_fog_as_asked(
) -> void:
	var snap: PickSnapshot = _fill(PickSnapshot.new())
	assert_array(_marks_against_is_shown(snap)).is_empty()
	assert_int(snap.pickable.slice(30).count(0)).is_equal(10)  # Every red tank is hidden.
	# Read at the call, nothing kept: one tile in sight brings one row, with no frame in between.
	Rig.set_seen(_layer.runner.snapshot, 1, Vector2i(34, 10), true)  # Red tank 31's tile.
	_fill(snap)
	assert_array(_marks_against_is_shown(snap)).is_empty()
	assert_int(snap.pickable[30]).is_equal(1)
	assert_int(snap.pickable.slice(31).count(0)).is_equal(9)
	Rig.set_seen(_layer.runner.snapshot, 1, Vector2i(34, 10), false)
	# The tile is the one of the unit's position in this tick, as for the rig: red tank 31 stood on
	# a tile in sight (blue tank 1's) the tick before and does not count as seen.
	_layer.runner.snapshot.prev_pos_x[30] = 8500
	_layer.runner.snapshot.prev_pos_y[30] = 18500
	_fill(snap)
	assert_int(snap.pickable[30]).is_equal(0)
	_layer.reveal_enemies = true  # The perf arena and the tests whose subject is not fog.
	_fill(snap)
	assert_int(snap.pickable.count(1)).is_equal(40)
	_layer.reveal_enemies = false
	Rig.blind(_layer.runner.snapshot, 1)  # Own units are marked 1 whatever the player sees.
	_fill(snap)
	assert_array(_marks_against_is_shown(snap)).is_empty()
	assert_int(snap.pickable.slice(0, 30).count(1)).is_equal(30)
	assert_int(snap.pickable.slice(30).count(0)).is_equal(10)


func test_local_player_2_hides_the_blue_tanks_and_picks_through_its_own_fog() -> void:
	var layer: UnitLayer = _layer_of(Rig.scenario(2))
	var runner: MatchRunner = layer.runner
	var snap: PickSnapshot = PickSnapshot.new()
	layer.fill_pick_snapshot(snap, UiScale.dp(_settings.hit_radius_dp))
	assert_int(snap.pickable.slice(0, 30).count(0)).is_equal(30)  # Blue is the enemy now.
	assert_int(snap.pickable.slice(30).count(1)).is_equal(10)
	# A tap on blue tank 1 with a selection hits nothing; once red sees its tile it is row 0.
	var on_tank_1: Vector2 = snap.screen_pos[0]
	assert_int(Picker.pick(snap, on_tank_1, 2, true)).is_equal(-1)
	Rig.set_seen(runner.snapshot, 2, Vector2i(8, 18), true)
	layer.fill_pick_snapshot(snap, UiScale.dp(_settings.hit_radius_dp))
	assert_int(snap.pickable[0]).is_equal(1)
	assert_int(snap.pickable.slice(1, 30).count(0)).is_equal(29)
	assert_int(Picker.pick(snap, on_tank_1, 2, true)).is_equal(0)


func test_a_local_player_the_fog_has_no_grid_for_or_a_fog_with_no_tiles_picks_every_row() -> void:
	# Two players: the fog has no grid for a third, so it hides nothing from it (as for is_shown).
	# The fill must not index the fog for that player, which would read past the end of `visible`.
	var layer: UnitLayer = _layer_of(Rig.scenario(3))
	var snap: PickSnapshot = PickSnapshot.new()
	layer.fill_pick_snapshot(snap, UiScale.dp(_settings.hit_radius_dp))
	assert_int(snap.pickable.count(1)).is_equal(40)
	assert_array(_marks_against_is_shown(snap, layer)).is_empty()
	# A fog sized for the players and no tiles (a snapshot with no map) hides nothing either.
	var no_tiles: FogGrid = FogGrid.new()
	no_tiles.configure(0, 0, 2)
	_layer.runner.snapshot.fog = no_tiles
	_fill(snap)
	assert_int(snap.pickable.count(1)).is_equal(40)
	assert_array(_marks_against_is_shown(snap)).is_empty()


func test_a_refill_from_a_layer_with_no_rows_empties_every_array_of_the_snapshot() -> void:
	var snap: PickSnapshot = _fill(PickSnapshot.new())
	assert_int(snap.pickable.size()).is_equal(40)
	var idle: UnitLayer = auto_free(UnitLayer.new())  # Its runner has no snapshot yet.
	idle.runner = auto_free(MatchRunner.new())
	idle.camera = _camera
	add_child(idle)
	idle.set_process(false)
	idle.fill_pick_snapshot(snap, UiScale.dp(_settings.hit_radius_dp))
	var sizes: Array[int] = [snap.ids.size(), snap.owners.size(), snap.type_index.size()]
	sizes.append_array([snap.screen_pos.size(), snap.radius_px.size(), snap.pickable.size()])
	assert_array(sizes).is_equal([0, 0, 0, 0, 0, 0])  # The arrays stay parallel: none is stale.
	_fill(snap)  # And the same snapshot takes the rows of a layer that has them again.
	assert_array([snap.size(), snap.pickable.size(), snap.pickable.count(1)]).is_equal([40, 40, 30])


func test_filling_a_snapshot_writes_the_rows_in_place_and_keeps_the_sizes() -> void:
	UiScale.set_override(UiProfiles.by_name(&"desktop"))  # dp(24) = 24 px, whatever the window is.
	_camera.position = Vector2(500, 1100)
	var snap: PickSnapshot = PickSnapshot.new()
	snap.ids.resize(100)  # Stale rows beyond the 40 units are dropped.
	_fill(snap)
	var sizes: Array[int] = [snap.ids.size(), snap.owners.size(), snap.type_index.size()]
	sizes.append_array([snap.screen_pos.size(), snap.radius_px.size(), snap.size()])
	sizes.append(snap.pickable.size())
	assert_array(sizes).is_equal([40, 40, 40, 40, 40, 40, 40])
	# P47p: the blue rows (0-29) are pickable, the red rows (30-39) are hidden at tick 0.
	assert_array([snap.pickable.slice(0, 30).count(1), snap.pickable.slice(30).count(0)]).is_equal(
		[30, 10]
	)
	assert_array(snap.ids).is_equal(PackedInt32Array(range(1, 41)))
	var counts: Array[int] = [snap.owners.count(1), snap.owners.count(2), snap.type_index.count(0)]
	assert_array(counts).is_equal([30, 10, 40])
	# The centre is the lifted one: the ground point raised by the sheet's pick lift (zoom 1).
	var lift: float = Lifts.pick(&"light_tank")
	assert_that(snap.screen_pos[0]).is_equal(_camera.world_to_screen(Vector2(-320, 432 - lift)))
	assert_that(snap.screen_pos[30]).is_equal(_layer.unit_screen_position(30) - Vector2(0.0, lift))
	assert_float(snap.radius_px[0]).is_equal(24.0)  # Art 22.63 px at zoom 1 loses to dp(24).
	# A second type, 1000 milli = 45.25 px, for row 5. The layer reads the published snapshot, so the
	# test writes that (allowed in SYNC, ADR 0012 section 3); a tick would not do, the sim has no
	# speed for type 1.
	var published: MatchSnapshot = _layer.runner.snapshot
	published.type_selection_radius.append(1000)
	published.type_index[5] = 1
	_fill(snap)
	assert_int(snap.type_index[5]).is_equal(1)
	assert_float(snap.radius_px[5]).is_equal_approx(45.2548, 0.001)
	assert_int(snap.radius_px.count(24.0)).is_equal(39)  # The other 39 rows keep their 24 px.
	var held: Array = [snap.ids, snap.owners, snap.type_index, snap.screen_pos, snap.radius_px]
	held.append(snap.pickable)
	for array: Variant in held:
		array.clear()  # In place, so the snapshot's own arrays are empty now.
	_camera.position = Vector2(600, 1100)
	_camera.zoom = Vector2(1.5, 1.5)
	_fill(snap)
	# A fill that replaced an array would leave the held one empty.
	assert_bool(held.all(func(a: Variant) -> bool: return a.size() == 40)).is_true()
	assert_int(held[5].count(1)).is_equal(30)  # And filled, not just resized.
	assert_that(held[3][0]).is_equal(_camera.world_to_screen(Vector2(-320, 432 - lift)))
	assert_float(snap.radius_px[0]).is_equal_approx(33.9411, 0.001)  # Art 22.63 px * 1.5.


## The rows whose `pickable` entry is not what `is_shown` says (of `layer`, else the suite's own; an
## own unit always is shown).
func _marks_against_is_shown(snap: PickSnapshot, layer: UnitLayer = null) -> Array[int]:
	var judge: UnitLayer = layer if layer != null else _layer
	var wrong: Array[int] = []
	for row: int in snap.size():
		if (snap.pickable[row] == 1) != judge.is_shown(row):
			wrong.append(row)
	return wrong


## A layer on its own started match of `scenario`, apart from the suite's `_layer`.
func _layer_of(scenario: ScenarioDef) -> UnitLayer:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = scenario
	runner.start()
	var layer: UnitLayer = auto_free(UnitLayer.new())
	layer.runner = runner
	layer.camera = _camera
	add_child(layer)
	layer.set_process(false)
	return layer


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
