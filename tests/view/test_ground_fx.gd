extends GdUnitTestSuite
## The dust behind moving vehicles (plan P138, ADR 0027 sections 3 and 8): one puff per
## `dust_every_milli` of travel of a vehicle in view, behind it, none while it stands, none for a
## squad or a building, none for a tile the local player does not see or outside the view rect
## grown by a tile, the 48-slot ring with the oldest overwritten, the life of a puff in match time,
## `reduced`, and a new match. The scene and the budget are in test_ground_fx_scene.gd.
## Fixtures: recoil_rig.gd (a paused runner not in the tree; the test publishes a tick by moving
## a unit in the snapshot and emitting `ticked`, as the runner does, then calls `_process` for a
## frame). Light tank (id 1) at tile (10, 10), rifle squad (3) and the Redoubt (4) near it, the
## enemy tank (5) out of sight at (28, 28).

const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const STEP: int = 300  ## Milli-tiles per tick: two ticks are under 700, three are over.
const TOL: Vector2 = Vector2(0.01, 0.01)
const FAR: float = 1.0e6

var _runner: MatchRunner
var _camera: RtsCamera
var _life: LifeSettings
var _layer: GroundFx
var _tick: int = 100


func before_test() -> void:
	_runner = auto_free(Rig.runner())
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_start(LifeSettings.new())
	_watch(Rig.LIGHT)


func after_test() -> void:
	CommandQueue.clear()


@warning_ignore("integer_division")
func test_a_vehicle_leaves_a_puff_for_each_dust_every_milli_of_travel() -> void:
	_drive(Rig.LIGHT, STEP, 0, 2)  # 600 milli: not yet.
	assert_int(_layer.slot_count()).is_equal(0)
	_drive(Rig.LIGHT, STEP, 0, 1)  # 900: the first puff, 200 left over.
	assert_int(_layer.slot_count()).is_equal(1)
	_drive(Rig.LIGHT, STEP, 0, 1)  # 500 since the puff.
	assert_int(_layer.slot_count()).is_equal(1)
	_drive(Rig.LIGHT, STEP, 0, 1)  # 800: the second.
	assert_int(_layer.slot_count()).is_equal(2)
	_drive(Rig.LIGHT, STEP, 0, 20)  # 25 ticks of 300 in all: 7500 milli, so 10 puffs by the carry.
	assert_int(_layer.slot_count()).is_equal(25 * STEP / 700)


func test_the_puff_lies_behind_the_position_the_vehicle_left_along_the_way_it_came() -> void:
	_drive(Rig.LIGHT, 0, 900, 1)  # South on the grid, 900 milli in a tick.
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(Rig.LIGHT)
	var behind: Vector2 = IsoProjection.ground_to_px(
		snap.prev_pos_x[row], snap.prev_pos_y[row] - _life.dust_back_milli
	)
	assert_int(_layer.slot_count()).is_equal(1)
	assert_vector(_layer.puff_at(0)).is_equal_approx(behind, TOL)
	assert_int(_layer.puff_born(0)).is_equal(_tick)


func test_a_standing_vehicle_a_squad_and_a_building_leave_nothing() -> void:
	_drive(Rig.LIGHT, 0, 0, 30)  # Stands.
	_drive(Rig.SQUAD, 900, 0, 5)  # Infantry moves, but leaves no dust.
	_drive(Rig.REDOUBT, 900, 0, 5)  # A defence has no speed.
	assert_int(_layer.slot_count()).is_equal(0)


func test_an_enemy_on_a_tile_the_player_does_not_see_leaves_nothing_but_a_seen_one_does() -> void:
	_watch(Rig.ENEMY_TANK)
	_drive(Rig.ENEMY_TANK, -900, 0, 3)
	assert_int(_layer.slot_count()).is_equal(0)  # In view, in the dark.
	var row_of_sight: Array[Vector2i] = []
	for column: int in range(14, 30):
		row_of_sight.append(Vector2i(column, Rig.FAR_TILE.y))
	Buildings.see(_runner.snapshot, 1, row_of_sight)
	_drive(Rig.ENEMY_TANK, -900, 0, 2)
	assert_int(_layer.slot_count()).is_equal(2)
	_layer.reveal_enemies = true
	Buildings.see(_runner.snapshot, 1, [])
	_drive(Rig.ENEMY_TANK, -900, 0, 1)
	assert_int(_layer.slot_count()).is_equal(3)


