extends GdUnitTestSuite
## MatchRunner's snapshot publishing (plan P38j, ADR 0012 sections 1 and 3): every tick runs a
## TickJob that fills a new MatchSnapshot, and the runner publishes it before `ticked`; start()
## publishes the tick-0 snapshot. The P38 and Phase 1 runner cases are in test_match_runner.gd,
## which is at gdlint's limit of public methods. Two scenarios: three tanks of player 1 built in
## code (as in test_match_runner.gd), and the perf arena with seed 42, where both players
## attack-move from tick 0, so units move on every early tick.

const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
## The snapshot arrays a capture fills besides COPIED.
const FILLED: Array[StringName] = [
	&"target_row",
	&"prev_pos_x",
	&"prev_pos_y",
	&"prev_proj_id",
	&"prev_proj_x",
	&"prev_proj_y",
	&"events",
	&"stats",
	&"type_ids",
	&"weapon_ids",
	&"terrain_ids",
]


func after_test() -> void:
	CommandQueue.clear()


## start() publishes the tick-0 snapshot before it returns, without `ticked`: tick 0, the runner's
## match_serial, last_hash 0 (the new loop's), prev = pos, and the runner's prev forwards return
## its arrays. Before the first start() there is none and the forwards are empty. Every start()
## publishes a new object.
func test_start_publishes_the_tick_0_snapshot_without_ticked() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	assert_object(runner.snapshot).is_null()
	assert_array([runner.prev_pos_x.size(), runner.prev_pos_y.size()]).is_equal([0, 0])
	runner.scenario = _scenario()
	var seen: Array[int] = []
	runner.ticked.connect(func(tick: int) -> void: seen.append(tick))
	runner.start()
	var first: MatchSnapshot = runner.snapshot
	assert_object(first).is_not_null()
	assert_array([first.tick, first.match_serial, first.last_hash, first.unit_count()]).is_equal(
		[0, 1, 0, 3]
	)
	assert_array(first.pos_x).is_equal(PackedInt32Array([2500, 4000, 5500]))
	assert_array([first.prev_pos_x, first.prev_pos_y]).is_equal([first.pos_x, first.pos_y])
	assert_bool(is_same(runner.prev_pos_x, first.prev_pos_x)).is_true()
	assert_bool(is_same(runner.prev_pos_y, first.prev_pos_y)).is_true()
	runner.run_ticks(2)
	runner.start()
	assert_bool(is_same(runner.snapshot, first)).is_false()
	assert_array([runner.snapshot.tick, runner.snapshot.match_serial]).is_equal([0, 2])
	assert_array(seen).is_equal([1, 2])


## A restart after 10 ticks of the arena, in which no unit died, so both matches have the same
## rows_version. The old match also held a projectile in slot 0. The new tick-0 snapshot has prev =
## pos for every row and prev_proj_* = proj_*, so no rig slides from the old match's positions, and
## the next tick interpolates from the new tick-0 positions.
func test_a_restart_with_the_same_rows_version_slides_nothing() -> void:
	var runner: MatchRunner = _arena_runner()
	runner.run_ticks(9)
	runner.world.proj_id[0] = 7
	runner.world.proj_x[0] = 500
	runner.world.proj_y[0] = 1500
	runner.run_ticks(1)
	var old: MatchSnapshot = runner.snapshot
	assert_int(old.proj_id[0]).is_equal(7)
	runner.start()
	var snap: MatchSnapshot = runner.snapshot
	assert_int(snap.rows_version).is_equal(old.rows_version)
	assert_bool(snap.pos_x == old.pos_x).is_false()
	assert_array([snap.prev_pos_x, snap.prev_pos_y]).is_equal([snap.pos_x, snap.pos_y])
	assert_array([snap.prev_proj_id, snap.prev_proj_x, snap.prev_proj_y]).is_equal(
		[snap.proj_id, snap.proj_x, snap.proj_y]
	)
	runner.run_ticks(1)
	assert_array([runner.prev_pos_x, runner.prev_pos_y]).is_equal([snap.pos_x, snap.pos_y])


## A restart frees the old match at once, before the first tick of the new one: nothing the runner
## keeps, its reused TickJob included, still holds the old World, MatchLoop, Replay or snapshot, so
## a restarted runner that stays paused does not keep the old match in memory.
func test_a_restart_frees_the_old_match_at_once() -> void:
	var runner: MatchRunner = _arena_runner()
	runner.run_ticks(5)
	var old: Array[WeakRef] = [weakref(runner.world), weakref(runner.loop), weakref(runner.replay)]
	old.append(weakref(runner.snapshot))
	runner.start()
	for index: int in old.size():
		assert_object(old[index].get_ref()).override_failure_message(str(index)).is_null()


