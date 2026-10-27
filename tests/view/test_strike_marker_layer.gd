extends GdUnitTestSuite
## What the strike puts on the ground (plan P112, ADR 0023 section 10): the aim's circle round the
## placed point and, for every player whose rupture is in the air, the warning at its point, from
## the published snapshot and no fog. The ring is the ground circle of the radius in the 2:1
## projection (every point of it is the radius from the centre once it is put back on the ground);
## the warning's radius is the first rupture type's, not the blackout's; a frame is drawn only
## while there is a point to aim or a rupture in the air, and one more when the last of it goes;
## the closing ring and the blink follow the time left. The drawing itself is the engine's, so
## the suite reads what the layer traced (`_ring`) and how often it drew (`draws`).

const Rig: GDScript = preload("res://tests/input/support/strike_rig.gd")
const AT: Vector2 = Vector2(100.0, 200.0)
const POINTS_HALF: int = 24  ## Half of the layer's 48 steps: the opposite side of the circle.

var _world: World
var _runner: MatchRunner
var _aim: StrikeAim
var _layer: StrikeMarkerLayer


func before_test() -> void:
	_world = Rig.world()
	_world.tick = 100
	_runner = auto_free(Rig.runner(Rig.snapshot(_world)))
	_aim = auto_free(StrikeAim.new())
	_aim.runner = _runner
	_layer = auto_free(StrikeMarkerLayer.new())
	_layer.runner = _runner
	_layer.aim = _aim
	add_child(_layer)


func test_the_ring_is_the_ground_circle_of_the_radius_as_a_two_to_one_ellipse() -> void:
	for radius: int in [1000, 3000, 4000]:
		_layer._trace(AT, radius)
		var ring: PackedVector2Array = _layer._ring
		var semi: Vector2 = IsoProjection.ellipse_px(radius)
		assert_vector(ring[0]).is_equal_approx(ring[ring.size() - 1], Vector2.ONE * 0.001)
		assert_float(semi.x / semi.y).is_equal_approx(2.0, 0.001)
		var centre: Vector2i = IsoProjection.px_to_ground(AT)
		for point: Vector2 in ring:
			var ground: Vector2i = IsoProjection.px_to_ground(point)
			var apart: float = Vector2(ground - centre).length()
			(
				assert_float(apart)
				. override_failure_message("r %d: %s" % [radius, point])
				. is_equal_approx(float(radius), 6.0)
			)
		var xs: Array[float] = []
		var ys: Array[float] = []
		for point: Vector2 in ring:
			xs.append(point.x)
			ys.append(point.y)
		assert_float(xs.max() - xs.min()).is_equal_approx(2.0 * semi.x, 0.01)
		assert_float(ys.max() - ys.min()).is_equal_approx(2.0 * semi.y, 0.01)


## The rig's world has a Deep Bore (a rupture, radius 3000) and a Blackout Array (4000): the warning
## is the rupture's, and one of each player's, the enemy's too.
func test_every_players_rupture_in_the_air_is_noticed_with_the_ruptures_radius() -> void:
	var bore: int = Rig.type_of(_world, "fossil_strike")
	var array: int = Rig.type_of(_world, "renew_strike")
	assert_int(_world.type_strike_radius[array]).is_not_equal(_world.type_strike_radius[bore])
	_world.strike_x[1] = 7500
	_world.strike_y[1] = 8500
	_world.strike_tick[1] = _world.tick + 30
	_world.strike_x[2] = 15500
	_world.strike_y[2] = 11500
	_world.strike_tick[2] = _world.tick + 20
	_runner.snapshot = Rig.snapshot(_world)
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_layer.draws).is_greater(0)
	assert_array(_layer._first.keys()).contains_exactly_in_any_order([130, 120])
	# On the first frame the closing ring is whole: the last ring traced is the rupture's circle.
	var ring: PackedVector2Array = _layer._ring
	var half: float = (ring[0].x - ring[POINTS_HALF].x) * 0.5
	assert_float(half).is_equal_approx(
		IsoProjection.ellipse_px(_world.type_strike_radius[bore]).x, 0.5
	)


