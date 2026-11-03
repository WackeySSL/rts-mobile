extends GdUnitTestSuite
## The launch and the fall of the superweapons (plan P141, ADR 0027 sections 3, 6 and 7): the lance
## rises at a shown building and falls from above the visible top onto the point in the last
## `fall_ms` before the landing tick, for every player, and is gone at the landing tick; a short
## delay starts the fall at the event; the seed and the net of the Blackout Array show where the
## player sees the point or fired; the ring of 8 slots; the clock that never steps back; `reduced`
## and a new match. The scene and the cost are in test_strike_fx_scene.gd.
## Fixture: the 32 x 32 building match, player 1 the local one with a Deep Bore (id 1, tile 10, 10)
## and a Blackout Array (id 2, tile 16, 10); player 2 a Blackout Array (id 3, tile 26, 26) in the
## dark. The runner is paused and not in the tree: the test sets the snapshot's tick and the alpha,
## delivers a tick's events the way the runner does and calls `_process` for a frame. Events are
## `[STRIKE, building id, x, y, kind, owner, landing tick, 0]`. A frame sits a hundredth of a tick
## past a tick where a time is compared with a sum of times (`EPS`), so a rounding cannot decide.

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


func test_a_lance_rises_from_the_footprint_centre_lifted_by_the_rise_and_fades_in_launch_ms(
) -> void:
	_fire(BORE, RUPTURE, T0 + 45)
	_frame(T0, 0.0)  # Born.
	assert_int(_layer.slot_count()).is_equal(1)
	var centre: Vector2 = _centre(BORE)
	var box: Rect2 = _buildings.frame_box(_row(BORE))
	assert_float(box.position.y).is_less(centre.y - 10.0)  # The picture has a rise.
	var launch: Vector2 = Vector2(centre.x, box.position.y)
	assert_vector(_layer.launch_point(0)).is_equal_approx(launch, Vector2(TOL, TOL))
	assert_array(_parts()).is_equal([RING, FLASH, LANCE_UP])
	assert_vector(_anchor_of(2, &"lance_up")).is_equal_approx(launch, Vector2(TOL, TOL))
	assert_float(_layer.quad_alpha(1)).is_equal_approx(1.0, TOL)  # The flash at full.
	_frame(T0 + 5, 0.25)  # 350 ms of 700: u 0.5, risen 0.75 of the way, 0.75 of the alpha.
	var risen: Vector2 = _anchor_of(2, &"lance_up")
	assert_float(launch.y - risen.y).is_equal_approx(_life.strike_rise_px * 0.75, TOL)
	assert_float(_layer.quad_alpha(2)).is_equal_approx(0.75, TOL)
	assert_float(_layer.quad_alpha(1)).is_equal_approx(0.0, TOL)  # launch_flash_ms is 250.
	_frame(T0 + 10, 0.6)  # Past 700 ms: the launch is over and the fall has not begun.
	assert_int(_layer.quad_count()).is_equal(0)


func test_the_launch_point_is_the_sheets_launch_emitter_when_there_is_one() -> void:
	var type_id: StringName = &"fossil_strike"
	var sheet: IsoSheetDef = _buildings.world_sort.sheet(type_id)
	assert_object(sheet).is_not_null()
	var crafted: IsoSheetDef = sheet.duplicate() as IsoSheetDef
	crafted.emitters = PackedStringArray(["smoke", "launch"])
	crafted.emitter_points = PackedVector2Array([Vector2(4.0, 4.0), Vector2(20.0, -100.0)])
	_buildings.world_sort._sheets[type_id] = crafted
	_fire(BORE, RUPTURE, T0 + 45)
	_frame(T0, 0.0)
	var want: Vector2 = _centre(BORE) + Vector2(10.0, -50.0)  # The 2x art's px, halved.
	assert_vector(_layer.launch_point(0)).is_equal_approx(want, Vector2(TOL, TOL))
	assert_vector(_anchor_of(2, &"lance_up")).is_equal_approx(want, Vector2(TOL, TOL))
	crafted.emitters = PackedStringArray(["smoke"])  # No launch among its emitters: the fallback.
	crafted.emitter_points = PackedVector2Array([Vector2(4.0, 4.0)])
	_fire(BORE, RUPTURE, T0 + 46)
	var box: Rect2 = _buildings.frame_box(_row(BORE))
	assert_vector(_layer.launch_point(1)).is_equal_approx(
		Vector2(_centre(BORE).x, box.position.y), Vector2(TOL, TOL)
	)


