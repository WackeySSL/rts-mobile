extends GdUnitTestSuite
## The Phase 3 skeleton of Sim.step (plan P70b, ADR 0017 sections 4 and 5): every new Command type
## is dropped and counted until its row (the modules refuse it), the commands need an undefeated
## player, the five module stubs change no state, and a tick runs them after FOG in the order of the
## pipeline. The perf arena is the world: 2 players, 150 units, no building, so it has no queue and
## no producer: since P73 `Production` is no stub, but QUEUE and CANCEL are still dropped here and
## its `run` still changes nothing (tests/sim/test_production_*.gd have the rules). Since P75b
## `Harvest` has its rules too (tests/sim/test_harvest_*.gd), but the arena holds no harvester and
## no ore, so a HARVEST is still dropped here and `release` and `run` still change nothing; two
## cases use a world with ore (tests/sim/support/harvest_worlds.gd) to pin what `Sim` does with the
## Harvest module: the undefeated-player gate of HARVEST and the release of MOVE and STOP.

const RecordingProbe: GDScript = preload("res://tests/sim/recording_probe.gd")
const Worlds: GDScript = preload("res://tests/sim/support/harvest_worlds.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const MINE: int = World.HarvestMode.MINE
const RETURN: int = World.HarvestMode.RETURN
const IDLE: int = World.HarvestMode.IDLE


func test_every_new_command_type_is_dropped_and_counted_until_its_row() -> void:
	var commands: Dictionary[String, Command] = {
		"place": Command.place(1, 20500, 4500),
		"queue": Command.queue(1, 0),
		"cancel": Command.cancel(1, 0, 0),
		"rally": Command.rally(1, 1, 20500, 4500),
		"harvest": Command.harvest(1, PackedInt32Array([1]), 20500, 4500),
		"surrender": Command.surrender(1),
	}
	var base: World = _arena()
	Sim.step(base, [])
	for label: String in commands:
		var command: Command = commands[label]
		command.tick = 0
		var world: World = _arena()
		Sim.step(world, [command])
		assert_int(world.dropped_commands).override_failure_message(label).is_equal(1)
		# The counter is in the header; nothing else of the state moved.
		assert_array(_differing(base, world)).override_failure_message(label).is_equal(["header"])
		assert_array([world.match_end_tick, world.winner]).is_equal([0, 0])
		assert_array(world.defeated_tick).is_equal([0, 0, 0])


## Types 15-19 and 21-29 stay reserved: no branch, so dropped as unknown like any other.
func test_the_reserved_types_next_to_the_new_ones_are_still_unknown() -> void:
	for type: int in [9, 15, 19, 21, 29]:
		var command: Command = Command.surrender(1)
		command.type = type
		command.tick = 0
		var world: World = _arena()
		Sim.step(world, [command])
		assert_int(world.dropped_commands).override_failure_message(str(type)).is_equal(1)


## The new types need a player who is not defeated; a player past the arrays (a hand-built world
## may raise player_count after prepare()) is not playing either.
func test_a_defeated_or_unknown_player_is_not_playing() -> void:
	var world: World = _arena()
	var command: Command = Command.queue(1, 0)
	assert_bool(Sim._playing(world, command)).is_true()
	world.defeated_tick[1] = 40
	assert_bool(Sim._playing(world, command)).is_false()
	assert_bool(Sim._playing(world, Command.queue(2, 0))).is_true()
	world.player_count = 3
	assert_bool(Sim._playing(world, Command.queue(3, 0))).is_false()


## The skeleton modules change nothing: each `run`, and `release`, leaves the state hash and every
## part of it as it was (Power.run rebuilds the derived row lists since P71, which are in no hash
## section), and each `apply_*` refuses a command that looks right (the arena has no producer for a
## QUEUE and no item for a CANCEL, since P73, and no harvester or ore for a HARVEST, since P75b).
func test_the_stub_modules_change_no_state_and_refuse_every_command() -> void:
	var world: World = _arena()
	var before: PackedInt64Array = world.hash_parts()
	var hash_before: int = world.state_hash()
	Power.run(world)
	Harvest.run(world)
	Production.run(world)
	Outcome.run(world)
	LastSeen.run(world)
	Harvest.release(world, PackedInt32Array([0, 1, 2]))
	assert_int(world.state_hash()).is_equal(hash_before)
	assert_array(world.hash_parts()).is_equal(before)
	assert_bool(Production.apply_queue(world, Command.queue(1, 0))).is_false()
	assert_bool(Production.apply_cancel(world, Command.cancel(1, 0, 0))).is_false()
	assert_bool(Production.apply_place(world, Command.place(1, 20500, 4500))).is_false()
	var ids: PackedInt32Array = PackedInt32Array([1])
	assert_bool(Harvest.apply_harvest(world, Command.harvest(1, ids, 20500, 4500))).is_false()
	assert_bool(Outcome.apply_rally(world, Command.rally(1, 1, 20500, 4500))).is_false()
	assert_bool(Outcome.apply_surrender(world, Command.surrender(1))).is_false()


## A MOVE and a STOP on units that are no harvesters work as in Phase 2, the order and the
## formation slot included, though `Sim` hands them to `Harvest.release`: it leaves their harvest
## columns alone (every row of the arena stays IDLE, with no cargo, cell or home).
func test_a_move_and_a_stop_on_units_that_are_no_harvesters_work_as_in_phase_2() -> void:
	var world: World = _arena()
	var move: Command = Command.move(1, PackedInt32Array([1, 2]), 20500, 4500)
	move.tick = 0
	Sim.step(world, [move])
	assert_int(world.dropped_commands).is_equal(0)
	assert_array([world.order[0], world.order[1]]).is_equal([World.Order.MOVE, World.Order.MOVE])
	var stop: Command = Command.stop(1, PackedInt32Array([1]))
	stop.tick = 1
	Sim.step(world, [stop])
	assert_int(world.dropped_commands).is_equal(0)
	assert_array([world.order[0], world.order[1]]).is_equal([World.Order.IDLE, World.Order.MOVE])
	assert_int(world.harvest_mode.count(IDLE)).is_equal(world.unit_count())
	assert_array([world.cargo.count(0), world.home.count(0)]).is_equal(
		[world.unit_count(), world.unit_count()]
	)
	assert_int(world.harvest_slot.count(-1)).is_equal(world.unit_count())


## A MOVE and a STOP send a harvester that is in its loop to IDLE through `Harvest.release`, and it
## keeps what it carries, its cell and its refinery; the order is the command's.
func test_a_move_or_a_stop_sends_a_looping_harvester_to_idle() -> void:
	var world: World = _ore_world()
	var refinery: int = Worlds.add_refinery(world, 1, 5, 1)  # Dock (6, 4); a home that stands.
	var miner: int = Worlds.add_harvester(world, 1, 3500, 2500, MINE, 0, refinery, 100)
	var returner: int = Worlds.add_harvester(world, 1, 3500, 4500, RETURN, 0, refinery, 200)
	var move: Command = Command.move(1, PackedInt32Array([miner]), 7500, 4500)
	Worlds.send(world, [move])
	var row: int = world.index_of(miner)
	assert_array([world.harvest_mode[row], world.order[row]]).is_equal([IDLE, World.Order.MOVE])
	assert_int(Worlds.mode_of(world, returner)).is_equal(RETURN)  # Not in the command.
	Worlds.send(world, [Command.stop(1, PackedInt32Array([returner]))])
	row = world.index_of(returner)
	assert_array([world.harvest_mode[row], world.order[row]]).is_equal([IDLE, World.Order.IDLE])
	assert_array([world.dropped_commands, Worlds.mode_of(world, miner)]).is_equal([0, IDLE])
	assert_array([world.cargo[world.index_of(miner)], world.cargo[row]]).is_equal([100, 200])
	assert_array([world.harvest_slot[world.index_of(miner)], world.harvest_slot[row]]).is_equal(
		[0, 0]
	)
	assert_array([world.home[world.index_of(miner)], world.home[row]]).is_equal(
		[refinery, refinery]
	)


## HARVEST needs a player who is not defeated, and `Sim` is where that is decided: on a world where
## the module takes the command (a harvester and a cell in reach), a defeated player's HARVEST is
## dropped and counted and changes nothing, while the same command on the same world, called on the
## module directly, is accepted, and an undefeated player's goes through `Sim` and applies.
func test_a_defeated_players_harvest_is_dropped_and_counted_though_the_module_accepts_it() -> void:
	var worlds: Array[World] = []
	for _case: int in 3:
		var world: World = _ore_world()
		Worlds.add_harvester(world, 1, 3500, 4500, MINE, -1, 0, 100)
		worlds.append(world)
	var command: Command = Command.harvest(1, PackedInt32Array([1]), 3500, 2500)
	var gated: World = worlds[0]
	var direct: World = worlds[1]
	var playing: World = worlds[2]
	gated.defeated_tick[1] = 40
	direct.defeated_tick[1] = 40
	assert_bool(Harvest.apply_harvest(direct, command)).is_true()
	assert_int(Worlds.mode_of(direct, 1)).is_equal(World.HarvestMode.SEEK)
	var before: Array[int] = Worlds.columns_of(gated, 1)
	Worlds.send(gated, [command])
	assert_int(gated.dropped_commands).is_equal(1)
	assert_array(Worlds.columns_of(gated, 1)).is_equal(before)
	assert_int(gated.stats[World.Stat.ORE_SCANNED]).is_equal(0)  # Never reached the module.
	Worlds.send(playing, [command])
	assert_int(playing.dropped_commands).is_equal(0)
	assert_array(Worlds.columns_of(playing, 1)).is_equal(
		[World.HarvestMode.SEEK, 0, World.Order.MOVE, 3500, 2500, 100, 0]
	)


## One tick marks every phase once, in id order, and the three Phase 3 phases follow FOG; a run of
## the arena through them is the run without a probe (the hashes are equal at every tick).
func test_a_tick_runs_the_three_phases_after_fog_and_the_probe_changes_nothing() -> void:
	var plain: World = _arena()
	var probed: World = _arena()
	var probe: Variant = RecordingProbe.new()
	for _tick: int in 30:
		Sim.step(plain, [])
		Sim.step(probed, [], probe)
		assert_int(probed.state_hash()).is_equal(plain.state_hash())
	var calls: PackedInt32Array = probe.calls
	var one_tick: PackedInt32Array = PackedInt32Array([-1])
	one_tick.append_array(PackedInt32Array(range(SimProbe.Phase.COUNT)))
	assert_int(calls.size()).is_equal(30 * one_tick.size())
	assert_array(calls.slice(calls.size() - one_tick.size())).is_equal(one_tick)
	var tail: PackedInt32Array = calls.slice(calls.size() - 4)
	assert_array(tail).is_equal(
		[
			SimProbe.Phase.FOG,
			SimProbe.Phase.ECONOMY,
			SimProbe.Phase.PRODUCTION,
			SimProbe.Phase.MEMORY
		]
	)


func _arena() -> World:
	return World.from_scenario(load(ARENA_PATH) as ScenarioDef)


## A 10 x 6 grass map with one ore cell at the tile (3, 2), centre (3 500, 2 500), that never grows
## (its cap is 0): the world of the Harvest cases, which add their own harvesters.
func _ore_world() -> World:
	var world: World = Worlds.world(Worlds.grass(10, 6, [Vector2i(3, 2)]))
	world.ore_cell_max = 0
	return world


## The names of the hash sections where `a` and `b` differ.
func _differing(a: World, b: World) -> Array[String]:
	var names: PackedStringArray = World.hash_section_names()
	var left: PackedInt64Array = a.hash_parts()
	var right: PackedInt64Array = b.hash_parts()
	var found: Array[String] = []
	for index: int in names.size():
		if left[index] != right[index]:
			found.append(names[index])
	return found