func test_a_vehicle_out_of_the_view_rect_leaves_nothing_but_its_travel_counts() -> void:
	_camera.position = Vector2(FAR, FAR)
	_drive(Rig.LIGHT, STEP, 0, 3)  # 900 milli, nowhere near the camera: the puff is not made.
	assert_int(_layer.slot_count()).is_equal(0)
	_watch(Rig.LIGHT)
	_drive(Rig.LIGHT, STEP, 0, 1)  # 200 carried over + 300.
	assert_int(_layer.slot_count()).is_equal(0)
	_drive(Rig.LIGHT, STEP, 0, 1)  # 800: this one is made.
	assert_int(_layer.slot_count()).is_equal(1)
	var inside: Rect2 = _camera.visible_world_rect().grow(GroundFx.VIEW_MARGIN_PX)
	assert_bool(inside.has_point(_layer.puff_at(0))).is_true()
	_layer.camera = null  # No camera, nothing in view.
	_drive(Rig.LIGHT, 900, 0, 3)
	assert_int(_layer.slot_count()).is_equal(1)


func test_the_ring_holds_dust_slots_and_the_oldest_puff_is_overwritten() -> void:
	_life.dust_life_ms = 100000  # Every puff of the ring is alive.
	for round: int in 12:  # A puff a tick, out and back so that the tank stays on the map.
		_drive(Rig.LIGHT, 700 if round % 2 == 0 else -700, 0, 5)
	assert_int(_layer.slot_count()).is_equal(_life.dust_slots)
	assert_int(_life.dust_slots).is_equal(48)
	var oldest: int = _tick
	for slot: int in _layer.slot_count():
		oldest = mini(oldest, _layer.puff_born(slot))
	assert_int(oldest).is_equal(_tick - 47)  # The 49th overwrote the first, and so on.
	_frame_at(0.0)
	assert_int(_layer.quad_count()).is_equal(48)


func test_a_puff_grows_and_fades_in_dust_life_ms_of_match_time_and_is_then_gone() -> void:
	_drive(Rig.LIGHT, 0, 900, 1)
	var spot: Vector2 = _layer.puff_at(0)
	var size: Vector2 = Vector2(LifeRegions.FIRST[&"dust"].size)
	_frame_at(0.0)  # Born: the first size, the full alpha.
	assert_int(_layer.quad_count()).is_equal(1)
	assert_float(_layer.quad_alpha(0)).is_equal_approx(_life.dust_alpha, 0.001)
	assert_vector(_layer.quad_rect(0).size).is_equal_approx(size * _life.dust_grow_from, TOL)
	# The anchor of the dust frame is its centre, so the centre of the quad is the puff's spot.
	assert_vector(_layer.quad_rect(0).get_center()).is_equal_approx(spot, TOL)
	Rig.at(_runner, _tick + 4, 0.5)  # 300 ms of the 600: half way on both.
	_layer._process(0.0)
	var mid: float = (_life.dust_grow_from + _life.dust_grow_to) * 0.5
	assert_float(_layer.quad_alpha(0)).is_equal_approx(_life.dust_alpha * 0.5, 0.001)
	assert_vector(_layer.quad_rect(0).size).is_equal_approx(size * mid, TOL)
	Rig.at(_runner, _tick + 9, 0.0)  # 600 ms: gone.
	_layer._process(0.0)
	assert_int(_layer.quad_count()).is_equal(0)