func test_the_lance_falls_in_the_last_fall_ms_from_above_the_top_and_is_gone_at_the_landing_tick(
) -> void:
	_fire(BORE, RUPTURE, T0 + 45)
	_frame(T0 + 35, 0.9)  # Before the last 600 ms (tick 136): nothing in the sky.
	assert_int(_layer.quad_count()).is_equal(0)
	_frame(T0 + 36, 0.0)  # The fall begins.
	assert_array(_parts()).is_equal([SHADOW, TRAIL, LANCE_DOWN])
	var top: float = _camera.visible_world_rect().position.y
	var ground: Vector2 = IsoProjection.ground_to_px(POINT.x, POINT.y)
	var start: Vector2 = _anchor_of(2, &"lance_down")
	assert_float(_layer.quad_rect(2).end.y).is_equal_approx(top, TOL)  # Its foot on the top edge.
	assert_float(start.x).is_equal_approx(ground.x, TOL)
	assert_float(_layer.quad_alpha(0)).is_equal_approx(0.0, TOL)  # No shadow yet.
	_frame(T0 + 40, 0.5)  # Half way: t 0.5, eased 0.25 of the way down.
	var now: Vector2 = _anchor_of(2, &"lance_down")
	assert_float(now.y).is_equal_approx(lerpf(start.y, ground.y, 0.25), TOL)
	assert_float(_layer.quad_alpha(0)).is_equal_approx(_life.fall_shadow_alpha * 0.5, TOL)
	var stretch: float = _layer.quad_rect(1).size.y / float(LifeRegions.FIRST[&"trail"].size.y)
	assert_float(stretch).is_equal_approx(1.5, TOL)  # Stretched 1 to 2 times, never more.
	_frame(T0 + 44, 0.99)  # The last frame before the landing tick.
	assert_array(_parts()).is_equal([SHADOW, TRAIL, LANCE_DOWN])
	assert_float(_anchor_of(2, &"lance_down").y).is_less_equal(ground.y + TOL)
	_frame(T0 + 45, 0.0)  # The landing tick: gone, and EffectsLayer's burst is born.
	assert_int(_layer.quad_count()).is_equal(0)
	assert_int(_layer.slot_count()).is_equal(0)


func test_a_delay_shorter_than_fall_ms_starts_the_fall_at_the_event_and_falls_shorter() -> void:
	_fire(BORE, RUPTURE, T0 + 3)  # 200 ms against fall_ms of 600.
	assert_float(_layer.fall_span(0).x).is_equal_approx(LifeClock.tick_ms(T0), TOL)
	assert_float(_layer.fall_span(0).y).is_equal_approx(LifeClock.tick_ms(T0 + 3), TOL)
	_frame(T0, 0.0)  # The launch and the fall's first frame together.
	assert_array(_parts()).is_equal([RING, FLASH, LANCE_UP, SHADOW, TRAIL, LANCE_DOWN])
	_frame(T0 + 1, 0.5)  # 100 of 200 ms: half way, eased 0.25.
	var ground: Vector2 = IsoProjection.ground_to_px(POINT.x, POINT.y)
	var top: float = _camera.visible_world_rect().position.y
	var region: Rect2i = LifeRegions.FIRST[&"lance_down"]
	var below: float = float(region.size.y) - LifeRegions.ANCHOR[&"lance_down"].y
	var from: float = minf(top, ground.y) - below
	assert_float(_anchor_of(5, &"lance_down").y).is_equal_approx(lerpf(from, ground.y, 0.25), TOL)
	_frame(T0 + 3, 0.0)
	assert_array(_parts()).is_equal([RING, FLASH, LANCE_UP])  # Fallen: only the launch is left.


func test_a_rupture_that_lands_in_the_same_step_has_a_launch_and_no_fall() -> void:
	_fire(BORE, RUPTURE, T0)
	for step: int in 4:
		_frame(T0 + step, 0.0)
		assert_array(_parts()).is_equal([RING, FLASH, LANCE_UP])
	_frame(T0 + 11, 0.0)
	assert_int(_layer.slot_count()).is_equal(0)


