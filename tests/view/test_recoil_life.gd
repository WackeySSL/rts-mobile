extends GdUnitTestSuite
## The recoil on match time (plan P136, ADR 0027 sections 2 and 8): it stops with the match (a
## pause), never runs backwards when WORKER mode restarts alpha at 0 after one, is the same at the
## same tick on every run (two runs of the real sim give the same turrets), reads every number from
## `LifeSettings`, and `reduced` keeps it (it tells the player something). Also the table's edges: a
## shot of a weapon with no row kicks nothing, a full table kicks nothing and leaves nothing stale,
## a second shot of the same rig restarts its kick. The look is in test_recoil_units.gd; fixtures
## in recoil_rig.gd (tick + alpha set by hand, match time = (tick + alpha) x 1000 / 15 ms).

const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const EffectsRig: GDScript = preload("res://tests/view/support/effects_rig.gd")
const TOL: Vector2 = Vector2(0.001, 0.001)

var _runner: MatchRunner
var _layer: UnitLayer
var _turret: Sprite2D
var _mount: Vector2
var _battle_writes: int = 0  ## The life sprite writes of the last `_play_battle`.


func before_test() -> void:
	_runner = auto_free(Rig.runner())
	_start(null)


func after_test() -> void:
	CommandQueue.clear()


func test_a_pause_freezes_the_kick_mid_step_and_the_resume_goes_on_from_there() -> void:
	_shoot(Rig.LIGHT, &"tank_cannon")
	_frame(31, 0.125)  # 75 ms: 2 px back.
	var frozen: Vector2 = _turret.position
	var writes: int = _layer.life_writes()
	var ms: float = LifeClock.ms(_runner.snapshot, _runner.alpha())
	_runner.paused = true
	for _frame_index: int in 30:  # Frames of real time pass: the match time does not.
		_runner._process(0.5)
		_layer._process(0.05)
	assert_float(LifeClock.ms(_runner.snapshot, _runner.alpha())).is_equal(ms)
	assert_vector(_turret.position).is_equal(frozen)
	assert_int(_layer.life_writes()).is_equal(writes)
	_runner.paused = false
	_frame(31, 0.5)  # 100 ms: 1.5 px, from the pose it froze in.
	assert_vector(_turret.position).is_equal_approx(_mount + Vector2(-1.5, 0.0), TOL)


func test_when_alpha_restarts_at_zero_after_a_pause_the_kick_holds_and_never_runs_back() -> void:
	# WORKER mode restarts alpha at 0 in the first frame after a pause, so the match time steps back
	# by up to a tick: 100 ms, then 66.7 ms of the same kick. The turret must not return to 2.5 px
	# (where it was at 66.7 ms); it holds at 1.5 and goes on, and no age is below the last one.
	_shoot(Rig.LIGHT, &"tank_cannon")
	_frame(31, 0.5)  # 100 ms: 1.5 px.
	assert_vector(_turret.position).is_equal_approx(_mount + Vector2(-1.5, 0.0), TOL)
	var writes: int = _layer.life_writes()
	_frame(31, 0.0)  # The resume: 66.7 ms of match time.
	assert_vector(_turret.position).is_equal_approx(_mount + Vector2(-1.5, 0.0), TOL)
	assert_int(_layer.life_writes()).is_equal(writes)
	var peak: float = 1.5
	for sample: Vector2 in [Vector2(31, 0.25), Vector2(31, 0.875), Vector2(32, 0.25)]:
		_frame(int(sample.x), sample.y)  # 83 ms (still held), 125 ms, 150 ms.
		var back: float = -(_turret.position - _mount).x
		assert_float(back).is_less_equal(peak)
		peak = back
	assert_float(peak).is_equal_approx(0.5, 0.001)


func test_the_same_shot_at_the_same_tick_and_alpha_gives_the_same_offsets_on_two_runs() -> void:
	var first: Array[Vector2] = _offsets_of_a_heavy_shot()
	_runner = auto_free(Rig.runner())
	_start(null)
	var second: Array[Vector2] = _offsets_of_a_heavy_shot()
	assert_int(first.size()).is_equal(Rig.SAMPLES.size())
	assert_array(second).is_equal(first)
	assert_float(first[1].x).is_equal_approx(-5.0, 0.001)  # And it kicked: 5 px at the peak.


func test_the_real_sim_gives_the_same_turrets_at_the_same_ticks_in_a_replay() -> void:
	# Two runs of one scenario and seed (a replay plays the same commands): after every tick, at
	# alpha 0.5, the Turret and the Hull of every rig stand in the same places. The fight must kick.
	var first: Array[Vector2] = _play_battle()
	var first_writes: int = _battle_writes
	var second: Array[Vector2] = _play_battle()
	assert_int(first.size()).is_greater(1000)
	assert_array(second).is_equal(first)
	assert_int(first_writes).is_greater(0)  # The fight kicked turrets.
	assert_int(_battle_writes).is_equal(first_writes)


