extends GdUnitTestSuite
## The Kestrel Flats scenarios are deterministic (plan row P79, CLAUDE.md rules 2 and 3): each
## loads and runs bit-identically twice, and under both implementations (the GDScript twins and
## the native kernels) it reaches the same state at every checkpoint and at the end. The run is the
## scripted match of kestrel_run.gd: a fight in the middle, two buildings placed per side and a
## tanker at work, so that the phases have something to compute.

const Rig: GDScript = preload("res://tests/sim/support/kestrel_rig.gd")
const Run: GDScript = preload("res://tests/sim/support/kestrel_run.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const HashReport: GDScript = preload("res://tests/sim/support/hash_report.gd")


func _play(path: String, impl: int) -> RefCounted:
	var run: RefCounted = Run.new().play(path, impl)
	assert_array(run.problems).override_failure_message(path).is_empty()
	return run


## "" when the two runs agree: the checkpoints (ticks and hashes), the commands that were recorded,
## the full state of both Worlds, and the state hash.
func _difference(a: RefCounted, b: RefCounted) -> String:
	var first: World = a.world
	var second: World = b.world
	if a.loop.replay.checkpoint_ticks != b.loop.replay.checkpoint_ticks:
		return "checkpoint ticks"
	if a.loop.replay.checkpoint_hashes != b.loop.replay.checkpoint_hashes:
		return "checkpoint hashes: " + HashReport.mismatch(first, second)
	if a.loop.replay.commands != b.loop.replay.commands:
		return "recorded commands"
	var member: String = StateDiff.first(first, second)
	if member != "":
		return "state member " + member
	return "" if first.state_hash() == second.state_hash() else "state hash"


@warning_ignore("integer_division")
func test_the_scripted_run_fights_places_two_buildings_a_side_and_harvests() -> void:
	for path: String in Rig.PATHS:
		var run: RefCounted = _play(path, SimImpls.Impl.GDSCRIPT)
		var world: World = run.world
		assert_int(world.tick).is_equal(Run.TICKS)
		assert_int(world.dropped_commands).override_failure_message(path).is_equal(0)
		# The squads met in the middle: somebody died, and nobody lost a building or the match.
		assert_int(world.stat_lost_units[1] + world.stat_lost_units[2]).is_greater(0)
		assert_array([world.stat_lost_buildings[1], world.stat_lost_buildings[2]]).is_equal([0, 0])
		assert_int(world.match_end_tick).is_equal(0)
		for player: int in [1, 2]:
			var label: String = "%s player %d" % [path, player]
			(
				assert_int(Rig.building_rows(world, player).size())
				. override_failure_message(label)
				. is_equal(3)
			)
			assert_int(world.stat_built[player]).override_failure_message(label).is_equal(2)
			assert_int(world.stat_harvested[player]).override_failure_message(label).is_greater(0)
		# Every checkpoint is a new state: the run never stood still.
		var seen: Dictionary[int, bool] = {}
		for hash_value: int in run.loop.replay.checkpoint_hashes:
			seen[hash_value] = true
		assert_int(seen.size()).is_equal(Run.TICKS / Replay.CHECKPOINT_PERIOD)


func test_each_scenario_loads_and_runs_bit_identically_twice() -> void:
	for path: String in Rig.PATHS:
		var first: RefCounted = _play(path, SimImpls.Impl.GDSCRIPT)
		var second: RefCounted = _play(path, SimImpls.Impl.GDSCRIPT)
		assert_str(_difference(first, second)).override_failure_message(path).is_empty()


## The scenarios differ in more than a label: the script, which is the same for both, ends in
## another state, so the cases above compare two runs that are not vacuously equal.
func test_the_two_scenarios_are_two_different_matches() -> void:
	var first: RefCounted = _play(Rig.SKIRMISH_PATH, SimImpls.Impl.GDSCRIPT)
	var second: RefCounted = _play(Rig.MIRRORED_PATH, SimImpls.Impl.GDSCRIPT)
	assert_int(second.world.state_hash()).is_not_equal(first.world.state_hash())
	assert_int(second.world.defs_hash()).is_not_equal(first.world.defs_hash())


func test_the_native_kernels_play_each_scenario_to_the_gdscript_twins_state() -> void:
	for path: String in Rig.PATHS:
		var twin: RefCounted = _play(path, SimImpls.Impl.GDSCRIPT)
		var native: RefCounted = _play(path, SimImpls.Impl.NATIVE)
		assert_str(_difference(twin, native)).override_failure_message(path).is_empty()
		# Not the same World twice: the kernels were attached to the second one.
		assert_object(native.world.kernels).is_not_null()
		assert_object(twin.world.kernels).is_null()