func test_the_fall_starts_above_the_visible_top_at_the_six_sizes_and_three_zooms() -> void:
	assert_array(ScreenSizes.ALL).has_size(6)
	var ground: Vector2 = IsoProjection.ground_to_px(POINT.x, POINT.y)
	var net_radius: int = _radius(ARRAY)
	var axes: Vector2 = IsoProjection.ellipse_px(net_radius)
	for size: Vector2i in ScreenSizes.ALL:
		for zoom: float in [0.75, 1.0, 1.5]:
			_camera.set(&"screen", Vector2(size))
			_camera.zoom = Vector2(zoom, zoom)
			# The second view puts the point 10 px under the top edge, so little sky is above it.
			for near: bool in [false, true]:
				var half_height: float = Vector2(size).y / zoom * 0.5
				_camera.position = ground + Vector2(0.0, half_height - 10.0 if near else 0.0)
				var note: String = "%s zoom %s near %s" % [size, zoom, near]
				_start_again()
				_fire(BORE, RUPTURE, T0 + 45)
				_frame(T0 + 36, 0.0)
				var top: float = _camera.visible_world_rect().position.y
				assert_array(_parts()).override_failure_message(note).has_size(3)
				var lance: Rect2 = _layer.quad_rect(2)
				assert_float(lance.end.y).override_failure_message(note).is_less_equal(top + TOL)
				_start_again()
				_fire(ARRAY, BLACKOUT, 0)
				_frame(T0, 0.0)  # The net's first frame: all of it above the edge.
				assert_int(_layer.net_count()).override_failure_message(note).is_equal(1)
				var rows: float = (axes.y + LifeRegions.NET_SHIFT_PX) * _layer.net_scale(0)
				var foot: float = _layer.net_at(0).y + rows + LifeRegions.NET_EDGE_PX * 0.5
				assert_float(foot).override_failure_message(note).is_less_equal(top + TOL)


func test_an_enemy_rupture_falls_for_every_player_but_its_launch_shows_only_in_sight() -> void:
	_fire(ENEMY_ARRAY, RUPTURE, T0 + 45, 2)  # Fired from a building in the dark.
	_frame(T0, 0.0)
	assert_int(_layer.quad_count()).is_equal(0)  # No launch.
	assert_int(_layer.slot_count()).is_equal(1)  # But the fall is kept.
	_frame(T0 + 36, 0.0)
	assert_array(_parts()).is_equal([SHADOW, TRAIL, LANCE_DOWN])


func test_an_enemy_building_in_sight_shows_its_launch() -> void:
	Buildings.see(_runner.snapshot, 1, [ENEMY_TILE])
	assert_bool(_buildings.is_shown(_row(ENEMY_ARRAY))).is_true()
	_fire(ENEMY_ARRAY, RUPTURE, T0 + 45, 2)
	_frame(T0, 0.0)
	assert_array(_parts()).is_equal([RING, FLASH, LANCE_UP])
	_start_again()
	_fire(ENEMY_ARRAY, BLACKOUT, 0, 2)  # Its point is dark, the building is not.
	_frame(T0, 0.0)
	assert_array(_parts()).is_equal([CORE, SEED_TRAIL, SEED])
	assert_int(_layer.net_count()).is_equal(0)


func test_a_seed_rises_and_a_net_falls_onto_the_spot_when_the_player_fired_it() -> void:
	_fire(ARRAY, BLACKOUT, 0)  # Player 1's own Blackout Array at a dark point.
	_frame(T0, 0.0)
	assert_array(_parts()).is_equal([CORE, SEED_TRAIL, SEED])
	assert_int(_layer.net_count()).is_equal(1)
	assert_float(_layer.net_alpha(0)).is_equal_approx(0.0, TOL)  # Born: fades in.
	assert_float(_layer.net_scale(0)).is_equal_approx(_life.net_scale_from, TOL)
	_frame(T0 + 4, 0.5)  # 300 ms of 600.
	assert_float(_layer.net_alpha(0)).is_equal_approx(_life.net_alpha * 0.5, 0.001)
	var scale_now: float = lerpf(_life.net_scale_from, 1.0, 0.25)  # Eased 0.25.
	assert_float(_layer.net_scale(0)).is_equal_approx(scale_now, 0.001)
	var ground: Vector2 = IsoProjection.ground_to_px(POINT.x, POINT.y)
	assert_float(_layer.net_at(0).x).is_equal_approx(ground.x, TOL)
	assert_float(_layer.net_at(0).y).is_less(ground.y)
	_frame(T0 + 9, EPS)  # 600 ms: landed, full size, the landing flash and four glints.
	assert_int(_layer.net_count()).is_equal(1)
	assert_vector(_layer.net_at(0)).is_equal_approx(ground, Vector2(TOL, TOL))
	assert_float(_layer.net_scale(0)).is_equal_approx(1.0, TOL)
	assert_float(_layer.net_alpha(0)).is_equal_approx(_life.net_alpha, 0.05)
	# The seed still rises (700 ms), so its three quads come first.
	assert_array(_parts()).is_equal([CORE, SEED_TRAIL, SEED, HEX_LIT, GLINT, GLINT, GLINT, GLINT])
	var axes: Vector2 = IsoProjection.ellipse_px(_radius(ARRAY))  # The firing type's radius.
	var east: Vector2 = ground + Vector2(axes.x, 0.0)
	var north: Vector2 = ground - Vector2(0.0, axes.y)
	assert_vector(_layer.quad_rect(4).get_center()).is_equal_approx(east, Vector2(TOL, TOL))
	assert_vector(_layer.quad_rect(7).get_center()).is_equal_approx(north, Vector2(TOL, TOL))
	_frame(T0 + 12, 0.75)  # 250 ms into the 500 ms settle: half faded; the seed is long gone.
	# The interior fades faster (the square), the ring of boundary cells stays (linear).
	assert_float(_layer.net_alpha(0)).is_equal_approx(_life.net_alpha * 0.25, 0.001)
	assert_float(_layer.net_ring_alpha(0)).is_equal_approx(_life.net_alpha * 0.5, 0.001)
	assert_float(_layer.net_ring_alpha(0)).is_greater(_layer.net_alpha(0))
	assert_float(_layer.quad_alpha(0)).is_equal_approx(0.5, 0.001)
	_frame(T0 + 17, EPS)  # 600 + 500 ms: over.
	assert_int(_layer.net_count()).is_equal(0)
	assert_int(_layer.slot_count()).is_equal(0)


