extends GdUnitTestSuite
## Defeat and the end of a match (plan row P76, ADR 0017 section 5, ADR 0018 section 7): a player
## whose `had_producer` is 1 and who owns no building that produces a tab is defeated in the step
## that finds it, SURRENDER defeats at once, and when somebody has fallen and at most one player
## is left the match ends in the same step, with the player left as `winner` (0 for a draw).
## `defeated_tick` and `match_end_tick` hold the tick the step produces, `tick + 1`, so the first
## step writes 1. A ready structure in a queue and the buildings that produce nothing do not save a
## player; a side that never owned a producer is never defeated by the rule and a World of units
## only runs on, applying Commands, as does the controls scenario. The world is
## `production_worlds.gd`'s base world: player 1 owns a power plant (id 1), a barracks (id 2), a
## refinery (id 3) and a vehicle factory (id 4), player 2 a barracks (id 5).

const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const PlaceRig: GDScript = preload("res://tests/sim/support/place_rig.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const TargetingRig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const CONTROLS_PATH: String = "res://data/scenarios/controls_test.tres"
const SEED: int = 42
const TICKS: int = 900


## [defeated_tick of player 1, of player 2, match_end_tick, winner].
func _state(world: World) -> Array[int]:
	return [world.defeated_tick[1], world.defeated_tick[2], world.match_end_tick, world.winner]


## Makes building `id` die in the next step: REMOVE takes its row.
func _kill(world: World, id: int) -> void:
	world.hp[world.index_of(id)] = 0


## A player that loses its last producer is defeated by the step that finds it, stamped with that
## step's tick (the seventh step makes tick 7), the match ends in the same step and the other
## player wins. Nothing is stamped before, and the later steps change none of it.
func test_the_last_producer_destroyed_defeats_the_player_and_the_other_one_wins() -> void:
	var world: World = Rig.base()
	Rig.run(world, 6)
	assert_array(_state(world)).is_equal([0, 0, 0, 0])
	_kill(world, Rig.ENEMY_BARRACKS)
	Rig.step(world)
	assert_int(world.tick).is_equal(7)
	assert_array(_state(world)).is_equal([0, 7, 7, 1])
	Rig.run(world, 5)
	assert_array(_state(world)).is_equal([0, 7, 7, 1])
	assert_int(world.dropped_commands).is_equal(0)


## Only a building that produces a tab keeps a player in: the plant and the refinery dying are no
## defeat, and a player left with only those is defeated, with its rows still on the map.
func test_only_the_buildings_that_produce_count_and_a_defeated_player_keeps_its_rows() -> void:
	var spared: World = Rig.base()
	_kill(spared, Rig.PLANT)
	_kill(spared, Rig.REFINERY)
	Rig.run(spared, 3)
	assert_array(_state(spared)).is_equal([0, 0, 0, 0])
	var world: World = Rig.base()
	_kill(world, Rig.BARRACKS)
	Rig.step(world)
	assert_array(_state(world)).is_equal([0, 0, 0, 0])
	_kill(world, Rig.FACTORY)
	Rig.step(world)
	assert_array(_state(world)).is_equal([2, 0, 2, 2])
	var rows: Array[int] = []
	for row: int in world.unit_count():
		if world.owner[row] == 1:
			rows.append(world.unit_id[row])
	assert_array(rows).is_equal([Rig.PLANT, Rig.REFINERY])


## The Headquarters is a producer too (it produces STRUCTURES): player 2 keeps playing on it alone
## after its barracks died, and is defeated when it falls.
func test_the_headquarters_alone_keeps_a_player_in_until_it_falls() -> void:
	var world: World = Rig.base()
	var headquarters: int = world.add_building(2, Worlds.type_of(world, "headquarters"), 14, 12)
	assert_int(headquarters).is_greater(0)
	_kill(world, Rig.ENEMY_BARRACKS)
	Rig.run(world, 3)
	assert_array(_state(world)).is_equal([0, 0, 0, 0])
	_kill(world, headquarters)
	Rig.step(world)
	assert_array(_state(world)).is_equal([0, 4, 4, 1])


## Both players' last producers on one tick is a draw: both are stamped with the tick and the
## winner is 0. So is a surrender on the tick the other player loses its last producer.
func test_both_on_one_tick_is_a_draw() -> void:
	var world: World = Rig.base()
	Rig.run(world, 4)
	for id: int in [Rig.BARRACKS, Rig.FACTORY, Rig.ENEMY_BARRACKS]:
		_kill(world, id)
	Rig.step(world)
	assert_array(_state(world)).is_equal([5, 5, 5, 0])
	var mixed: World = Rig.base()
	_kill(mixed, Rig.ENEMY_BARRACKS)
	Rig.step(mixed, [Command.surrender(1)])
	assert_array(_state(mixed)).is_equal([1, 1, 1, 0])


## SURRENDER defeats its player at once, in the step of the command, and the match ends in that
## step with the other player the winner; the command is applied, not dropped. Player 2
## surrendering hands the win to player 1.
func test_a_surrender_defeats_the_player_in_its_own_step() -> void:
	var world: World = Rig.base()
	Rig.run(world, 5)
	Rig.step(world, [Command.surrender(1)])
	assert_int(world.tick).is_equal(6)
	assert_array(_state(world)).is_equal([6, 0, 6, 2])
	assert_int(world.dropped_commands).is_equal(0)
	var other: World = Rig.base()
	Rig.run(other, 2)
	Rig.step(other, [Command.surrender(2)])
	assert_array(_state(other)).is_equal([0, 3, 3, 1])
	assert_int(other.dropped_commands).is_equal(0)


## A structure that is ready at the head of the queue does not save its player: with the
## Headquarters, the barracks and the factory gone, player 1 is defeated although the power plant
## still waits to be placed (the head stays ready and the queue is as it was).
func test_a_ready_structure_does_not_prevent_defeat() -> void:
	var world: World = PlaceRig.world()
	var headquarters: int = world.unit_id[Rig.rows_of(world, 1, "headquarters")[0]]
	PlaceRig.ready(world, "power_plant")
	var queue: int = PlaceRig.queue()
	var goal: int = PlaceRig.build_ticks(world, "power_plant") * Production.PROGRESS_PER_TICK
	assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal([1, goal])
	var before: int = world.tick
	for id: int in [headquarters, Rig.BARRACKS, Rig.FACTORY]:
		_kill(world, id)
	Rig.step(world)
	assert_array(_state(world)).is_equal([before + 1, 0, before + 1, 2])
	assert_array([world.queue_count[queue], world.queue_progress[queue]]).is_equal([1, goal])


## A defeat and an end on the first step read 1: 0 keeps meaning "playing" and "running".
func test_a_defeat_and_an_end_on_the_first_step_are_stamped_1() -> void:
	var lost: World = Rig.base()
	_kill(lost, Rig.ENEMY_BARRACKS)
	Rig.step(lost)
	assert_array(_state(lost)).is_equal([0, 1, 1, 1])
	var gave_up: World = Rig.base()
	Rig.step(gave_up, [Command.surrender(1)])
	assert_array(_state(gave_up)).is_equal([1, 0, 1, 2])


## A side that never owned a producer is never defeated by the rule, whatever it owns: player 1
## here has a power plant and a unit and no producer (`had_producer` 0) and plays on until player 2
## loses its barracks, which makes player 1 the winner without ever being checked.
func test_a_side_that_never_owned_a_producer_is_never_defeated_and_wins_by_default() -> void:
	var world: World = Worlds.open(24, 16, Rig.IDS)
	world.add_building(1, Worlds.type_of(world, "power_plant"), 2, 1)
	world.add_unit(1, Worlds.type_of(world, "rifle_squad"), 500, 500)
	var barracks: int = world.add_building(2, Worlds.type_of(world, "barracks"), 8, 12)
	assert_array([world.had_producer[1], world.had_producer[2]]).is_equal([0, 1])
	Rig.run(world, 60)
	assert_array(_state(world)).is_equal([0, 0, 0, 0])
	_kill(world, barracks)
	Rig.step(world)
	assert_array(_state(world)).is_equal([0, 61, 61, 1])
	assert_int(world.had_producer[1]).is_equal(0)


## A hand-built World with units only keeps applying Commands for 900 ticks: nobody owned a
## producer, so nobody is defeated and the match never ends, with two players and with one (a lone
## player is not a match that has ended). A MOVE, an ATTACK_MOVE and a STOP of the last tick still
## apply and nothing was dropped.
func test_a_world_of_units_only_applies_commands_for_900_ticks() -> void:
	for players: int in [2, 1]:
		var world: World = _units_only(players)
		var ids: PackedInt32Array = PackedInt32Array([1, 2])
		for tick: int in TICKS:
			var commands: Array[Command] = []
			if tick % 100 == 0 or tick == TICKS - 1:
				var east: int = 3000 if tick % 200 == 0 else 0
				commands.append(Command.move(1, ids, 2500 + east, 2500))
				if players == 2:
					commands.append(Command.attack_move(2, PackedInt32Array([3]), 16500, 9500))
			Rig.step(world, commands)
		var label: String = "%d players" % players
		assert_int(world.tick).override_failure_message(label).is_equal(TICKS)
		assert_int(world.dropped_commands).override_failure_message(label).is_equal(0)
		assert_array(world.defeated_tick).override_failure_message(label).is_equal(
			_zeros(players + 1)
		)
		assert_array([world.match_end_tick, world.winner]).override_failure_message(label).is_equal(
			[0, 0]
		)
		assert_int(world.order[0]).override_failure_message(label).is_equal(World.Order.MOVE)


## The controls scenario (the preview's main scene) has units only: 900 ticks with its orders and a
## tap every 100 ticks keep `match_end_tick` 0, nobody defeated and every Command applied, though
## the tanks fight on the far side and red's group there dies.
func test_the_controls_scenario_runs_900_ticks_without_an_end() -> void:
	var scenario: ScenarioDef = load(CONTROLS_PATH) as ScenarioDef
	var world: World = World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	var loop: MatchLoop = MatchLoop.create(scenario, CONTROLS_PATH, SEED, world)
	var ids: PackedInt32Array = PackedInt32Array(range(1, 31))
	for tick: int in TICKS:
		var queued: Array[Command] = []
		if tick % 100 == 0:
			queued.append(Command.attack_move(1, ids, 28500, 39500))
		loop.step(world, queued)
	assert_int(world.tick).is_equal(TICKS)
	assert_int(world.dropped_commands).is_equal(0)
	assert_array(world.defeated_tick).is_equal(_zeros(3))
	assert_array([world.match_end_tick, world.winner]).is_equal([0, 0])


## Two sides of units (rifle squad type 0, light tank type 1), far apart: player 1's rows 0 and 1
## (ids 1 and 2) and, with two players, player 2's id 3.
func _units_only(players: int) -> World:
	var units: Array[UnitDef] = [
		load(Worlds.UNIT_DIR + "rifle_squad.tres") as UnitDef,
		load(Worlds.UNIT_DIR + "light_tank.tres") as UnitDef,
	]
	var world: World = TargetingRig.world_of(units, 20, 12, true, players)
	world.add_unit(1, 0, 2500, 2500)
	world.add_unit(1, 1, 3500, 2500)
	if players == 2:
		world.add_unit(2, 0, 17500, 9500)
	return world


## `count` zeros.
func _zeros(count: int) -> Array[int]:
	var zeros: Array[int] = []
	zeros.resize(count)
	return zeros