func test_nothing_is_drawn_without_a_point_or_a_rupture_and_one_last_frame_clears_it() -> void:
	await await_idle_frame()
	await await_idle_frame()
	var idle: int = _layer.draws  # The engine draws a node once as it enters the tree.
	await await_idle_frame()
	assert_int(_layer.draws).is_equal(idle)
	_world.tick = Rig.fire_tick(_world, Rig.BORE_A)
	_runner.snapshot = Rig.snapshot(_world)
	_aim.refresh()
	_aim.begin()
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_layer.draws).is_equal(idle)  # Aiming with no point draws nothing.
	_aim.place(Vector2i(7500, 8500))
	await await_idle_frame()
	await await_idle_frame()
	var drawn: int = _layer.draws
	assert_int(drawn).is_greater(idle)
	_aim.cancel()
	await await_idle_frame()
	await await_idle_frame()
	await await_idle_frame()
	var cleared: int = _layer.draws
	assert_int(cleared).is_greater(drawn)  # The frame that drew nothing.
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_layer.draws).is_equal(cleared)
	assert_dict(_layer._first).is_empty()


func test_the_aims_ring_is_the_radius_of_the_building_that_fires() -> void:
	_world.tick = Rig.fire_tick(_world, Rig.ARRAY)
	_world.ready_tick[_world.index_of(Rig.BORE_A)] += 5000
	_world.ready_tick[_world.index_of(Rig.BORE_B)] += 5000
	_runner.snapshot = Rig.snapshot(_world)
	_aim.refresh()
	_aim.begin()
	_aim.place(Vector2i(7500, 8500))
	await await_idle_frame()
	await await_idle_frame()
	var ring: PackedVector2Array = _layer._ring
	var array: int = Rig.type_of(_world, "renew_strike")
	var semi: Vector2 = IsoProjection.ellipse_px(_world.type_strike_radius[array])
	assert_float((ring[0].x - ring[POINTS_HALF].x) * 0.5).is_equal_approx(semi.x, 0.5)
	var centre: Vector2 = IsoProjection.ground_to_px(7500, 8500)
	assert_vector((ring[0] + ring[POINTS_HALF]) * 0.5).is_equal_approx(centre, Vector2.ONE * 0.5)


## The closing ring is the whole radius when the warning was first seen and none at the landing,
## linear between; the triangle is on for the first half of each blink and off for the second.
func test_the_closing_ring_follows_the_time_left_and_the_triangle_blinks() -> void:
	assert_int(StrikeMarkerLayer.closing_radius(3000, 45.0, 45.0)).is_equal(3000)
	assert_int(StrikeMarkerLayer.closing_radius(3000, 22.5, 45.0)).is_equal(1500)
	assert_int(StrikeMarkerLayer.closing_radius(3000, 0.0, 45.0)).is_equal(0)
	assert_int(StrikeMarkerLayer.closing_radius(3000, 60.0, 45.0)).is_equal(3000)  # Never wider.
	assert_int(StrikeMarkerLayer.closing_radius(3000, 10.0, 0.0)).is_equal(3000)  # No span.
	var on: Array[bool] = []
	for step: int in 8:
		on.append(StrikeMarkerLayer.blinks_on(float(step)))
	assert_array(on).is_equal([true, true, false, false, true, true, false, false])


## The first sight of a landing is kept while it is in the air, so the ring closes from it.
func test_the_time_left_at_the_first_sight_is_kept_until_the_landing() -> void:
	_world.strike_x[2] = 15500
	_world.strike_y[2] = 11500
	_world.strike_tick[2] = _world.tick + 45
	_runner.snapshot = Rig.snapshot(_world)
	await await_idle_frame()
	await await_idle_frame()
	assert_float(_layer._first[145]).is_equal_approx(45.0, 0.01)
	_world.tick += 20
	_runner.snapshot = Rig.snapshot(_world)
	await await_idle_frame()
	await await_idle_frame()
	assert_float(_layer._first[145]).is_equal_approx(45.0, 0.01)
	_world.strike_tick[2] = 0
	_runner.snapshot = Rig.snapshot(_world)
	await await_idle_frame()
	await await_idle_frame()
	assert_dict(_layer._first).is_empty()
