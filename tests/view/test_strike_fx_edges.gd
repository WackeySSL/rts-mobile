extends GdUnitTestSuite
## The edges of `StrikeFx` and its net (plan P141 review, ADR 0027 sections 3 and 6): the net
## settles as a ring, the ring, one lattice per radius, a lance held until the tick of its landing,
## a fall that a pan does not slide, a point above the view, slot reuse, and a real SUPERWEAPON
## command through the runner. The fixture is test_strike_fx.gd's.

const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const SizedCamera: GDScript = preload("res://tests/view/support/sized_camera.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const BORE: int = 1
const ARRAY: int = 2
const ENEMY_ARRAY: int = 3
const RUPTURE: int = 1
const BLACKOUT: int = 2
const T0: int = 100  ## The tick of the event.
const POINT: Vector2i = Vector2i(20500, 20500)  ## Tile (20, 20), dark.
const SEEN_TILE: Vector2i = Vector2i(20, 20)
const ENEMY_TILE: Vector2i = Vector2i(26, 26)
const TOL: float = 0.01
const EPS: float = 0.01
const RING: int = StrikeFx.Part.RING
const FLASH: int = StrikeFx.Part.FLASH
const CORE: int = StrikeFx.Part.CORE
const LANCE_UP: int = StrikeFx.Part.LANCE_UP
const LANCE_DOWN: int = StrikeFx.Part.LANCE_DOWN
const TRAIL: int = StrikeFx.Part.TRAIL
const SHADOW: int = StrikeFx.Part.SHADOW
const SEED: int = StrikeFx.Part.SEED
const SEED_TRAIL: int = StrikeFx.Part.SEED_TRAIL
const GLINT: int = StrikeFx.Part.GLINT
const HEX_LIT: int = StrikeFx.Part.HEX_LIT

var _runner: MatchRunner
var _camera: RtsCamera
var _buildings: BuildingLayer
var _life: LifeSettings
var _layer: StrikeFx


func test_the_ring_is_the_closed_hexagons_of_the_cells_on_the_boundary() -> void:
	var axes: Vector2 = IsoProjection.ellipse_px(_radius(ARRAY))
	var net: StrikeNet = StrikeNet.new()
	var ring: PackedVector2Array = net.ring(net.lattice_for(axes))
	assert_int(ring.size()).is_greater(0)
	assert_int(ring.size() % 12).is_equal(0)  # Six edges of two ends for each cell.
	var offsets: Array[Vector2] = [
		Vector2(0.0, -LifeRegions.NET_ROW_PX),
		Vector2(0.0, LifeRegions.NET_ROW_PX),
		Vector2(LifeRegions.NET_COLUMN_PX, -LifeRegions.NET_SHIFT_PX),
		Vector2(LifeRegions.NET_COLUMN_PX, LifeRegions.NET_SHIFT_PX),
		Vector2(-LifeRegions.NET_COLUMN_PX, -LifeRegions.NET_SHIFT_PX),
		Vector2(-LifeRegions.NET_COLUMN_PX, LifeRegions.NET_SHIFT_PX),
	]
	var boundary: int = 0
	var inside: int = 0
	for col: int in range(-12, 13):
		for row: int in range(-12, 13):
			var c: Vector2 = StrikeNet.centre_of(col, row)
			if not _in_ellipse(c, axes):
				continue
			inside += 1
			for offset: Vector2 in offsets:
				if not _in_ellipse(c + offset, axes):
					boundary += 1
					break
	assert_int(ring.size() / 12).is_equal(boundary)
	assert_int(boundary).is_less(inside)  # An interior is left to fade.
	assert_int(boundary).is_greater(inside / 4)


func test_the_net_settles_as_a_ring_the_ring_brighter_than_the_interior_while_it_fades() -> void:
	_fire(ARRAY, BLACKOUT, 0)
	_frame(T0 + 9, EPS)  # Just landed: both at the same alpha.
	assert_float(_layer.net_ring_alpha(0)).is_equal_approx(_layer.net_alpha(0), 0.05)
	for step: int in [1, 2, 3]:
		_frame(T0 + 9 + step * 2, 0.5)  # 1/4 of the settle after 125 ms, and so on, to the end.
		assert_float(_layer.net_ring_alpha(0)).is_greater(_layer.net_alpha(0))
		assert_float(_layer.net_alpha(0)).is_greater(0.0)


func test_two_nets_of_two_radii_each_draw_their_own_lattice() -> void:
	_fire(ARRAY, BLACKOUT, 0)
	var snap: MatchSnapshot = _runner.snapshot
	var type: int = snap.type_index[_row(ARRAY)]
	var radius: int = snap.type_strike_radius[type]
	snap.type_strike_radius[type] = radius / 2
	_fire(ARRAY, BLACKOUT, 0)  # The same building type, another radius, alive at once.
	snap.type_strike_radius[type] = radius
	_frame(T0 + 4, 0.5)
	assert_int(_layer.net_count()).is_equal(2)
	var nets: StrikeNet = _layer.nets()
	assert_int(nets.lattice_count()).is_equal(2)
	assert_int(nets.lattice_of(0)).is_not_equal(nets.lattice_of(1))
	assert_int(nets.edges(nets.lattice_of(0)).size()).is_not_equal(
		nets.edges(nets.lattice_of(1)).size()
	)
	var wide: PackedVector2Array = nets.edges(nets.lattice_of(0))
	var narrow: PackedVector2Array = nets.edges(nets.lattice_of(1))
	assert_int(wide.size()).is_greater(narrow.size())  # Slot 0 keeps its larger net.


func test_a_rupture_whose_clock_has_reached_the_landing_but_not_its_tick_keeps_its_lance() -> void:
	_fire(BORE, RUPTURE, T0 + 45)
	_frame(T0 + 44, 0.99)
	assert_array(_parts()).is_equal([SHADOW, TRAIL, LANCE_DOWN])
	# A late worker holds alpha at 1.0: the clock is the landing time, the snapshot still tick 144.
	_frame(T0 + 44, 1.0)
	assert_array(_parts()).is_equal([SHADOW, TRAIL, LANCE_DOWN])
	assert_int(_layer.slot_count()).is_equal(1)
	var ground: Vector2 = IsoProjection.ground_to_px(POINT.x, POINT.y)
	assert_float(_anchor_of(2, &"lance_down").y).is_equal_approx(ground.y, TOL)  # On the ground.
	_frame(T0 + 45, 0.0)  # The tick arrives with its burst: gone.
	assert_int(_layer.quad_count()).is_equal(0)
	assert_int(_layer.slot_count()).is_equal(0)


func test_a_rupture_that_lands_in_its_own_step_at_a_hidden_building_takes_no_slot() -> void:
	for index: int in 8:  # Eight live strikes fill the ring.
		_fire_on(T0, BORE, RUPTURE, T0 + 100 + index, 1, POINT)
	assert_int(_layer.slot_count()).is_equal(8)
	var span: Vector2 = _layer.fall_span(0)
	_fire(ENEMY_ARRAY, RUPTURE, T0, 2)  # Lands now, from a building in the dark.
	assert_int(_layer.slot_count()).is_equal(8)
	assert_vector(_layer.fall_span(0)).is_equal(span)  # Nothing was overwritten.


func test_a_pan_or_a_pinch_during_the_fall_does_not_slide_the_lance_against_the_ground() -> void:
	_fire(BORE, RUPTURE, T0 + 45)
	_frame(T0 + 36, 0.0)  # The first planned frame fixes where the fall starts.
	var start: Vector2 = _anchor_of(2, &"lance_down")
	_camera.position += Vector2(0.0, 300.0)  # Panned south: the top edge is far lower now.
	_camera.zoom = Vector2(1.5, 1.5)
	_frame(T0 + 40, 0.5)
	var ground: Vector2 = IsoProjection.ground_to_px(POINT.x, POINT.y)
	assert_float(_anchor_of(2, &"lance_down").y).is_equal_approx(
		lerpf(start.y, ground.y, 0.25), TOL
	)
	assert_float(_anchor_of(2, &"lance_down").x).is_equal_approx(ground.x, TOL)


func test_a_point_above_the_visible_top_edge_falls_from_above_the_point_itself() -> void:
	var ground: Vector2 = IsoProjection.ground_to_px(POINT.x, POINT.y)
	_camera.position = ground + Vector2(0.0, 400.0)  # The top edge is 40 px south of the point.
	assert_float(_camera.visible_world_rect().position.y).is_greater(ground.y + 30.0)
	_fire(BORE, RUPTURE, T0 + 45)
	_frame(T0 + 36, 0.0)
	assert_float(_layer.quad_rect(2).end.y).is_equal_approx(ground.y, TOL)  # Not the top edge.
	_start_again()
	_fire(ARRAY, BLACKOUT, 0)
	_frame(T0, 0.0)
	var rows: float = IsoProjection.ellipse_px(_radius(ARRAY)).y + LifeRegions.NET_SHIFT_PX
	var foot: float = (
		_layer.net_at(0).y + rows * _layer.net_scale(0) + LifeRegions.NET_EDGE_PX * 0.5
	)
	assert_float(foot).is_equal_approx(ground.y, TOL)


func test_a_free_slot_is_reused_before_a_live_one_is_overwritten() -> void:
	_fire_on(T0, BORE, RUPTURE, T0, 1, POINT)  # Slot 0: a launch alone, 700 ms.
	var far: Vector2i = Vector2i(8500, 8500)
	_fire_on(T0 + 1, BORE, RUPTURE, T0 + 100, 1, far)  # Slot 1: a long fall.
	_frame(T0 + 11, 0.6)  # Slot 0 is over and freed; slot 1 lives.
	assert_int(_layer.slot_count()).is_equal(1)
	_fire_on(T0 + 11, BORE, RUPTURE, T0 + 111, 1, Vector2i(5500, 5500))
	var want: Vector2 = IsoProjection.ground_to_px(5500, 5500)
	assert_vector(_layer.landing_point(0)).is_equal_approx(want, Vector2(TOL, TOL))
	assert_vector(_layer.landing_point(1)).is_equal_approx(
		IsoProjection.ground_to_px(far.x, far.y), Vector2(TOL, TOL)
	)


func test_a_real_superweapon_command_reaches_the_layer_and_a_dropped_one_does_not() -> void:
	var world: World = _runner.world
	world.ready_tick[world.index_of(BORE)] = 0  # Charged, so the command is taken.
	_runner.run_ticks(1)
	assert_int(_layer.slot_count()).is_equal(0)
	CommandQueue.submit(Command.superweapon(1, BORE, POINT.x, POINT.y))
	_runner.run_ticks(1)
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(_layer.slot_count()).is_equal(1)
	assert_int(snap.strike_tick[1]).is_greater(snap.tick)
	var land: float = LifeClock.tick_ms(snap.strike_tick[1])
	assert_float(_layer.fall_span(0).y).is_equal_approx(land, TOL)
	assert_vector(_layer.landing_point(0)).is_equal_approx(
		IsoProjection.ground_to_px(POINT.x, POINT.y), Vector2(TOL, TOL)
	)
	CommandQueue.submit(Command.superweapon(1, BORE, POINT.x, POINT.y))  # Charging again: dropped.
	_runner.run_ticks(1)
	assert_int(_layer.slot_count()).is_equal(1)


func test_a_new_match_empties_the_ring() -> void:
	_fire(BORE, RUPTURE, T0 + 45)
	assert_int(_layer.slot_count()).is_equal(1)
	_runner.snapshot.match_serial += 1
	_frame(T0 + 1, 0.0)
	assert_int(_layer.slot_count()).is_equal(0)
	assert_int(_layer.quad_count()).is_equal(0)


func test_a_long_run_of_strikes_makes_no_object_and_no_node() -> void:
	for index: int in 40:  # Warm up: the arrays are made, the lattice is built.
		_fire_on(T0 + index * 2, ARRAY, BLACKOUT, 0, 1, POINT)
		_frame(T0 + index * 2 + 1, 0.5)
	var objects: int = roundi(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes: int = _layer.get_child_count()
	var most: int = 0
	for index: int in range(40, 400):
		var kind: int = RUPTURE if index % 2 == 0 else BLACKOUT
		var building: int = BORE if kind == RUPTURE else ARRAY
		_fire_on(
			T0 + index * 2, building, kind, T0 + index * 2 + 20 if kind == RUPTURE else 0, 1, POINT
		)
		for frame: int in 4:
			_frame(T0 + index * 2 + 1, 0.25 * frame)
			most = maxi(most, _layer.quad_count())
	assert_int(roundi(Performance.get_monitor(Performance.OBJECT_COUNT))).is_equal(objects)
	assert_int(_layer.get_child_count()).is_equal(nodes)
	assert_int(most).is_between(1, 8 * StrikeFx.QUADS_PER_SLOT)


func before_test() -> void:
	var spawns: Array[SpawnDef] = [
		Buildings.spawn(1, "fossil_strike", 10, 10),
		Buildings.spawn(1, "renew_strike", 16, 10),
		Buildings.spawn(2, "renew_strike", 26, 26),
	]
	_runner = auto_free(Buildings.runner(Buildings.scenario(spawns)))
	_camera = auto_free(SizedCamera.new())
	add_child(_camera)
	_camera.position = IsoProjection.ground_to_px(POINT.x, POINT.y)
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	add_child(_buildings)
	_buildings.set_process(false)
	_buildings._process(0.0)
	_life = LifeSettings.new()
	_layer = auto_free(StrikeFx.new())
	_layer.runner = _runner
	_layer.camera = _camera
	_layer.life = _life
	_layer.building_layer = _buildings
	add_child(_layer)
	_layer.set_process(false)


func after_test() -> void:
	CommandQueue.clear()


## Delivers a STRIKE record of building `building`, `kind`, landing tick `land` (0 for a blackout),
## fired by player `owner_id` at `point`, as the events of tick `tick`.
func _fire_on(
	tick: int, building: int, kind: int, land: int, owner_id: int, point: Vector2i
) -> void:
	var events: PackedInt32Array = PackedInt32Array(
		[World.Event.STRIKE, building, point.x, point.y, kind, owner_id, land, 0]
	)
	Rig.deliver(_runner, events, tick)


## The same, as the events of tick `T0`.
func _fire(building: int, kind: int, land: int, owner_id: int = 1) -> void:
	_fire_on(T0, building, kind, land, owner_id, POINT)


func _frame(tick: int, alpha: float) -> void:
	Rig.at(_runner, tick, alpha)
	_layer._process(0.0)


## A new match for the layer: its ring and its clock are empty.
func _start_again() -> void:
	_runner.snapshot.match_serial += 1
	Rig.at(_runner, 0, 0.0)
	_layer._process(0.0)


## The part of each quad of the plan.
func _parts() -> Array[int]:
	var found: Array[int] = []
	for index: int in _layer.quad_count():
		found.append(_layer.quad_part(index))
	return found


func _row(id: int) -> int:
	return _runner.snapshot.index_of(id)


func _radius(id: int) -> int:
	var snap: MatchSnapshot = _runner.snapshot
	return snap.type_strike_radius[snap.type_index[_row(id)]]


func _centre(id: int) -> Vector2:
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = _row(id)
	return IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])


## Where the anchor of quad `index` (of kind `kind`) is: its corner plus the anchor's offset.
func _anchor_of(index: int, kind: StringName) -> Vector2:
	return _layer.quad_rect(index).position + LifeRegions.ANCHOR[kind]


## Whether `at` (relative to the net's centre) is inside the ellipse of semi-axes `axes`.
func _in_ellipse(at: Vector2, axes: Vector2) -> bool:
	return (at.x * at.x) / (axes.x * axes.x) + (at.y * at.y) / (axes.y * axes.y) <= 1.0
