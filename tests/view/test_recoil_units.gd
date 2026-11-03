extends GdUnitTestSuite
## The turret kick and the hull rock of a vehicle (plan P136, ADR 0027 sections 1, 3 and 6): a
## SHOT of a rig with a turret moves its Turret back along the aim by the weapon's `recoil_px`,
## peaking at `recoil_out_ms` and back on its mount by `recoil_back_ms` (match time since the
## shot), and a weapon with `rock_px` moves the Hull with it. Only child sprites move: the rig's
## node, its picks, its bar anchor and its Shadow stay. A squad does not kick and a hidden enemy
## changes nothing drawn. The fixture is `recoil_rig.gd`: a paused runner, a tick and an alpha set
## by hand (match time = (tick + alpha) x 1000 / 15), SHOTs delivered as `ticked` does. The tank's
## kick is 3 px along a straight line on the screen, in steps of 0.5 px, so its numbers are exact.
## The clock, the table and the settings are in test_recoil_life.gd and test_rig_life.gd.

const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const Frames: GDScript = preload("res://tests/view/support/rig_frames.gd")
const TOL: Vector2 = Vector2(0.001, 0.001)

var _runner: MatchRunner
var _layer: UnitLayer


func before_test() -> void:
	_runner = auto_free(Rig.runner())
	_layer = _make_layer(null)


func after_test() -> void:
	CommandQueue.clear()


func test_a_shot_kicks_the_turret_back_along_the_aim_and_it_returns_to_its_mount() -> void:
	# Straight east on the screen, so the turret goes straight west: 1.5 px at 25 ms (half way to the
	# 3 px peak at 50 ms), then the ease back: 2, 1.5, 1, 0.5 and on its mount at 175 ms. It is
	# written 7 times in all and never again (200 ms is the end; 225 finds no kick).
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var turret: Sprite2D = _rig(row).get_node("Turret")
	var mount: Vector2 = _sheet(row).mount(UnitLayer.D_EAST) * WorldSort.ART_SCALE
	assert_vector(turret.position).is_equal_approx(mount, TOL)
	_shoot(Rig.LIGHT, Rig.EAST_ON_SCREEN, &"tank_cannon")
	assert_int(_layer.kick_count()).is_equal(1)
	_frame(Rig.SHOT_TICK, 0.0)  # The shot's own instant: nothing yet.
	assert_vector(turret.position).is_equal_approx(mount, TOL)
	assert_int(_layer.life_writes()).is_equal(0)
	for index: int in Rig.SAMPLES.size():
		_frame(int(Rig.SAMPLES[index].x), Rig.SAMPLES[index].y)
		var back: float = Rig.TANK_CANNON_BACK[index]
		var note: String = "sample %d" % index
		assert_vector(turret.position).override_failure_message(note).is_equal_approx(
			mount + Vector2(-back, 0.0), TOL
		)
	assert_int(_layer.life_writes()).is_equal(7)
	assert_int(_layer.kick_count()).is_equal(0)
	for _again: int in 5:  # No write once it is home.
		_frame(40, 0.5)
	assert_int(_layer.life_writes()).is_equal(7)


func test_the_kick_goes_away_from_the_target_along_the_aim_as_drawn() -> void:
	# Straight south on the screen: the turret goes straight up. Along the grid x axis (the screen
	# diagonal, 2:1): the unit vector of the aim as drawn, 3 px of it, reversed.
	var turret: Sprite2D = _rig(_runner.snapshot.index_of(Rig.LIGHT)).get_node("Turret")
	var mount: Vector2 = turret.position
	_shoot(Rig.LIGHT, Rig.SOUTH_ON_SCREEN, &"tank_cannon")
	_frame(Rig.SHOT_TICK, 0.75)  # 50 ms: the peak.
	assert_vector(turret.position - mount).is_equal_approx(Vector2(0.0, -3.0), TOL)
	_frame(34, 0.0)  # Home.
	_shoot(Rig.LIGHT, Vector2i(4000, 0), &"tank_cannon", 40)
	_frame(40, 0.75)
	var drawn: Vector2 = IsoProjection.ground_to_px(4000, 0)
	assert_vector(turret.position - mount).is_equal_approx(-drawn.normalized() * 3.0, TOL)