func test_reduced_keeps_the_recoil() -> void:
	# Reduced effects drop the ambient and keep what tells the player something (ADR 0027 section
	# 8, answer 3): the same offsets, the same writes, also when it is switched on mid-kick.
	var life: LifeSettings = LifeSettings.new()
	life.reduced = true
	_start(life)
	_shoot(Rig.LIGHT, &"tank_cannon")
	for index: int in Rig.SAMPLES.size():
		_frame(int(Rig.SAMPLES[index].x), Rig.SAMPLES[index].y)
		var back: float = Rig.TANK_CANNON_BACK[index]
		assert_vector(_turret.position).is_equal_approx(_mount + Vector2(-back, 0.0), TOL)
	assert_int(_layer.life_writes()).is_equal(7)
	var other: LifeSettings = LifeSettings.new()
	_start(other)
	_shoot(Rig.LIGHT, &"tank_cannon", 40)
	_frame(40, 0.375)
	other.reduced = true  # Switched on mid-kick.
	_frame(40, 0.75)
	assert_vector(_turret.position).is_equal_approx(_mount + Vector2(-3.0, 0.0), TOL)
	assert_int(_layer.life_writes()).is_equal(2)


func test_every_number_comes_from_the_settings() -> void:
	# 6 px, peak at 100 ms, home at 400 ms: at 100 ms 6 px, at 250 ms half way down the ease
	# (0.25 x 6 = 1.5), at 400 ms home.
	var life: LifeSettings = LifeSettings.new()
	life.recoil_px[&"tank_cannon"] = 6.0
	life.recoil_out_ms = 100
	life.recoil_back_ms = 400
	_start(life)
	_shoot(Rig.LIGHT, &"tank_cannon")
	_frame(31, 0.5)  # 100 ms.
	assert_vector(_turret.position).is_equal_approx(_mount + Vector2(-6.0, 0.0), TOL)
	_frame(33, 0.0)  # 200 ms: (1 - 100 / 300) squared = 4 / 9 of 6 px = 2.67, in steps: 2.5.
	assert_vector(_turret.position).is_equal_approx(_mount + Vector2(-2.5, 0.0), TOL)
	_frame(34, 0.0)  # 266.7 ms: (1 - 166.7 / 300) squared = 0.197 of 6 px = 1.19, in steps: 1.0.
	assert_vector(_turret.position).is_equal_approx(_mount + Vector2(-1.0, 0.0), TOL)
	_frame(36, 0.0)  # 400 ms: home.
	assert_vector(_turret.position).is_equal_approx(_mount, TOL)
	assert_int(_layer.kick_count()).is_equal(0)


func test_a_weapon_with_no_recoil_row_kicks_nothing() -> void:
	var life: LifeSettings = LifeSettings.new()
	life.recoil_px.erase(&"tank_cannon")
	_start(life)
	_shoot(Rig.LIGHT, &"tank_cannon")
	assert_int(_layer.kick_count()).is_equal(0)
	_frame(30, 0.75)
	assert_int(_layer.life_writes()).is_equal(0)
	life.recoil_px[&"tank_cannon"] = 0.0  # And a row of 0 kicks nothing either.
	_shoot(Rig.LIGHT, &"tank_cannon", 31)
	assert_int(_layer.kick_count()).is_equal(0)


func test_a_full_table_kicks_nothing_more_and_a_rig_is_never_left_off_its_mount() -> void:
	var life: LifeSettings = LifeSettings.new()
	life.kick_slots = 1
	_start(life)
	var other: Sprite2D = _layer.rig(_runner.snapshot.index_of(Rig.HEAVY)).get_node("Turret")
	var other_mount: Vector2 = other.position
	_shoot(Rig.LIGHT, &"tank_cannon")
	_shoot(Rig.HEAVY, &"heavy_cannon")  # Finds the table full.
	assert_int(_layer.kick_count()).is_equal(1)
	for index: int in Rig.SAMPLES.size():
		_frame(int(Rig.SAMPLES[index].x), Rig.SAMPLES[index].y)
		assert_vector(other.position).is_equal_approx(other_mount, TOL)
	assert_int(_layer.kick_count()).is_equal(0)
	_shoot(Rig.HEAVY, &"heavy_cannon", 40)  # The slot is free again.
	assert_int(_layer.kick_count()).is_equal(1)