## One snapshot per publish: the snapshot published at tick 20 keeps every array and its fog after
## the next tick, which publishes a new object. The arena's fog does not change in a tick before
## the fog rules (P46b), so the test writes two fog cells of the World first. The old snapshot is
## freed at publish, so the object count after 20 ticks equals the count right after start().
func test_each_tick_publishes_a_new_snapshot_and_leaves_the_old_one_alone() -> void:
	var runner: MatchRunner = _arena_runner()
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	runner.run_ticks(20)
	assert_int(int(Performance.get_monitor(Performance.OBJECT_COUNT))).is_equal(objects)
	var published: MatchSnapshot = runner.snapshot
	var kept: Array = _values(published)
	var fog: FogGrid = runner.world.fog
	fog.visible[0] += 1
	fog.explored[0] = 1 - fog.explored[0]
	assert_bool(fog.visible[0] == published.fog.visible[0]).is_false()
	runner.run_ticks(1)
	assert_bool(is_same(runner.snapshot, published)).is_false()
	assert_bool(runner.snapshot.pos_x == published.pos_x).is_false()
	assert_array(_values(published)).is_equal(kept)


## Unit 2 dies in tick 3 (hp 0 written in the test, removed in the tick): the published prev
## positions follow the ids, so units 1 and 3 keep their positions from before the tick. A unit
## added to the running world starts at its position (moved here from P38).
func test_prev_positions_follow_the_ids_when_a_unit_dies_or_is_added() -> void:
	var runner: MatchRunner = _tank_runner()
	CommandQueue.submit(Command.attack_move(1, PackedInt32Array([1, 2, 3]), 12500, 9500))
	runner.run_ticks(2)
	var before: MatchSnapshot = runner.snapshot
	runner.world.hp[1] = 0
	runner.run_ticks(1)
	var snap: MatchSnapshot = runner.snapshot
	assert_array(snap.unit_id).is_equal(PackedInt32Array([1, 3]))
	assert_array(snap.prev_pos_x).is_equal(PackedInt32Array([before.pos_x[0], before.pos_x[2]]))
	assert_array(snap.prev_pos_y).is_equal(PackedInt32Array([before.pos_y[0], before.pos_y[2]]))
	assert_bool(snap.prev_pos_y == snap.pos_y).is_false()
	assert_bool(is_same(runner.prev_pos_x, snap.prev_pos_x)).is_true()
	assert_int(runner.world.add_unit(1, 0, 7000, 8000)).is_equal(4)
	runner.run_ticks(1)
	assert_array(runner.snapshot.unit_id).is_equal(PackedInt32Array([1, 3, 4]))
	assert_array([runner.prev_pos_x[1], runner.prev_pos_y[1]]).is_equal(
		[snap.pos_x[1], snap.pos_y[1]]
	)
	assert_array([runner.prev_pos_x[2], runner.prev_pos_y[2]]).is_equal([7000, 8000])


## `ticked(n)` arrives after the publish: in the handler the runner's snapshot is tick n, with that
## tick's events, the World's: none in ticks 1 and 2, the DIED record of unit 2 in tick 3.
func test_ticked_arrives_with_the_snapshot_of_its_tick_and_its_events() -> void:
	var runner: MatchRunner = _tank_runner()
	var ticks: Array[int] = []
	var events: Array[PackedInt32Array] = []
	var world_events: Array[PackedInt32Array] = []
	runner.ticked.connect(
		func(tick: int) -> void:
			ticks.append_array([tick, runner.snapshot.tick])
			events.append(runner.snapshot.events)
			world_events.append(runner.world.events.duplicate())
	)
	runner.run_ticks(2)
	runner.world.hp[1] = 0
	runner._process(1.0 / 15.0)
	assert_array(ticks).is_equal([1, 1, 2, 2, 3, 3])
	assert_array(events).is_equal(world_events)
	var died: PackedInt32Array = events[2]
	assert_array([events[0].size(), events[1].size(), died.size()]).is_equal(
		[0, 0, World.EVENT_STRIDE]
	)
	assert_array([died[0], died[1]]).is_equal([World.Event.DIED, 2])


## At every publish the runner's last_hash, last_tick_usec and last_runner_tick_usec are the
## snapshot's last_hash, step_usec and job_usec. The job's clock readings lie in the run: the post,
## then the job, then its end. With a TimingProbe on the runner the snapshot's phase_usec equals
## the probe's array at publish and is another object; without a probe it is empty.
func test_the_published_fields_and_the_phase_times_come_from_the_snapshot() -> void:
	var runner: MatchRunner = _arena_runner()
	var timing: TimingProbe = TimingProbe.new()
	runner.probe = timing
	var rows: Array = []
	runner.ticked.connect(func(_tick: int) -> void: rows.append(_published(runner, timing)))
	var started: int = Time.get_ticks_usec()
	runner.run_ticks(16)
	runner.probe = null
	runner.run_ticks(1)
	var ended: int = Time.get_ticks_usec()
	assert_int(rows.size()).is_equal(17)
	for tick: int in rows.size():
		var row: Array = rows[tick]
		var label: String = str(tick + 1)
		assert_array(row[0]).override_failure_message(label).is_equal(row[1])
		var snap: MatchSnapshot = row[2]
		assert_int(snap.step_usec).override_failure_message(label).is_greater(0)
		assert_int(snap.job_usec).override_failure_message(label).is_greater_equal(snap.step_usec)
		var clock: Array[int] = [started, snap.post_usec, snap.end_usec - snap.job_usec]
		clock.append_array([snap.end_usec, ended])
		var sorted: Array[int] = clock.duplicate()
		sorted.sort()
		assert_array(clock).override_failure_message(label).is_equal(sorted)
		if tick < 16:
			assert_array(snap.phase_usec).override_failure_message(label).is_equal(row[3])
			assert_bool(row[4]).override_failure_message(label).is_false()
	var at_15: MatchSnapshot = rows[14][2]
	assert_array([at_15.tick, at_15.last_hash == 0]).is_equal([15, false])
	assert_bool(runner.snapshot.phase_usec.is_empty()).is_true()


