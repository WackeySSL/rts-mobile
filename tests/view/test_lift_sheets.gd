extends GdUnitTestSuite
## The lifts of the sorted world (plan P114b, ADR 0023 sections 2 and 3): with a `WorldSort` the
## layers lift by the sheets of its atlas, the numbers `SpriteLift` otherwise takes from its tables
## and class defaults (test_sprite_lift.gd). A bar stands over the sheet's `bar_lift_px`, a shot
## leaves the sheet's `muzzle_lift_px` of the weapon's shooter, a burst is centred on the sheet's
## `pick_lift_px`, and a tap picks a unit round that same lifted centre. The sheets are generated
## data, so their numbers are read from the index (`Lifts`), never typed here.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const Fx: GDScript = preload("res://tests/view/support/effects_rig.gd")
const Lifts: GDScript = preload("res://tests/view/support/lifts.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const TOL: Vector2 = Vector2(0.001, 0.001)

var _runner: MatchRunner
var _camera: RtsCamera
var _sort: WorldSort
var _now_ms: int = 0  ## The frame clock of the effects layers: each delivery is a second later.


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_the_sorted_world_answers_each_weapons_muzzle_from_the_sheet_of_the_type_that_carries_it(
) -> void:
	_start(Fx.battle())
	var snap: MatchSnapshot = _runner.snapshot
	var carriers: Dictionary[StringName, StringName] = {
		&"tank_cannon": &"light_tank", &"rifle": &"rifle_squad", &"rocket": &"rocket_squad"
	}
	for weapon_id: StringName in carriers:
		var weapon: int = snap.weapon_ids.find(weapon_id)
		assert_int(weapon).override_failure_message(String(weapon_id)).is_greater_equal(0)
		assert_float(_sort.muzzle_px(weapon)).override_failure_message(String(weapon_id)).is_equal(
			Lifts.muzzle(carriers[weapon_id])
		)
	assert_float(_sort.muzzle_px(-1)).is_equal(0.0)  # No weapon.
	assert_float(_sort.muzzle_px(snap.weapon_ids.size())).is_equal(0.0)  # Past the table.


func test_a_weapon_that_two_types_share_has_the_muzzle_of_the_first_of_them() -> void:
	# The Lumen Accord's scout carries the light tank's cannon (data/units), with a sheet of its own.
	var scout: Array[SpawnDef] = [
		Rig.spawn(1, "renew_scout", 4, 4), Rig.spawn(1, "light_tank", 6, 4)
	]
	_start(Rig.scenario(scout))
	var weapon: int = _runner.snapshot.weapon_ids.find(&"tank_cannon")
	assert_float(_sort.muzzle_px(weapon)).is_equal(Lifts.muzzle(&"renew_scout"))
	var tank: Array[SpawnDef] = [
		Rig.spawn(1, "light_tank", 4, 4), Rig.spawn(1, "renew_scout", 6, 4)
	]
	_start(Rig.scenario(tank))
	assert_float(_sort.muzzle_px(weapon)).is_equal(Lifts.muzzle(&"light_tank"))


func test_a_shot_and_a_puff_leave_the_muzzle_of_the_sheet_and_without_a_sorted_world_the_tables_row(
) -> void:
	_start(Fx.battle())
	var snap: MatchSnapshot = _runner.snapshot
	var rifle: int = snap.weapon_ids.find(&"rifle")  # Hitscan: its tracer shows the lift at both ends.
	var shooter: Vector2i = Vector2i(10000, 20000)
	var target: Vector2i = Vector2i(14000, 20000)
	var sheet_px: float = Lifts.muzzle(&"rifle_squad")
	var with_world: EffectsLayer = _effects(_sort)
	var without: EffectsLayer = _effects(null)
	for case: Array in [[with_world, sheet_px], [without, SpriteLift.MUZZLE_PX[&"rifle"]]]:
		var layer: EffectsLayer = case[0]
		_deliver(layer, Fx.shot(shooter, target, rifle))
		var lifted: Vector2 = IsoProjection.ground_to_px(target.x, target.y) - Vector2(0.0, case[1])
		assert_vector(layer.line_to(1)).is_equal_approx(lifted, TOL)
		_deliver(layer, Fx.impact(target, rifle))
		assert_vector(layer.quad_rect(0).get_center()).is_equal_approx(lifted, TOL)


func test_a_death_is_centred_on_the_sheets_pick_lift_and_a_type_with_no_sheet_gets_its_class(
) -> void:
	_start(Fx.battle())
	var snap: MatchSnapshot = _runner.snapshot
	var at: Vector2i = Vector2i(15000, 8000)
	var layer: EffectsLayer = _effects(_sort)
	var ground: Vector2 = IsoProjection.ground_to_px(at.x, at.y)
	for type_id: StringName in [&"light_tank", &"rifle_squad", &"rocket_squad"]:
		_deliver(layer, Fx.died(at, snap.type_ids.find(type_id)))
		(
			assert_vector(layer.quad_rect(0).get_center())
			. override_failure_message(String(type_id))
			. is_equal_approx(ground - Vector2(0.0, Lifts.pick(type_id)), TOL)
		)
	snap.type_ids[snap.type_ids.find(&"light_tank")] = &"bullhead"  # A name no sheet has.
	_deliver(layer, Fx.died(at, snap.type_ids.find(&"bullhead")))
	assert_vector(layer.quad_rect(0).get_center()).is_equal_approx(ground - Vector2(0.0, 13.0), TOL)


func test_a_shell_flies_at_the_muzzle_height_of_its_weapons_sheet() -> void:
	_start(Fx.battle())
	var snap: MatchSnapshot = _runner.snapshot
	var shells: ProjectileLayer = auto_free(ProjectileLayer.new())
	shells.runner = _runner
	shells.world_sort = _sort
	shells.reveal_enemies = true
	add_child(shells)
	shells.set_process(false)
	var plain: ProjectileLayer = auto_free(ProjectileLayer.new())
	plain.runner = _runner
	plain.reveal_enemies = true
	add_child(plain)
	plain.set_process(false)
	var cannon: int = snap.weapon_ids.find(&"tank_cannon")
	snap.proj_id[0] = 61
	snap.prev_proj_id[0] = 61
	snap.proj_weapon[0] = cannon
	snap.proj_x[0] = 24000
	snap.proj_y[0] = 24000
	snap.prev_proj_x[0] = 24000
	snap.prev_proj_y[0] = 24000
	shells._process(0.0)
	plain._process(0.0)
	var ground: Vector2 = IsoProjection.ground_to_px(24000, 24000)
	assert_vector(shells.quad_position(0)).is_equal_approx(
		ground - Vector2(0.0, Lifts.muzzle(&"light_tank")), TOL
	)
	assert_vector(plain.quad_position(0)).is_equal_approx(
		ground - Vector2(0.0, SpriteLift.MUZZLE_PX[&"tank_cannon"]), TOL
	)


func test_a_bar_lift_is_the_sheets_top_of_frame_and_a_squads_is_its_own() -> void:
	_start(Fx.battle())
	var units: UnitLayer = _units()
	var snap: MatchSnapshot = _runner.snapshot
	for type_id: StringName in [&"light_tank", &"rifle_squad"]:
		var row: int = Rig.row_of(snap, type_id)
		assert_float(units.bar_lift_px(row)).override_failure_message(String(type_id)).is_equal(
			Lifts.bar(type_id)
		)
	assert_float(units.bar_lift_px(-1)).is_equal(0.0)
	assert_float(units.bar_lift_px(snap.unit_count())).is_equal(0.0)
	var tank: int = Rig.row_of(snap, &"light_tank")
	snap.type_ids[snap.type_index[tank]] = &"bullhead"  # No sheet: the class's default, 26.
	assert_float(units.bar_lift_px(tank)).is_equal(SpriteLift.VEHICLE_BAR_PX)


func test_a_units_pick_centre_is_its_ground_point_lifted_by_the_sheet_at_every_zoom() -> void:
	_start(Fx.battle())
	var units: UnitLayer = _units()
	var snap: MatchSnapshot = _runner.snapshot
	var pick: PickSnapshot = PickSnapshot.new()
	for zoom: float in [0.75, 1.0, 1.5]:
		_camera.zoom = Vector2(zoom, zoom)
		units.fill_pick_snapshot(pick, UiScale.dp(24.0))
		for type_id: StringName in [&"light_tank", &"rifle_squad"]:
			var row: int = Rig.row_of(snap, type_id)
			var lift: float = Lifts.pick(type_id) * zoom
			var note: String = "%s at zoom %s" % [type_id, zoom]
			assert_float(pick.lift_of(row)).override_failure_message(note).is_equal_approx(
				lift, 0.001
			)
			(
				assert_vector(pick.screen_pos[row] + Vector2(0.0, lift))
				. override_failure_message(note)
				. is_equal_approx(units.unit_screen_position(row), TOL)
			)
			assert_float(pick.radius_px[row]).override_failure_message(note).is_greater_equal(
				UiScale.dp(24.0)
			)


func test_a_tap_goes_to_the_unit_whose_lifted_centre_is_nearest_not_the_one_whose_foot_is() -> void:
	# Two tanks of player 1, B standing so that its lifted centre is on A's ground point: a tap on
	# A's foot is on B's centre and A's centre is a lift away from it, so B is picked. With the
	# ground point as the centre, as before P114b, A would be.
	var spawns: Array[SpawnDef] = [
		Rig.spawn(1, "light_tank", 10, 10), Rig.spawn(1, "light_tank", 14, 14)
	]
	_start(Rig.scenario(spawns))
	var units: UnitLayer = _units()
	var snap: MatchSnapshot = _runner.snapshot
	var lift: float = Lifts.pick(&"light_tank")
	# B stands `lift` px below A on the screen: the diagonal step (d, d) is (0, 32 d) px.
	var step: int = roundi(lift / 32.0 * 1000.0)
	snap.pos_x[1] = snap.pos_x[0] + step
	snap.pos_y[1] = snap.pos_y[0] + step
	snap.prev_pos_x[1] = snap.pos_x[1]
	snap.prev_pos_y[1] = snap.pos_y[1]
	units._process(0.0)
	var pick: PickSnapshot = PickSnapshot.new()
	_camera.zoom = Vector2.ONE
	units.fill_pick_snapshot(pick, UiScale.dp(24.0))
	var a_foot: Vector2 = units.unit_screen_position(0)
	assert_int(Picker.pick(pick, a_foot, 1, false)).is_equal(1)  # B, whose centre is right there.
	assert_int(Picker.pick(pick, a_foot - Vector2(0.0, lift), 1, false)).is_equal(0)  # A's body.


## A paused runner on `scenario`, started, with a sorted world synced to its first snapshot.
func _start(scenario: ScenarioDef) -> void:
	_runner = auto_free(Rig.runner(scenario))
	_sort = auto_free(WorldSort.new())
	_sort.runner = _runner
	add_child(_sort)
	_sort.sync()


## A unit layer on the runner's sorted world, its rigs made.
func _units() -> UnitLayer:
	var layer: UnitLayer = auto_free(UnitLayer.new())
	layer.runner = _runner
	layer.camera = _camera
	layer.world_sort = _sort
	layer.reveal_enemies = true
	add_child(layer)
	layer.set_process(false)
	return layer


## An effects layer on the runner, with `sort` for its sheets (null: none).
func _effects(sort: WorldSort) -> EffectsLayer:
	var layer: EffectsLayer = auto_free(EffectsLayer.new())
	layer.runner = _runner
	layer.world_sort = sort
	layer.reveal_enemies = true
	layer.clock = func() -> int: return _now_ms
	add_child(layer)
	layer.set_process(false)
	return layer


## Delivers `events` as the events of a tick to `layer`, a second apart from the last, and plans a
## frame.
func _deliver(layer: EffectsLayer, events: PackedInt32Array) -> void:
	_now_ms += 1000
	_runner.snapshot.events = events
	_runner.ticked.emit(_runner.snapshot.tick)
	layer._process(0.0)