func test_a_second_shot_of_the_same_rig_restarts_its_kick() -> void:
	_shoot(Rig.LIGHT, &"tank_cannon")
	_frame(30, 0.75)  # The peak of the first.
	_shoot(Rig.LIGHT, &"tank_cannon", 31)  # A tick on: the first is 16.7 ms past its peak.
	assert_int(_layer.kick_count()).is_equal(1)  # The same slot.
	_frame(31, 0.375)  # 25 ms into the second: 1.5 px.
	assert_vector(_turret.position).is_equal_approx(_mount + Vector2(-1.5, 0.0), TOL)
	_frame(32, 0.0)  # 66.7 ms into it: 2.5 px on the way back (0.8889 squared x 3 = 2.37).
	assert_vector(_turret.position).is_equal_approx(_mount + Vector2(-2.5, 0.0), TOL)


func test_a_frame_that_plays_several_ticks_draws_each_kick_at_its_own_age() -> void:
	# Two ticks come in one frame: the earlier shot is a tick (66.7 ms) older at the frame. The
	# light tank shot at tick 30, the heavy at 31; the frame is at tick 31 + 0.5 = 100 and 33.3 ms.
	var heavy: Sprite2D = _layer.rig(_runner.snapshot.index_of(Rig.HEAVY)).get_node("Turret")
	var heavy_mount: Vector2 = heavy.position
	_shoot(Rig.LIGHT, &"tank_cannon", 30)
	_shoot(Rig.HEAVY, &"heavy_cannon", 31)
	_frame(31, 0.5)
	assert_vector(_turret.position).is_equal_approx(_mount + Vector2(-1.5, 0.0), TOL)
	# 33.3 ms of 50: two thirds of the 4 px of recoil and the 1 px of rock = 3.33 px, in steps 3.5.
	assert_vector(heavy.position - heavy_mount).is_equal_approx(Vector2(-3.5, 0.0), TOL)


## A layer on the fixture runner with the settings `life` (null: the data file's), and the light
## tank's Turret and mount.
func _start(life: LifeSettings) -> void:
	if is_instance_valid(_layer):
		_layer.free()
	_layer = auto_free(UnitLayer.new())
	_layer.runner = _runner
	_layer.life = life
	var camera: RtsCamera = auto_free(RtsCamera.new())
	add_child(camera)
	_layer.camera = camera
	add_child(_layer)
	_layer.set_process(false)
	_layer._process(0.0)
	_turret = _layer.rig(_runner.snapshot.index_of(Rig.LIGHT)).get_node("Turret")
	_mount = _turret.position


## Delivers a SHOT of unit `id`, straight east on the screen, at tick `tick`.
func _shoot(id: int, weapon_id: StringName, tick: int = Rig.SHOT_TICK) -> void:
	var from: Vector2i = Rig.position_of(_runner, id)
	var events: PackedInt32Array = Rig.shot(_runner, id, from, Rig.EAST_ON_SCREEN, weapon_id)
	Rig.deliver(_runner, events, tick)


func _frame(tick: int, alpha: float) -> void:
	Rig.at(_runner, tick, alpha)
	_layer._process(0.0)


## The Turret offsets of the heavy tank after a shot, at the fixture's samples.
func _offsets_of_a_heavy_shot() -> Array[Vector2]:
	var turret: Sprite2D = _layer.rig(_runner.snapshot.index_of(Rig.HEAVY)).get_node("Turret")
	var mount: Vector2 = turret.position
	_shoot(Rig.HEAVY, &"heavy_cannon")
	var offsets: Array[Vector2] = []
	for sample: Vector2 in Rig.SAMPLES:
		_frame(int(sample.x), sample.y)
		offsets.append(turret.position - mount)
	return offsets


## Plays the effects fixture's battle for 200 ticks and notes, after each tick at alpha 0.5, the
## local position of the Turret and the Hull of every rig that has them.
func _play_battle() -> Array[Vector2]:
	var battle: MatchRunner = auto_free(MatchRunner.new())
	battle.scenario = EffectsRig.battle()
	battle.start()
	var layer: UnitLayer = auto_free(UnitLayer.new())
	layer.runner = battle
	layer.reveal_enemies = true
	var camera: RtsCamera = auto_free(RtsCamera.new())
	add_child(camera)
	layer.camera = camera
	add_child(layer)
	layer.set_process(false)
	var places: Array[Vector2] = []
	for _tick: int in 200:
		battle.run_ticks(1)
		battle._micro_ticks = MatchRunner.MICRO_TICKS_PER_TICK / 2
		layer._process(0.0)
		for row: int in battle.snapshot.unit_count():
			var rig: Node2D = layer.rig(row)
			if rig != null and rig.has_node("Turret"):
				places.append((rig.get_node("Turret") as Sprite2D).position)
				places.append((rig.get_node("Hull") as Sprite2D).position)
	_battle_writes = layer.life_writes()
	return places