func test_a_heavy_gun_rocks_the_hull_and_carries_the_turret_with_it() -> void:
	# `heavy_cannon`: 4 px of recoil and 1 px of rock. At the peak the Hull stands 1 px back and the
	# Turret 5 px (the rock and its own recoil); the Shadow and the rig's node stay.
	var row: int = _runner.snapshot.index_of(Rig.HEAVY)
	var rig: Node2D = _rig(row)
	var hull: Sprite2D = rig.get_node("Hull")
	var turret: Sprite2D = rig.get_node("Turret")
	var shadow: Sprite2D = rig.get_node("Shadow")
	var mount: Vector2 = turret.position
	var rig_at: Vector2 = rig.position
	_shoot(Rig.HEAVY, Rig.EAST_ON_SCREEN, &"heavy_cannon")
	_frame(Rig.SHOT_TICK, 0.75)
	assert_vector(hull.position).is_equal_approx(Vector2(-1.0, 0.0), TOL)
	assert_vector(turret.position - mount).is_equal_approx(Vector2(-5.0, 0.0), TOL)
	assert_vector(shadow.position).is_equal(Vector2.ZERO)
	assert_vector(rig.position).is_equal(rig_at)
	_frame(34, 0.0)  # Over: both home.
	assert_vector(hull.position).is_equal(Vector2.ZERO)
	assert_vector(turret.position).is_equal_approx(mount, TOL)


func test_a_weapon_with_no_rock_never_writes_the_hull() -> void:
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var hull: Sprite2D = _rig(row).get_node("Hull")
	_shoot(Rig.LIGHT, Rig.EAST_ON_SCREEN, &"tank_cannon")
	for index: int in Rig.SAMPLES.size():
		_frame(int(Rig.SAMPLES[index].x), Rig.SAMPLES[index].y)
		assert_vector(hull.position).is_equal(Vector2.ZERO)
	assert_int(_layer.life_writes()).is_equal(7)  # The Turret's only.


func test_the_kick_never_moves_the_rig_its_picks_or_its_bar() -> void:
	# The rig's node is the sort key, the pick centre and the bar anchor: a kick at its peak leaves
	# them as they were, and the pick snapshot holds the same numbers.
	var row: int = _runner.snapshot.index_of(Rig.HEAVY)
	var rig: Node2D = _rig(row)
	var before: PickSnapshot = PickSnapshot.new()
	_layer.fill_pick_snapshot(before, 24.0)
	var screen_before: Vector2 = _layer.unit_screen_position(row)
	var bar_before: float = _layer.bar_lift_px(row)
	var at_before: Vector2 = rig.global_position
	_shoot(Rig.HEAVY, Rig.EAST_ON_SCREEN, &"heavy_cannon")
	_frame(Rig.SHOT_TICK, 0.75)
	assert_int(_layer.life_writes()).is_greater(0)  # The kick is on.
	var during: PickSnapshot = PickSnapshot.new()
	_layer.fill_pick_snapshot(during, 24.0)
	assert_vector(rig.global_position).is_equal(at_before)
	assert_vector(_layer.unit_screen_position(row)).is_equal(screen_before)
	assert_float(_layer.bar_lift_px(row)).is_equal(bar_before)
	assert_array(during.screen_pos).is_equal(before.screen_pos)
	assert_array(during.lift_px).is_equal(before.lift_px)
	assert_array(during.radius_px).is_equal(before.radius_px)


func test_a_squad_does_not_kick_even_when_its_weapon_has_a_recoil_row() -> void:
	var life: LifeSettings = LifeSettings.new()
	life.recoil_px[&"rifle"] = 3.0
	life.rock_px[&"rifle"] = 1.0
	_layer = _make_layer(life)
	var row: int = _runner.snapshot.index_of(Rig.SQUAD)
	var squad: Node2D = _rig(row)
	assert_bool(squad.has_node("Turret")).is_false()
	_shoot(Rig.SQUAD, Rig.EAST_ON_SCREEN, &"rifle")
	assert_int(_layer.kick_count()).is_equal(0)
	_frame(Rig.SHOT_TICK, 0.75)
	assert_int(_layer.life_writes()).is_equal(0)
	assert_vector((squad.get_node("Hull") as Sprite2D).position).is_equal(Vector2.ZERO)