## For 30 ticks of the arena every published snapshot carries the runner's match_serial and the
## loop's last_hash: 0 before tick 15, then the state hash at 15 and at 30, two different non-zero
## hashes. After a restart the next snapshot carries the new match_serial.
func test_every_snapshot_carries_the_match_serial_and_the_loop_hash() -> void:
	var runner: MatchRunner = _arena_runner()
	var rows: Array = []
	runner.ticked.connect(
		func(_tick: int) -> void:
			var snap: MatchSnapshot = runner.snapshot
			rows.append([snap.match_serial, snap.last_hash, runner.loop.last_hash])
	)
	runner.run_ticks(30)
	var hashes: Array[int] = []
	for row: Array in rows:
		assert_array([row[0], row[1]]).is_equal([runner.match_serial, row[2]])
		hashes.append(row[1])
	assert_array([hashes[13], hashes[28]]).is_equal([0, hashes[14]])
	assert_bool(hashes[14] != 0 and hashes[29] != 0 and hashes[14] != hashes[29]).is_true()
	assert_array(runner.replay.checkpoint_hashes).is_equal([hashes[14], hashes[29]])
	runner.start()
	runner.run_ticks(1)
	assert_array([runner.match_serial, runner.snapshot.match_serial]).is_equal([2, 2])


## Two consecutive ticks of the arena, units moving: the second snapshot's prev positions are the
## first one's positions by value, and some unit moved between them. A match_serial set after the
## capture would send every tick down the "another match" path, prev = current.
func test_the_second_of_two_ticks_interpolates_from_the_first() -> void:
	var runner: MatchRunner = _arena_runner()
	runner.run_ticks(3)
	var first: MatchSnapshot = runner.snapshot
	runner.run_ticks(1)
	var second: MatchSnapshot = runner.snapshot
	assert_array(second.prev_pos_x).is_equal(first.pos_x)
	assert_array(second.prev_pos_y).is_equal(first.pos_y)
	var moved: int = 0
	for row: int in second.unit_count():
		if second.prev_pos_x[row] != second.pos_x[row]:
			moved += 1
	assert_int(moved).is_greater(0)


func _arena_runner() -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(ARENA_PATH) as ScenarioDef
	runner.match_seed = 42
	runner.start()
	return runner


func _tank_runner() -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = _scenario()
	runner.start()
	return runner


## The published fields, the snapshot's matching fields, the snapshot, a copy of the probe's
## phases, and whether the snapshot shares the probe's array.
func _published(runner: MatchRunner, timing: TimingProbe) -> Array:
	var snap: MatchSnapshot = runner.snapshot
	return [
		[runner.last_hash, runner.last_tick_usec, runner.last_runner_tick_usec],
		[snap.last_hash, snap.step_usec, snap.job_usec],
		snap,
		timing.phase_usec.duplicate(),
		is_same(snap.phase_usec, timing.phase_usec),
	]


## Copies of every array of `snap` a capture fills, and of its fog's fields.
func _values(snap: MatchSnapshot) -> Array:
	var values: Array = []
	for name: StringName in MatchSnapshot.COPIED + FILLED:
		values.append(snap.get(name).duplicate())
	for name: StringName in FogGrid.HASHED + FogGrid.UNHASHED:
		var value: Variant = snap.fog.get(name)
		values.append(value if typeof(value) == TYPE_INT else value.duplicate())
	return values


## Three tanks of player 1 at (2500, 2500), (4000, 2500) and (5500, 2500) on a 20x20 map.
func _scenario() -> ScenarioDef:
	var tank: UnitDef = UnitDef.new()
	tank.speed = 120
	tank.radius = 400
	tank.formation_spacing = 1200
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = 1
	spawn.unit = tank
	spawn.count = 3
	spawn.origin_tile = Vector2i(2, 2)
	spawn.columns = 3
	spawn.spacing = 1500
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(20, 20)
	scenario.spawns.append(spawn)
	return scenario
