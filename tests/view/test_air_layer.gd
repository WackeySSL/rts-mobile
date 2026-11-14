extends GdUnitTestSuite
## `AirLayer` (plan P243, ADR 0036 section 15): a flyer has no rig in `UnitLayer` and one in the air
## layer, whose hull is lifted by its sheet's `fly_px` (`low_fly_px` for a drone squad) over a
## shadow that stays on the ground; an enemy flyer shows only on a tile the local player sees; the
## hover bobs on match time and holds still with reduced effects; the hull turns to where the
## flyer moves; a flyer that dies in sight falls and its rig returns to the pool. The page and the
## batch are test_air_layer_batch.gd's. The runner is paused and not in the tree: only the calls
## here move time. Own fighter: unit 3 (row 2) at tile (8, 8); enemy drone: unit 4 (row 3).

const Air: GDScript = preload("res://tests/view/support/air_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const Frames: GDScript = preload("res://tests/view/support/rig_frames.gd")
const FIGHTER_ID: int = Air.FIGHTER_ID
const DRONE_ID: int = Air.DRONE_ID

var _runner: MatchRunner
var _layer: AirLayer
var _life: LifeSettings


func before_test() -> void:
	_runner = auto_free(Air.runner())
	_life = load("res://data/life_settings.tres").duplicate()
	_layer = auto_free(Air.layer(self, _runner))
	_layer.life = _life
	_see_all()
	_render(0.0)


func after_test() -> void:
	CommandQueue.clear()


func test_a_flyer_has_an_air_rig_and_no_unit_rig() -> void:
	var units: UnitLayer = auto_free(UnitLayer.new())
	units.runner = _runner
	var camera: RtsCamera = auto_free(RtsCamera.new())
	add_child(camera)
	units.camera = camera
	add_child(units)
	units.sync_rows()
	assert_int(_layer.rig_count()).is_equal(2)
	var snap: MatchSnapshot = _runner.snapshot
	for row: int in snap.unit_count():
		var flyer: bool = snap.unit_id[row] == FIGHTER_ID or snap.unit_id[row] == DRONE_ID
		assert_bool(units.rig(row) == null).override_failure_message("row %d" % row).is_equal(flyer)
	assert_object(_layer.rig_of(FIGHTER_ID)).is_not_null()
	assert_object(_layer.rig_of(1)).is_null()  # A tank is the sorted world's.


func test_the_layer_is_at_z_20_and_its_shadow_on_the_ground_at_z_2() -> void:
	assert_int(_layer.z_index).is_equal(20)
	assert_bool(_layer.z_as_relative).is_false()
	assert_bool(_layer.y_sort_enabled).is_true()
	var rig: AirLayer.Rig = _layer.rig_of(FIGHTER_ID)
	assert_int(rig.hull.z_index).is_equal(0)  # Relative: 20.
	assert_int(rig.shadow.z_index + _layer.z_index).is_equal(WorldSort.Z_SHADOW)


func test_the_hull_stands_fly_px_above_the_ground_point_and_a_drone_squad_low_fly_px() -> void:
	_life.reduced = true  # No bob: the lift is exact.
	_render(0.0)
	var fighter: AirLayer.Rig = _layer.rig_of(FIGHTER_ID)
	var drone: AirLayer.Rig = _layer.rig_of(DRONE_ID)
	assert_float(fighter.hull.position.y).is_equal(-float(Air.FLY_PX))
	assert_float(drone.hull.position.y).is_equal(-float(Air.LOW_FLY_PX))
	assert_float(fighter.shadow.position.y).is_equal(0.0)  # The shadow stays on the ground.
	var snap: MatchSnapshot = _runner.snapshot
	assert_float(_layer.lift_of_type(snap, snap.type_index[2])).is_equal(float(Air.FLY_PX))
	assert_float(_layer.lift_of_type(snap, snap.type_index[0])).is_equal(0.0)  # A tank.
	var at: Vector2 = IsoProjection.ground_to_px(snap.pos_x[2], snap.pos_y[2])
	assert_vector(fighter.position).is_equal_approx(at, Vector2(0.01, 0.01))


func test_an_enemy_flyer_shows_only_where_its_tile_is_seen_and_an_own_one_always() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	Buildings.see(snap, 1, [Vector2i(8, 8)])  # The fighter's tile, not the drone's.
	_render(0.0)
	assert_bool(_layer.rig_of(FIGHTER_ID).visible).is_true()
	assert_bool(_layer.rig_of(DRONE_ID).visible).is_false()
	Buildings.see(snap, 1, [Vector2i(20, 20)])  # Not the own fighter's tile now.
	_render(0.0)
	assert_bool(_layer.rig_of(FIGHTER_ID).visible).is_true()
	assert_bool(_layer.rig_of(DRONE_ID).visible).is_true()
	_layer.reveal_enemies = true
	Buildings.see(snap, 1, [])
	_render(0.0)
	assert_bool(_layer.rig_of(DRONE_ID).visible).is_true()


func test_the_hover_bobs_within_the_amplitude_on_match_time_and_reduced_holds_still() -> void:
	var rig: AirLayer.Rig = _layer.rig_of(FIGHTER_ID)
	var seen: Dictionary[float, bool] = {}
	for _tick: int in 24:  # 1.6 s, most of a period.
		_runner.run_ticks(1)
		_see_all()
		_render(0.0)
		var offset: float = -rig.hull.position.y - float(Air.FLY_PX)
		assert_float(absf(offset)).is_less_equal(AirLayer.BOB_PX + 0.001)
		seen[snappedf(offset, 0.01)] = true
	assert_int(seen.size()).is_greater(4)
	_life.reduced = true
	_render(0.0)
	assert_float(rig.hull.position.y).is_equal(-float(Air.FLY_PX))
	_runner.run_ticks(3)
	_see_all()
	_render(0.0)
	assert_float(rig.hull.position.y).is_equal(-float(Air.FLY_PX))


func test_two_flyers_bob_out_of_step_by_their_ids() -> void:
	var a: int = LifeClock.pick(FIGHTER_ID, AirLayer.SALT_BOB, AirLayer.BOB_MS)
	assert_int(_layer.rig_of(FIGHTER_ID).phase_ms).is_equal(a)
	assert_int(_layer.rig_of(DRONE_ID).phase_ms).is_not_equal(a)


func test_the_hull_and_its_shadow_turn_to_where_the_flyer_moves() -> void:
	_life.reduced = true
	CommandQueue.submit(Command.move(1, PackedInt32Array([FIGHTER_ID]), 8000, 30000))
	for _tick: int in 30:  # Due +y on the grid, a quarter turn from east.
		_runner.run_ticks(1)
		_see_all()
		_render(0.1)  # 0.1 s a frame: the hull turns 1.2 rad of the 1.57.
	var rig: AirLayer.Rig = _layer.rig_of(FIGHTER_ID)
	assert_float(rig.heading).is_equal_approx(PI / 2.0, 0.05)  # The aim is the last step's.
	var want: int = Frames.of_angle(PI / 2.0, 8)
	var atlas: IsoAtlas = _layer.world_sort.atlas
	var slot: int = _layer.world_sort.slot_of(1)
	for part: StringName in [&"hull", &"shadow"]:
		var sprite: Sprite2D = rig.hull if part == &"hull" else rig.shadow
		var region: Rect2i = atlas.region(Air.FIGHTER, part, want, slot)
		assert_bool(region.has_area()).is_true()
		assert_that(Rect2i(sprite.region_rect)).override_failure_message(part).is_equal(region)


func test_a_hovering_flyer_keeps_its_heading() -> void:
	var rig: AirLayer.Rig = _layer.rig_of(FIGHTER_ID)
	rig.heading = 1.0
	rig.aim = 1.0
	_runner.run_ticks(3)
	_see_all()
	_render(0.5)
	assert_float(rig.heading).is_equal(1.0)


func test_a_flyer_that_dies_in_sight_falls_and_its_rig_goes_back_to_the_pool() -> void:
	_life.reduced = true
	var rig: AirLayer.Rig = _layer.rig_of(FIGHTER_ID)
	var made: int = _layer.rigs_made()
	_runner.world.hp[2] = 0
	_runner.run_ticks(1)
	_see_all()
	_render(0.0)
	assert_int(_layer.falling_count()).is_equal(1)
	assert_int(_layer.rig_count()).is_equal(1)  # The drone only; the faller is not a row.
	assert_object(_layer.rig_of(FIGHTER_ID)).is_null()
	var low: float = -rig.hull.position.y
	var last: float = float(Air.FLY_PX) + 1.0
	for _tick: int in 6:
		_runner.run_ticks(1)
		_render(0.0)
		var height: float = -rig.hull.position.y
		assert_float(height).is_less(last)  # It sinks every tick...
		last = height
	assert_float(low).is_greater(last)
	assert_vector(rig.position).is_not_equal(rig.origin)  # ...and drifts along its heading.
	assert_int(_layer.falling_count()).is_equal(1)
	for _tick: int in 6:  # Past FALL_MS (700 ms is about 10.5 ticks).
		_runner.run_ticks(1)
		_render(0.0)
	assert_int(_layer.falling_count()).is_equal(0)
	assert_object(rig.get_parent()).is_not_same(_layer)  # In the pool, no longer drawn.
	assert_object(rig.hull.texture).is_null()
	# The next flyer takes the pooled rig; none is made.
	_runner.world.hp[2] = 0
	_runner.run_ticks(1)
	_render(0.0)
	assert_int(_layer.rigs_made()).is_equal(made)


func test_a_flyer_that_dies_out_of_sight_does_not_fall() -> void:
	Buildings.see(_runner.snapshot, 1, [])
	_render(0.0)
	_runner.world.hp[3] = 0  # The enemy drone, in the dark.
	_runner.run_ticks(1)
	Buildings.see(_runner.snapshot, 1, [])
	_render(0.0)
	assert_int(_layer.falling_count()).is_equal(0)
	assert_object(_layer.rig_of(DRONE_ID)).is_null()
	assert_int(_layer.rig_count()).is_equal(1)


func test_another_match_starts_with_the_flyers_of_the_new_one() -> void:
	_runner.start()
	_see_all()
	_render(0.0)
	assert_int(_layer.rig_count()).is_equal(2)
	assert_int(_layer.falling_count()).is_equal(0)


func test_a_flyer_without_art_is_a_marker_at_the_default_lift() -> void:
	var fresh: MatchRunner = auto_free(Air.runner())
	var bare: AirLayer = auto_free(AirLayer.new())
	bare.runner = fresh
	bare.life = _life
	add_child(bare)
	bare.set_process(false)
	bare._process(0.0)
	var rig: AirLayer.Rig = bare.rig_of(FIGHTER_ID)
	assert_object(rig).is_not_null()
	assert_bool(rig.marker.visible).is_true()
	assert_bool(rig.hull.visible).is_false()
	assert_float(rig.marker.position.y).is_equal_approx(-AirLayer.DEFAULT_FLY_PX, 1.5)


func _see_all() -> void:
	var tiles: Array = []
	for y: int in 32:
		for x: int in 32:
			tiles.append(Vector2i(x, y))
	Buildings.see(_runner.snapshot, 1, tiles)


func _render(delta: float) -> void:
	_layer._process(delta)