func test_a_hidden_enemy_rig_kicks_nothing_and_a_seen_one_kicks() -> void:
	var row: int = _runner.snapshot.index_of(Rig.ENEMY_TANK)
	var far: Vector2i = Rig.centre(Rig.FAR_TILE)
	var turret: Sprite2D = _rig(row).get_node("Turret")
	var mount: Vector2 = turret.position
	assert_bool(_layer.is_shown(row)).is_false()  # The fixture: its tile is in the dark.
	Rig.deliver(
		_runner, Rig.shot(_runner, Rig.ENEMY_TANK, far, Rig.EAST_ON_SCREEN, &"heavy_cannon"), 30
	)
	assert_int(_layer.kick_count()).is_equal(0)
	_frame(30, 0.75)
	assert_int(_layer.life_writes()).is_equal(0)
	assert_vector(turret.position).is_equal_approx(mount, TOL)
	Buildings.see(_runner.snapshot, 1, [Rig.FAR_TILE])  # Now its tile is seen.
	assert_bool(_layer.is_shown(row)).is_true()
	Rig.deliver(
		_runner, Rig.shot(_runner, Rig.ENEMY_TANK, far, Rig.EAST_ON_SCREEN, &"heavy_cannon"), 40
	)
	assert_int(_layer.kick_count()).is_equal(1)
	_frame(40, 0.75)
	assert_vector(turret.position - mount).is_equal_approx(Vector2(-5.0, 0.0), TOL)
	assert_int(_layer.life_writes()).is_equal(2)  # The Hull and the Turret.


func test_the_fog_of_the_tick_decides_not_the_fog_at_the_frame() -> void:
	# The shot is judged by the tile of the shooter in the fog of its own tick: seen then, it plays
	# out although the rig is out of sight a frame later (the node hides, the sprites still move).
	var row: int = _runner.snapshot.index_of(Rig.ENEMY_TANK)
	var far: Vector2i = Rig.centre(Rig.FAR_TILE)
	Buildings.see(_runner.snapshot, 1, [Rig.FAR_TILE])
	Rig.deliver(
		_runner, Rig.shot(_runner, Rig.ENEMY_TANK, far, Rig.EAST_ON_SCREEN, &"heavy_cannon"), 30
	)
	Buildings.see(_runner.snapshot, 1, [])
	_frame(30, 0.75)
	assert_bool(_layer.is_shown(row)).is_false()
	assert_vector((_rig(row).get_node("Hull") as Sprite2D).position).is_equal_approx(
		Vector2(-1.0, 0.0), TOL
	)


func test_a_turret_that_turns_with_its_hull_mid_kick_keeps_the_kick_on_its_new_mount() -> void:
	# The hull turns (the unit drove south on the grid), which moves the mount: the kick is still on
	# the turret, at the new mount.
	var row: int = _runner.snapshot.index_of(Rig.LIGHT)
	var snap: MatchSnapshot = _runner.snapshot
	var turret: Sprite2D = _rig(row).get_node("Turret")
	_shoot(Rig.LIGHT, Rig.EAST_ON_SCREEN, &"tank_cannon")
	_frame(Rig.SHOT_TICK, 0.75)  # The peak: 3 px back.
	var speed: int = snap.type_speed[snap.type_index[row]]
	snap.prev_pos_y[row] = snap.pos_y[row] - speed  # A full step towards grid +y in the last tick.
	_layer._process(1.0)  # A long frame: the hull turns at once.
	var dir: int = Frames.dir(_layer, row, &"hull")
	assert_int(dir).is_not_equal(UnitLayer.D_EAST)
	var mount: Vector2 = _sheet(row).mount(dir) * WorldSort.ART_SCALE
	assert_vector(turret.position).is_equal_approx(mount + Vector2(-3.0, 0.0), TOL)
	# The kick's next steps are written on the new mount too, not on the mount of the first frame:
	# 100 ms is 1.5 px, and the mounts of the two frames are a whole 17 px apart.
	assert_vector(_sheet(row).mount(UnitLayer.D_EAST) * WorldSort.ART_SCALE - mount).is_not_equal(
		Vector2.ZERO
	)
	_frame(31, 0.5)
	assert_vector(turret.position).is_equal_approx(mount + Vector2(-1.5, 0.0), TOL)
	_frame(33, 0.0)  # And home: on the new mount.
	assert_vector(turret.position).is_equal_approx(mount, TOL)