func test_the_net_is_a_closed_lattice_of_hexagons_inside_the_ellipse_of_the_strike_radius() -> void:
	var axes: Vector2 = IsoProjection.ellipse_px(_radius(ARRAY))
	var net: StrikeNet = StrikeNet.new()  # The lattice needs no runner.
	var lattice: int = net.lattice_for(axes)
	assert_int(net.lattice_for(axes)).is_equal(lattice)  # Once for a radius.
	var edges: PackedVector2Array = net.edges(lattice)
	assert_int(edges.size()).is_greater(0)
	assert_int(edges.size() % 2).is_equal(0)
	var area: float = PI * axes.x * axes.y
	var cell_area: float = LifeRegions.NET_COLUMN_PX * LifeRegions.NET_ROW_PX
	var edge_cells: float = float(edges.size()) / 2.0 / 3.0  # About three edges a cell.
	assert_float(edge_cells).is_between(area / cell_area * 0.8, area / cell_area * 1.4)
	var degree: Dictionary[Vector2i, int] = {}
	for index: int in edges.size():
		var at: Vector2 = edges[index]
		var reach: float = (
			(at.x * at.x) / pow(axes.x + 16.0, 2.0) + (at.y * at.y) / pow(axes.y + 8.0, 2.0)
		)
		assert_float(reach).override_failure_message(str(at)).is_less_equal(1.0)
		var key: Vector2i = Vector2i(roundi(at.x * 4.0), roundi(at.y * 4.0))
		degree[key] = degree.get(key, 0) + 1
	for key: Vector2i in degree:  # Every vertex is on two lines or more: no loose end.
		assert_int(degree[key]).override_failure_message(str(key)).is_greater_equal(2)
	# The first edge is a cell's top: sixteen px wide (a hexagon of side 16 has a top of 16).
	assert_vector(edges[1] - edges[0]).is_equal_approx(
		Vector2(LifeRegions.NET_SIDE_PX, 0.0), Vector2(TOL, TOL)
	)


func test_a_net_shows_where_the_point_is_seen_and_not_in_the_dark_unless_the_player_fired() -> void:
	_fire(ENEMY_ARRAY, BLACKOUT, 0, 2)  # An enemy blackout, at a dark point, from a dark building.
	assert_int(_layer.slot_count()).is_equal(0)  # Nothing to show: no slot at all.
	Buildings.see(_runner.snapshot, 1, [SEEN_TILE])
	_fire(ENEMY_ARRAY, BLACKOUT, 0, 2)
	assert_int(_layer.slot_count()).is_equal(1)
	_frame(T0 + 4, 0.5)
	assert_int(_layer.net_count()).is_equal(1)
	assert_int(_layer.quad_count()).is_equal(0)  # The building is dark: no seed.
	_start_again()
	Buildings.see(_runner.snapshot, 1, [])
	_layer.reveal_enemies = true  # The perf arena and the tests that are not about fog.
	_fire(ENEMY_ARRAY, BLACKOUT, 0, 2)
	assert_int(_layer.slot_count()).is_equal(1)
	_start_again()
	_layer.reveal_enemies = false
	_fire(ARRAY, BLACKOUT, 0, 1)  # Fired by the local player: the dark does not matter.
	_frame(T0 + 4, 0.5)
	assert_int(_layer.net_count()).is_equal(1)