func test_the_frame_is_the_pick_of_the_unit_and_the_tick_and_two_layers_agree() -> void:
	var twin: GroundFx = auto_free(GroundFx.new())
	twin.runner = _runner
	twin.camera = _camera
	twin.life = _life
	add_child(twin)
	twin.set_process(false)
	var seen: Dictionary[int, bool] = {}
	for round: int in 20:
		_drive(Rig.LIGHT, 0, 900 if round % 2 == 0 else -900, 1)
		_frame_at(0.0)
		twin._process(0.0)
		var want: int = LifeClock.pick(Rig.LIGHT, GroundFx.SALT_DUST + _tick, 3)
		var newest: int = _layer.quad_count() - 1  # The plan runs from the oldest puff.
		assert_int(_layer.quad_frame(newest)).is_equal(want)
		assert_int(twin.quad_frame(newest)).is_equal(want)
		assert_vector(twin.quad_rect(newest).position).is_equal(_layer.quad_rect(newest).position)
		seen[want] = true
	assert_int(seen.size()).is_greater(1)  # The three frames vary.


func test_reduced_makes_no_dust_and_the_switch_empties_the_ring() -> void:
	_drive(Rig.LIGHT, 0, 900, 3)
	_frame_at(0.0)
	assert_int(_layer.slot_count()).is_equal(3)
	assert_int(_layer.quad_count()).is_equal(3)
	_life.reduced = true
	_layer._process(0.0)
	assert_int(_layer.slot_count()).is_equal(0)
	assert_int(_layer.quad_count()).is_equal(0)
	_drive(Rig.LIGHT, 0, -900, 5)
	assert_int(_layer.slot_count()).is_equal(0)
	_life.reduced = false  # Back on: new dust, nothing that was dropped returns.
	_drive(Rig.LIGHT, 0, -900, 1)
	_frame_at(0.0)
	assert_int(_layer.quad_count()).is_equal(1)


func test_a_new_match_empties_the_ring_and_the_travel() -> void:
	_drive(Rig.LIGHT, STEP, 0, 2)  # 600 milli of travel, no puff yet.
	_drive(Rig.LIGHT, 0, 900, 2)
	assert_int(_layer.slot_count()).is_equal(2)
	_runner.snapshot.match_serial += 1
	_layer._process(0.0)
	assert_int(_layer.slot_count()).is_equal(0)
	_drive(Rig.LIGHT, STEP, 0, 1)  # The travel before the new match is forgotten.
	assert_int(_layer.slot_count()).is_equal(0)


func test_a_change_of_rows_keeps_the_travel_of_the_units_that_stay() -> void:
	_drive(Rig.LIGHT, STEP, 0, 2)  # 600.
	_runner.snapshot.rows_version += 1  # A unit was made elsewhere; the light tank stays.
	_drive(Rig.LIGHT, STEP, 0, 1)
	assert_int(_layer.slot_count()).is_equal(1)  # 900 in all, carried over the new table.


func _start(life: LifeSettings) -> void:
	_life = life
	_layer = auto_free(GroundFx.new())
	_layer.runner = _runner
	_layer.camera = _camera
	_layer.life = _life
	add_child(_layer)
	_layer.set_process(false)


## Points the camera at unit `id`.
func _watch(id: int) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(id)
	_camera.position = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])


## `ticks` ticks of unit `id` moving by (dx, dy) milli-tiles each, each one delivered the way the
## runner does it. The camera stays where it is.
func _drive(id: int, dx: int, dy: int, ticks: int) -> void:
	for _i: int in ticks:
		var snap: MatchSnapshot = _runner.snapshot
		snap.prev_pos_x = snap.pos_x.duplicate()
		snap.prev_pos_y = snap.pos_y.duplicate()
		var row: int = snap.index_of(id)
		snap.pos_x[row] += dx
		snap.pos_y[row] += dy
		_tick += 1
		snap.tick = _tick
		_runner.ticked.emit(_tick)


## A frame at `alpha` into the tick of the last drive.
func _frame_at(alpha: float) -> void:
	Rig.at(_runner, _tick, alpha)
	_layer._process(0.0)