func test_a_new_match_starts_every_rig_on_its_rest_with_no_kick() -> void:
	# The rigs go to the pool and come out for the next match: a kicked one is not left kicked.
	var row: int = _runner.snapshot.index_of(Rig.HEAVY)
	_shoot(Rig.HEAVY, Rig.EAST_ON_SCREEN, &"heavy_cannon")
	_frame(Rig.SHOT_TICK, 0.75)
	assert_int(_layer.life_writes()).is_greater(0)
	var made: int = _layer.rigs_made()
	_runner.start()  # Another match of the same scenario.
	_layer._process(0.0)
	assert_int(_layer.kick_count()).is_equal(0)
	assert_int(_layer.rigs_made()).is_equal(made)  # The pool served them.
	row = _runner.snapshot.index_of(Rig.HEAVY)
	var sheet: IsoSheetDef = _sheet(row)
	var turret: Sprite2D = _rig(row).get_node("Turret")
	assert_vector((_rig(row).get_node("Hull") as Sprite2D).position).is_equal(Vector2.ZERO)
	assert_vector(turret.position).is_equal_approx(
		sheet.mount(UnitLayer.D_EAST) * WorldSort.ART_SCALE, TOL
	)
	# A stale kick on the rig would show at its next hull turn, which puts the turret on the mount
	# plus what the rig believes it is off by: turn the hull and the turret is on the mount exactly.
	var snap: MatchSnapshot = _runner.snapshot
	snap.prev_pos_y[row] = snap.pos_y[row] - snap.type_speed[snap.type_index[row]]
	_layer._process(1.0)
	var dir: int = Frames.dir(_layer, row, &"hull")
	assert_int(dir).is_not_equal(UnitLayer.D_EAST)
	assert_vector(turret.position).is_equal(sheet.mount(dir) * WorldSort.ART_SCALE)


func test_a_unit_that_dies_mid_kick_takes_its_kick_with_it_and_gives_it_to_no_other_rig() -> void:
	# Four heavy tanks of the local player, the last of them the last row. The first fires and dies
	# in the next tick: its id is gone, and a row of -1 must not reach the last rig, which GDScript
	# would index from the end of the array.
	var spawns: Array[SpawnDef] = [Buildings.spawn(2, "renew_tank", 28, 28)]
	for column: int in 4:
		spawns.append(Buildings.spawn(1, "heavy_tank", 4 + 4 * column, 4))
	_runner = auto_free(Buildings.runner(Buildings.scenario(spawns)))
	_layer = _make_layer(null)
	var snap: MatchSnapshot = _runner.snapshot
	var first: int = snap.unit_id[1]
	var last_row: int = snap.unit_count() - 1
	var last: Node2D = _rig(last_row)
	var last_mount: Vector2 = (last.get_node("Turret") as Sprite2D).position
	assert_bool(_layer.is_shown(last_row)).is_true()
	_shoot(first, Rig.EAST_ON_SCREEN, &"heavy_cannon", 0)
	_frame(0, 0.75)  # The peak: the first tank's Hull 1 px and Turret 5 px back.
	assert_int(_layer.kick_count()).is_equal(1)
	assert_vector((_rig(1).get_node("Hull") as Sprite2D).position).is_equal_approx(
		Vector2(-1.0, 0.0), TOL
	)
	_runner.world.hp[1] = 0  # It dies in the next tick, and the rows after it move up.
	_runner.run_ticks(1)
	_layer._process(0.0)
	assert_int(_runner.snapshot.index_of(first)).is_equal(-1)
	assert_int(_layer.kick_count()).is_equal(0)
	last = _rig(_runner.snapshot.unit_count() - 1)
	assert_vector((last.get_node("Hull") as Sprite2D).position).is_equal(Vector2.ZERO)
	assert_vector((last.get_node("Turret") as Sprite2D).position).is_equal(last_mount)
	assert_int(_layer.life_writes()).is_equal(2)  # The dead tank's two, and none after.


## A layer on the fixture runner with the settings `life` (null: the data file's).
func _make_layer(life: LifeSettings) -> UnitLayer:
	if is_instance_valid(_layer):
		_layer.free()
	var layer: UnitLayer = auto_free(UnitLayer.new())
	layer.runner = _runner
	layer.life = Rig.calmed(life)
	var camera: RtsCamera = auto_free(RtsCamera.new())
	add_child(camera)
	layer.camera = camera
	add_child(layer)
	layer.set_process(false)
	layer._process(0.0)
	return layer


## Delivers a SHOT of unit `id` towards `aim` with the weapon `weapon_id` at tick `tick`.
func _shoot(id: int, aim: Vector2i, weapon_id: StringName, tick: int = Rig.SHOT_TICK) -> void:
	var from: Vector2i = Rig.position_of(_runner, id)
	Rig.deliver(_runner, Rig.shot(_runner, id, from, aim, weapon_id), tick)


## One frame at match time (tick + alpha).
func _frame(tick: int, alpha: float) -> void:
	Rig.at(_runner, tick, alpha)
	_layer._process(0.0)


func _rig(row: int) -> Node2D:
	return _layer.rig(row)


func _sheet(row: int) -> IsoSheetDef:
	var snap: MatchSnapshot = _runner.snapshot
	return _layer.world_sort.sheet(snap.type_ids[snap.type_index[row]])