func test_the_seed_trail_stretches_to_twice_its_region_and_never_hangs_below_the_launch() -> void:
	_fire(ARRAY, BLACKOUT, 0)
	var launch: Vector2 = _layer.launch_point(0)
	var full: float = float(LifeRegions.FIRST[&"seed_trail"].size.y)
	assert_float(LifeRegions.MAX_STRETCH[&"seed_trail"]).is_equal(2.0)
	_frame(T0, 0.0)  # Nothing has risen yet: no trail.
	assert_float(_layer.quad_rect(1).size.y).is_equal_approx(0.0, TOL)
	_frame(T0 + 5, 0.25)  # u 0.5: risen 72 px, the region would stretch to 96.
	assert_float(_layer.quad_rect(1).size.y).is_equal_approx(_life.strike_rise_px * 0.75, TOL)
	for step: int in 5:
		_frame(T0 + 5 + step, 0.5)
		var trail: Rect2 = _layer.quad_rect(1)
		assert_float(trail.size.y).is_less_equal(full * 2.0)
		assert_float(trail.end.y).is_less_equal(launch.y + TOL)  # Not below where it left.


func test_superweapon_effects_stay_with_reduced() -> void:
	_life.reduced = true
	_fire(BORE, RUPTURE, T0 + 45)
	_frame(T0, 0.0)
	assert_int(_layer.quad_count()).is_equal(3)
	_frame(T0 + 36, 0.0)
	assert_int(_layer.quad_count()).is_equal(3)


func test_a_frame_never_steps_back_after_a_pause() -> void:
	_fire(BORE, RUPTURE, T0 + 45)
	_frame(T0 + 40, 0.5)
	var rect: Rect2 = _layer.quad_rect(2)
	var alpha: float = _layer.quad_alpha(0)
	_frame(T0 + 40, 0.0)  # WORKER mode restarts alpha at 0 after a pause: the clock is a step back.
	assert_that(_layer.quad_rect(2)).is_equal(rect)
	assert_float(_layer.quad_alpha(0)).is_equal(alpha)
	_frame(T0 + 41, 0.0)  # And on from there.
	assert_float(_layer.quad_rect(2).position.y).is_greater(rect.position.y)


func test_a_tick_without_a_strike_record_makes_nothing() -> void:
	# A dropped SUPERWEAPON writes no record (P133), so the tick holds none: only a shot.
	var shot: PackedInt32Array = PackedInt32Array([World.Event.SHOT, 1, 100, 100, 0, 0, 200, 200])
	Rig.deliver(_runner, shot, T0)
	Rig.deliver(_runner, PackedInt32Array(), T0 + 1)
	_frame(T0 + 1, 0.0)
	assert_int(_layer.slot_count()).is_equal(0)
	assert_int(_layer.quad_count()).is_equal(0)
	assert_int(_layer.net_count()).is_equal(0)
	var odd: PackedInt32Array = PackedInt32Array([World.Event.STRIKE, 1, 1, 1, 0, 1, 0, 0])
	Rig.deliver(_runner, odd, T0 + 2)  # A kind that is neither strike.
	assert_int(_layer.slot_count()).is_equal(0)


func test_the_ring_holds_strike_slots_and_overwrites_the_oldest() -> void:
	assert_int(_life.strike_slots).is_equal(8)
	for index: int in 9:
		_fire_on(T0 + index, BORE, RUPTURE, T0 + 100 + index, 1, POINT)
	assert_int(_layer.slot_count()).is_equal(8)
	# The first strike (landing tick T0 + 100, slot 0) was overwritten by the ninth.
	assert_float(_layer.fall_span(0).y).is_equal_approx(LifeClock.tick_ms(T0 + 108), TOL)
	for slot: int in range(1, 8):
		assert_float(_layer.fall_span(slot).y).is_equal_approx(
			LifeClock.tick_ms(T0 + 100 + slot), TOL
		)
	_frame(T0 + 8, 0.0)  # All eight launches are rising.
	assert_int(_layer.quad_count()).is_equal(24)
	assert_int(_layer.quad_count()).is_less_equal(8 * StrikeFx.QUADS_PER_SLOT)


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
