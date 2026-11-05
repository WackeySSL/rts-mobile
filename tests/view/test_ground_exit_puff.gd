extends GdUnitTestSuite
## The dust puff at a factory's exit (plan P150, ADR 0027 sections 3 and 6): a SPAWNED record of a
## vehicle or a squad leaves one puff of `GroundFx`'s dust at the point it carries; a building (a
## site), a spawn on a tile the local player does not see and one outside the view rect leave none;
## a DIED record, cancelled or not, draws nothing; `reduced` drops it; it takes slots of the dust
## ring only. Fixtures: recoil_rig.gd (a light tank, a heavy tank, a squad, a Redoubt, an enemy tank
## far away).

const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const TOL: Vector2 = Vector2(0.01, 0.01)
const START: int = 100

var _runner: MatchRunner
var _camera: RtsCamera
var _life: LifeSettings
var _layer: GroundFx


func before_test() -> void:
	_runner = auto_free(Rig.runner())
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_life = LifeSettings.new()
	_layer = auto_free(GroundFx.new())
	_layer.runner = _runner
	_layer.camera = _camera
	_layer.life = _life
	add_child(_layer)
	_layer.set_process(false)
	_camera.position = _spot(Vector2i(10500, 10500))


func after_test() -> void:
	CommandQueue.clear()


func test_a_made_vehicle_leaves_one_dust_puff_at_the_exit_it_carries() -> void:
	_spawn(Rig.LIGHT, Vector2i(11500, 10500), 1)
	assert_int(_layer.slot_count()).is_equal(1)
	assert_vector(_layer.puff_at(0)).is_equal_approx(_spot(Vector2i(11500, 10500)), TOL)
	assert_int(_layer.puff_born(0)).is_equal(START)
	var want: int = LifeClock.pick(Rig.LIGHT, GroundFx.SALT_EXIT + START, 3)
	_layer._process(0.0)
	assert_int(_layer.quad_count()).is_equal(1)
	assert_int(_layer.quad_frame(0)).is_equal(want)


func test_a_made_squad_leaves_one_too_and_a_made_site_or_defence_none() -> void:
	_spawn(Rig.SQUAD, Vector2i(10500, 11500), 1)
	assert_int(_layer.slot_count()).is_equal(1)
	_spawn(Rig.REDOUBT, Vector2i(10500, 11500), 1)  # A building has no exit.
	assert_int(_layer.slot_count()).is_equal(1)


func test_a_spawn_on_an_unseen_tile_leaves_none_until_the_tile_is_seen() -> void:
	var far: Vector2i = Rig.centre(Rig.FAR_TILE)
	_camera.position = _spot(far)
	_spawn(Rig.ENEMY_TANK, far, 2)
	assert_int(_layer.slot_count()).is_equal(0)
	Buildings.see(_runner.snapshot, 1, [Rig.FAR_TILE])
	_spawn(Rig.ENEMY_TANK, far, 2)
	assert_int(_layer.slot_count()).is_equal(1)
	Buildings.see(_runner.snapshot, 1, [])
	_layer.reveal_enemies = true
	_spawn(Rig.ENEMY_TANK, far, 2)
	assert_int(_layer.slot_count()).is_equal(2)


func test_an_own_spawn_is_shown_whatever_the_fog_says() -> void:
	Buildings.see(_runner.snapshot, 1, [])
	_spawn(Rig.LIGHT, Vector2i(11500, 10500), 1)
	assert_int(_layer.slot_count()).is_equal(1)


func test_a_spawn_outside_the_view_rect_leaves_none() -> void:
	_camera.position = Vector2(1.0e6, 1.0e6)
	_spawn(Rig.LIGHT, Vector2i(11500, 10500), 1)
	assert_int(_layer.slot_count()).is_equal(0)
	_camera.position = _spot(Vector2i(10500, 10500))
	_layer.camera = null
	_spawn(Rig.LIGHT, Vector2i(11500, 10500), 1)
	assert_int(_layer.slot_count()).is_equal(0)


func test_a_died_record_cancelled_or_not_draws_nothing() -> void:
	var type: int = _runner.snapshot.type_index[_runner.snapshot.index_of(Rig.LIGHT)]
	for flag: int in [0, 1]:
		var died: PackedInt32Array = PackedInt32Array(
			[World.Event.DIED, Rig.LIGHT, 10500, 10500, type, 1, flag, 0]
		)
		Rig.deliver(_runner, died, START + flag)
		assert_int(_layer.slot_count()).is_equal(0)


func test_reduced_makes_no_exit_puff_and_the_switch_empties_the_ring() -> void:
	_spawn(Rig.LIGHT, Vector2i(11500, 10500), 1)
	assert_int(_layer.slot_count()).is_equal(1)
	_life.reduced = true
	_layer._process(0.0)
	assert_int(_layer.slot_count()).is_equal(0)
	_spawn(Rig.LIGHT, Vector2i(11500, 10500), 1)
	assert_int(_layer.slot_count()).is_equal(0)


func test_the_exit_puff_is_the_dust_of_the_ring_and_shares_its_quota() -> void:
	assert_int(_life.dust_slots).is_equal(48)
	for count: int in 60:
		_spawn(Rig.LIGHT, Vector2i(11500, 10500), 1, START + count)
	assert_int(_layer.slot_count()).is_equal(48)
	_life.dust_slots = 0  # Dust off: no exit puff either.
	_layer._process(0.0)
	_spawn(Rig.LIGHT, Vector2i(11500, 10500), 1)
	assert_int(_layer.slot_count()).is_equal(0)


func test_the_exit_puff_does_not_need_the_travel_dust() -> void:
	_life.dust_every_milli = 0
	_spawn(Rig.LIGHT, Vector2i(11500, 10500), 1)
	assert_int(_layer.slot_count()).is_equal(1)


# Delivers a tick with the SPAWNED record of unit `id` at `at` (milli-tiles) for `owner`.
func _spawn(id: int, at: Vector2i, owner: int, tick: int = START) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var type: int = snap.type_index[snap.index_of(id)]
	var spawned: PackedInt32Array = PackedInt32Array(
		[World.Event.SPAWNED, id, at.x, at.y, type, owner, 0, 0]
	)
	Rig.deliver(_runner, spawned, tick)


func _spot(at: Vector2i) -> Vector2:
	return IsoProjection.ground_to_px(at.x, at.y)
