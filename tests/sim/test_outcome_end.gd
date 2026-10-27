extends GdUnitTestSuite
## After the end and around the gates (plan row P76, ADR 0017 section 4, ADR 0018 section 7): once
## `match_end_tick` is above 0 `Sim.step` drops every Command of any type and `Outcome.run` leaves
## `match_end_tick`, `winner` and the stamps alone; a Command of the ending step itself still
## applies. RALLY and SURRENDER need an undefeated player through `Sim._playing`, which the
## `Outcome.apply_*` functions do not ask for (a defeated player's SURRENDER would rewrite its
## `defeated_tick` if it got through). The queues of a defeated player stop while the match goes on
## for the others (three players here), and the match ends when one is left.

const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const PlaceRig: GDScript = preload("res://tests/sim/support/place_rig.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const TargetingRig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const INFANTRY: int = World.Tab.INFANTRY


## [defeated_tick of player 1, of player 2, match_end_tick, winner].
func _state(world: World) -> Array[int]:
	return [world.defeated_tick[1], world.defeated_tick[2], world.match_end_tick, world.winner]


## Makes building `id` die in the next step: REMOVE takes its row.
func _kill(world: World, id: int) -> void:
	world.hp[world.index_of(id)] = 0


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


## The base world with player 1's headquarters, a power plant ready to be placed, a rifle squad
## queued (the item to cancel), a rifle squad of player 1 and one of player 2 far apart (the units
## to order and to attack), after one more step; with `ended`, player 2's barracks dies in that
## step, so player 2 is defeated, player 1 has won and `match_end_tick` is set.
func _world(ended: bool) -> World:
	var world: World = PlaceRig.world()
	PlaceRig.ready(world, "power_plant")
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
	var rifle: int = Worlds.type_of(world, "rifle_squad")
	world.add_unit(1, rifle, 5500, 9500)
	world.add_unit(2, rifle, 20500, 13500)
	if ended:
		_kill(world, Rig.ENEMY_BARRACKS)
	Rig.step(world)
	return world


## One fresh Command of each kind for `world` (built by `_world`), each valid while the match runs
## but a HARVEST (the base world has no ore).
func _commands(world: World) -> Dictionary[String, Command]:
	var mine: PackedInt32Array = PackedInt32Array(
		[world.unit_id[Rig.rows_of(world, 1, "rifle_squad")[0]]]
	)
	var foe: int = world.unit_id[Rig.rows_of(world, 2, "rifle_squad")[0]]
	return {
		"move": Command.move(1, mine, 6500, 9500),
		"attack_move": Command.attack_move(1, mine, 6500, 9500),
		"stop": Command.stop(1, mine),
		"attack": Command.attack(1, mine, foe),
		"place": PlaceRig.place(6, 5),
		"queue": Rig.queue(world, 1, "rifle_squad"),
		"cancel": Command.cancel(1, INFANTRY, 0),
		"rally": Command.rally(1, Rig.BARRACKS, 15500, 9500),
		"harvest": Command.harvest(1, mine, 6500, 9500),
		"surrender": Command.surrender(1),
	}


## Every kind of Command applies while the match runs (except HARVEST, which has no ore here) and
## is dropped and counted after the end, leaving the state exactly as the same step without it:
## only the dropped counter in the header differs.
func test_no_command_applies_once_the_match_has_ended() -> void:
	for label: String in _commands(_world(false)):
		var running: World = _world(false)
		var ended: World = _world(true)
		var control: World = _world(true)
		assert_int(ended.match_end_tick).override_failure_message(label).is_greater(0)
		assert_int(running.match_end_tick).override_failure_message(label).is_equal(0)
		var before: int = ended.dropped_commands
		if label != "harvest":
			Rig.step(running, [_commands(running)[label]])
			assert_int(running.dropped_commands).override_failure_message(label).is_equal(0)
		Rig.step(ended, [_commands(ended)[label]])
		Rig.step(control)
		assert_int(ended.dropped_commands).override_failure_message(label).is_equal(before + 1)
		assert_array(_differing(ended, control)).override_failure_message(label).is_equal(
			["header"]
		)
		assert_array([ended.match_end_tick, ended.winner]).is_equal(
			[control.match_end_tick, control.winner]
		)


## The end is set in PRODUCTION, after the Commands of its step: a command of the ending step
## applies, the next one is dropped and counted.
func test_a_command_of_the_ending_step_applies_and_the_next_one_is_dropped() -> void:
	var world: World = Rig.base()
	var queue: int = Rig.queue_of(1, INFANTRY)
	_kill(world, Rig.ENEMY_BARRACKS)
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
	assert_int(world.match_end_tick).is_equal(1)
	assert_array([world.dropped_commands, world.queue_count[queue]]).is_equal([0, 1])
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad")])
	assert_array([world.dropped_commands, world.queue_count[queue]]).is_equal([1, 1])


## Once set, `match_end_tick` and `winner` stay, and nobody else is defeated: a World that was
## given an end by hand keeps it though both sides lose every producer, and a match that ended with
## player 1 the winner stays that way when player 1 loses its producers on later ticks.
func test_the_outcome_leaves_the_end_alone_once_it_is_set() -> void:
	var set_by_hand: World = Rig.base()
	set_by_hand.match_end_tick = 50
	set_by_hand.winner = 2
	for id: int in [Rig.BARRACKS, Rig.FACTORY, Rig.ENEMY_BARRACKS]:
		_kill(set_by_hand, id)
	Rig.step(set_by_hand)
	Outcome.run(set_by_hand)
	assert_array(_state(set_by_hand)).is_equal([0, 0, 50, 2])
	var played: World = Rig.base()
	_kill(played, Rig.ENEMY_BARRACKS)
	Rig.step(played)
	assert_array(_state(played)).is_equal([0, 1, 1, 1])
	_kill(played, Rig.BARRACKS)
	_kill(played, Rig.FACTORY)
	Rig.run(played, 5)
	Outcome.run(played)
	assert_array(_state(played)).is_equal([0, 1, 1, 1])


## The `_playing` gate for SURRENDER: a defeated player's command is dropped and counted and its
## `defeated_tick` stays, although `apply_surrender` called on its own takes the command and
## writes the new stamp. A player past the match and a payload drop it too, with nobody defeated.
func test_a_defeated_players_surrender_is_dropped_by_the_gate() -> void:
	var direct: World = Rig.base()
	direct.defeated_tick[1] = 3
	assert_bool(Outcome.apply_surrender(direct, Command.surrender(1))).is_true()
	assert_int(direct.defeated_tick[1]).is_equal(direct.tick + 1)
	var world: World = Rig.base()
	world.defeated_tick[1] = 3
	Rig.step(world, [Command.surrender(1)])
	assert_int(world.dropped_commands).is_equal(1)
	assert_int(world.defeated_tick[1]).is_equal(3)
	var late: World = Rig.base()
	var payload: Command = Command.surrender(1)
	payload.payload = PackedInt32Array([1])
	Rig.step(late, [Command.surrender(3), payload])
	assert_int(late.dropped_commands).is_equal(2)
	assert_array(_state(late)).is_equal([0, 0, 0, 0])


## Called on their own the two functions refuse a player outside the arrays and a payload, and
## change nothing.
func test_the_apply_functions_refuse_a_player_outside_the_match() -> void:
	var world: World = Rig.base()
	var before: int = world.state_hash()
	for player: int in [0, 3, 7, -1]:
		assert_bool(Outcome.apply_surrender(world, Command.surrender(player))).is_false()
		var rally: Command = Command.rally(player, Rig.BARRACKS, 15500, 9500)
		assert_bool(Outcome.apply_rally(world, rally)).is_false()
	assert_int(world.state_hash()).is_equal(before)


## Three players: a surrender ends no match while two are left, and the surrendered player's queue
## stops where it was (its barracks stands) while the others' go on; the match ends in the step
## that defeats the second player, with the third as the winner.
func test_a_defeated_players_queues_stop_and_the_match_ends_when_one_is_left() -> void:
	var world: World = _three_players()
	var first: int = Rig.queue_of(1, INFANTRY)
	var second: int = Rig.queue_of(2, INFANTRY)
	Rig.step(world, [Rig.queue(world, 1, "rifle_squad"), Rig.queue(world, 2, "rifle_squad", 1)])
	Rig.run(world, 9)
	assert_array([world.queue_progress[first], world.queue_progress[second]]).is_equal([1000, 1000])
	Rig.step(world, [Command.surrender(1)])
	assert_array([world.defeated_tick[1], world.match_end_tick]).is_equal([11, 0])
	assert_array([world.queue_progress[first], world.queue_progress[second]]).is_equal([1000, 1100])
	var ticks: int = world.type_build_ticks[Worlds.type_of(world, "rifle_squad")]
	Rig.run(world, ticks)
	assert_int(Rig.rows_of(world, 1, "rifle_squad").size()).is_equal(0)
	assert_int(Rig.rows_of(world, 2, "rifle_squad").size()).is_equal(1)
	var paid: int = world.start_credits - world.type_cost[Worlds.type_of(world, "rifle_squad")]
	assert_array([world.queue_count[first], world.queue_progress[first]]).is_equal([1, 1000])
	assert_array([world.stat_built[1], world.stat_built[2], world.credits[1]]).is_equal(
		[0, 1, paid]
	)
	assert_array([world.match_end_tick, world.winner]).is_equal([0, 0])
	_kill(world, world.unit_id[Rig.rows_of(world, 3, "barracks")[0]])
	Rig.step(world)
	assert_array([world.defeated_tick[3], world.match_end_tick, world.winner]).is_equal(
		[world.tick, world.tick, 2]
	)
	assert_int(world.defeated_tick[2]).is_equal(0)


## Three players, each with a barracks and a power plant (so that none is on low power), 8 tiles
## apart along the north edge: the barracks of player p stands at tile (1 + 8 * (p - 1), 1), its
## exit 7.5 tiles or more from any enemy building.
func _three_players() -> World:
	var units: Array[UnitDef] = []
	for id: String in Rig.IDS:
		units.append(load(Worlds.UNIT_DIR + id + ".tres") as UnitDef)
	var world: World = TargetingRig.world_of(units, 24, 12, true, 3)
	for player: int in range(1, 4):
		var column: int = 1 + (player - 1) * 8
		world.add_building(player, Worlds.type_of(world, "barracks"), column, 1)
		Rig.add_plant(world, player, column, 6)
	return world
