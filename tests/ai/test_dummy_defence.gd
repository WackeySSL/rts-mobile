extends GdUnitTestSuite
## What the dummy's defence orders at one think (plan row P83b, ADR 0020 section 4 "Defend"; the
## rules are in the header of `DummyDefence`). Each case is a think on the skirmish-like start of
## `ai_rig.gd` that the case changed (an enemy row given, a unit given or ordered), and where it
## matters the Commands go through the loop to show that the sim keeps every one
## (`dropped_commands` 0).
##
## The start: player 1's Headquarters has its top-left tile at (6, 6), so its centre is (7,500,
## 7,500) milli-tiles and it sees 7 tiles round it; its two rifle squads stand at tiles (4, 10);
## the shipped guard point is two tiles from the centre on each axis, (9,500, 9,500). Cases that
## need an enemy at the edge of the radius use a def with `defend_radius_tiles` 5, so that the
## enemy is inside the Headquarters' sight; the shipped radius of 12 is out of it.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const Audit: GDScript = preload("res://tests/ai/support/defence_audit.gd")
const GUARD_1: Vector2i = Vector2i(9500, 9500)
const GUARD_2: Vector2i = Vector2i(29500, 29500)


func test_an_enemy_within_the_radius_is_met_with_attack_move_to_its_position() -> void:
	var world: World = _start()
	var loop: MatchLoop = Rig.loop_of(world)
	Rig.add_unit_of(world, 2, "rifle_squad", 11500, 7500)
	var moves: Array[Command] = _moves(_think(world, Rig.ai_of(_def(5), 1)))
	assert_int(moves.size()).is_equal(1)
	assert_int(moves[0].player_id).is_equal(1)
	assert_array(Array(moves[0].unit_ids)).is_equal(Array(Rig.ids_of(world, 1, "rifle_squad")))
	assert_vector(Vector2i(moves[0].target_x, moves[0].target_y)).is_equal(Vector2i(11500, 7500))
	Rig.step(world, loop, moves)
	assert_int(world.dropped_commands).is_equal(0)
	for row: int in world.unit_count():
		if world.owner[row] == 1 and world.type_index[row] == Rig.type_of(world, "rifle_squad"):
			assert_int(world.order[row]).is_equal(World.Order.ATTACK_MOVE)


func test_the_radius_includes_its_edge_and_not_a_milli_tile_beyond() -> void:
	var world: World = _start()
	var enemy: int = Rig.add_unit_of(world, 2, "rifle_squad", 12500, 7500)
	# 5,000 milli-tiles from the Headquarters' centre: on the edge, so a threat.
	assert_array(_targets(_think(world, Rig.ai_of(_def(5), 1)))).is_equal([Vector2i(12500, 7500)])
	world.pos_x[world.index_of(enemy)] = 12501
	assert_array(_targets(_think(world, Rig.ai_of(_def(5), 1)))).is_equal([GUARD_1])


func test_every_building_counts_not_only_the_headquarters() -> void:
	var world: World = _start()
	var loop: MatchLoop = Rig.loop_of(world)
	Rig.give(world, 1, "defence_turret", 14, 6)
	Rig.settle(world, loop)
	# The turret's centre is (14,500, 6,500) and its sight 7 tiles. The enemy is 4 tiles from it
	# and 11 from the Headquarters, which is outside the radius of 5.
	Rig.add_unit_of(world, 2, "rifle_squad", 18500, 6500)
	assert_array(_targets(_think(world, Rig.ai_of(_def(5), 1)))).is_equal([Vector2i(18500, 6500)])


func test_a_building_of_the_enemy_is_a_threat_too() -> void:
	var world: World = _start()
	Rig.give(world, 2, "defence_turret", 11, 7)
	assert_array(_targets(_think(world, Rig.ai_of(_def(5), 1)))).is_equal([Vector2i(11500, 7500)])


func test_the_most_pressing_threat_is_the_nearest_one_and_a_tie_goes_to_the_lower_row() -> void:
	var world: World = _start()
	Rig.add_unit_of(world, 2, "rifle_squad", 11500, 7500)
	Rig.add_unit_of(world, 2, "rifle_squad", 10500, 7500)
	assert_array(_targets(_think(world, Rig.ai_of(_def(5), 1)))).is_equal([Vector2i(10500, 7500)])
	# Two enemies 4 tiles from the centre: the one of the lower row, whichever side it is on.
	for first: Vector2i in [Vector2i(11500, 7500), Vector2i(7500, 11500)]:
		var tied: World = _start()
		Rig.add_unit_of(tied, 2, "rifle_squad", first.x, first.y)
		Rig.add_unit_of(tied, 2, "rifle_squad", first.y, first.x)
		assert_array(_targets(_think(tied, Rig.ai_of(_def(5), 1)))).is_equal([first])


func test_with_no_threat_the_units_go_to_the_guard_point_beside_the_headquarters() -> void:
	var world: World = _start()
	var loop: MatchLoop = Rig.loop_of(world)
	for player: int in [1, 2]:
		var moves: Array[Command] = _moves(_think(world, Rig.dummy(player)))
		assert_int(moves.size()).is_equal(1)
		assert_array(Array(moves[0].unit_ids)).is_equal(
			Array(Rig.ids_of(world, player, "rifle_squad"))
		)
		assert_vector(Vector2i(moves[0].target_x, moves[0].target_y)).is_equal(
			GUARD_1 if player == 1 else GUARD_2
		)
		Rig.step(world, loop, moves)
	assert_int(world.dropped_commands).is_equal(0)


func test_the_guard_point_is_beside_the_headquarters_else_beside_the_first_building() -> void:
	var world: World = _start()
	var loop: MatchLoop = Rig.loop_of(world)
	Rig.give(world, 1, "barracks", 20, 6)
	Rig.kill(world, loop, Rig.row_of(world, 1, "headquarters"))
	assert_int(world.defeated_tick[1]).is_equal(0)
	# The barracks (2 x 2, top-left tile (20, 6)) has its centre at (21,000, 7,000).
	assert_array(_targets(_think(world, Rig.dummy(1)))).is_equal([Vector2i(23000, 9000)])
	# A new Headquarters (a later row than the barracks) is the anchor again: its centre is
	# (31,500, 21,500).
	Rig.give(world, 1, "headquarters", 30, 20)
	assert_array(_targets(_think(world, Rig.dummy(1)))).is_equal([Vector2i(33500, 23500)])


func test_a_still_enemy_costs_one_order_and_the_units_keep_it_on_their_way_and_arrived() -> void:
	var world: World = _start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = Rig.dummy(1)
	var sent: Array[Command] = _moves(_think(world, ai))
	assert_int(sent.size()).is_equal(1)
	Rig.step(world, loop, sent)
	# On their way (ATTACK_MOVE, the guard point not reached): kept.
	assert_array(_moves(_think(world, ai))).is_empty()
	Rig.run(world, loop, [], 300)
	for id: int in Rig.ids_of(world, 1, "rifle_squad"):
		assert_int(world.order[world.index_of(id)]).is_equal(World.Order.IDLE)
	# Arrived (IDLE, where the defence sent them): kept.
	assert_array(_moves(_think(world, ai))).is_empty()


func test_the_units_return_to_the_guard_point_when_the_threat_is_gone() -> void:
	var world: World = _start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = Rig.ai_of(_def(5), 1)
	var enemy: int = Rig.add_unit_of(world, 2, "harvester", 11500, 7500)
	Rig.step(world, loop, _moves(_think(world, ai)))
	Rig.kill(world, loop, world.index_of(enemy))
	# The squads are still on their way to the harvester: sent back with one order, then kept.
	var back: Array[Command] = _moves(_think(world, ai))
	assert_array(_targets(back)).is_equal([GUARD_1])
	assert_array(Array(back[0].unit_ids)).is_equal(Array(Rig.ids_of(world, 1, "rifle_squad")))
	Rig.step(world, loop, back)
	assert_array(_moves(_think(world, ai))).is_empty()
	assert_int(world.dropped_commands).is_equal(0)


func test_a_unit_with_another_order_keeps_it() -> void:
	var world: World = _start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = Rig.dummy(1)
	var squads: PackedInt32Array = Rig.ids_of(world, 1, "rifle_squad")
	var third: int = Rig.add_unit_of(world, 1, "rifle_squad", 4500, 12500)
	# A MOVE of a player to the first squad and an ATTACK_MOVE that the defence did not give to the
	# third: neither is the defence's to order.
	var given: Array[Command] = [
		Command.move(1, PackedInt32Array([squads[0]]), 5500, 12500),
		Command.attack_move(1, PackedInt32Array([third]), 5500, 13500),
	]
	Rig.step(world, loop, given)
	var moves: Array[Command] = _moves(_think(world, ai))
	assert_int(moves.size()).is_equal(1)
	assert_array(Array(moves[0].unit_ids)).is_equal([squads[1]])
	Rig.step(world, loop, moves)
	assert_array(_moves(_think(world, ai))).is_empty()
	assert_int(world.dropped_commands).is_equal(0)


func test_harvesters_and_buildings_are_not_combat_units() -> void:
	var world: World = _start()
	var combat: Array[String] = []
	var view: PlayerView = PlayerView.of(world, 1)
	for type: int in world.type_ids.size():
		if DummyDefence.is_combat(view, type):
			combat.append(String(world.type_ids[type]))
	assert_array(combat).is_equal(["rifle_squad", "light_tank"])
	# The rule names harvesting itself: a harvester that carried a weapon would be none either.
	var harvester_type: int = Rig.type_of(world, "harvester")
	view.type_weapon[harvester_type] = 0
	assert_bool(DummyDefence.is_combat(view, harvester_type)).is_false()
	# An idle harvester and an idle tank: the tank joins the squads, the harvester gets nothing.
	var harvester: int = Rig.add_unit_of(world, 1, "harvester", 5500, 9500)
	var tank: int = Rig.add_unit_of(world, 1, "light_tank", 5500, 11500)
	var ids: PackedInt32Array = _moves(_think(world, Rig.dummy(1)))[0].unit_ids
	assert_bool(ids.has(tank)).is_true()
	assert_bool(ids.has(harvester)).is_false()
	assert_int(ids.size()).is_equal(3)


func test_a_unit_that_spawns_is_ordered_the_think_after_and_alone() -> void:
	var world: World = _start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: DummyAi = Rig.dummy(1)
	Rig.step(world, loop, _moves(_think(world, ai)))
	var tank: int = Rig.add_unit_of(world, 1, "light_tank", 5500, 11500)
	var moves: Array[Command] = _moves(_think(world, ai))
	assert_int(moves.size()).is_equal(1)
	assert_array(Array(moves[0].unit_ids)).is_equal([tank])
	assert_vector(Vector2i(moves[0].target_x, moves[0].target_y)).is_equal(GUARD_1)
	Rig.step(world, loop, moves)
	assert_array(_moves(_think(world, ai))).is_empty()
	assert_int(world.dropped_commands).is_equal(0)


func test_no_order_goes_beyond_the_radius_whatever_the_def_says() -> void:
	# (radius, offset) of defs that ask for more than they may: the offset is cut to half the radius
	# on each axis.
	var defs: Array[Array] = [
		[12, Vector2i(2, 2)],
		[4, Vector2i(9, -9)],
		[0, Vector2i(5, 5)],
		[12, Vector2i(-20, 30)],
	]
	for with_enemy: bool in [false, true]:
		for spec: Array in defs:
			var world: World = _start()
			if with_enemy:
				Rig.add_unit_of(world, 2, "rifle_squad", 10500, 7500)
			var def: AiDef = _def(spec[0])
			def.guard_offset_tiles = spec[1]
			var moves: Array[Command] = _moves(_think(world, Rig.ai_of(def, 1)))
			assert_int(moves.size()).is_equal(1)
			assert_bool(Audit.within(world, moves[0], spec[0])).is_true()


func test_a_neutral_row_is_no_threat() -> void:
	var world: World = _start()
	Rig.add_unit_of(world, 0, "rifle_squad", 11500, 7500)
	assert_int(PlayerView.of(world, 1).seen_rows.size()).is_equal(1)
	var ai: DummyAi = Rig.ai_of(_def(5), 1)
	assert_array(_targets(_think(world, ai))).is_equal([GUARD_1])
	assert_int(ai.defence.tests).is_equal(0)


func test_a_fogged_enemy_and_a_ghost_are_not_threats() -> void:
	var world: World = _start()
	# 12 tiles east of the Headquarters' centre: inside the shipped radius, outside the sight.
	var enemy: int = Rig.add_unit_of(world, 2, "rifle_squad", 19500, 7500)
	assert_int(PlayerView.of(world, 1).row_of(enemy)).is_equal(PlayerView.MISSING)
	# A last-seen record of an enemy barracks at the tile (10, 7), 3 tiles from the Headquarters.
	var first: int = 1 * world.ghost_cap
	world.ghost_id[first] = 999
	world.ghost_type[first] = Rig.type_of(world, "barracks")
	world.ghost_owner[first] = 2
	world.ghost_cell[first] = 7 * world.map_cols + 10
	world.ghost_count[1] = 1
	assert_int(PlayerView.of(world, 1).ghost_count).is_equal(1)
	var ai: DummyAi = Rig.dummy(1)
	assert_array(_targets(_think(world, ai))).is_equal([GUARD_1])
	assert_int(ai.defence.tests).is_equal(0)


func test_the_work_is_the_seen_rows_times_the_buildings() -> void:
	var world: World = _start()
	var loop: MatchLoop = Rig.loop_of(world)
	Rig.give(world, 1, "defence_turret", 14, 6)
	Rig.settle(world, loop)
	Rig.add_unit_of(world, 2, "rifle_squad", 10500, 7500)
	Rig.add_unit_of(world, 2, "rifle_squad", 11500, 7500)
	Rig.add_unit_of(world, 2, "rifle_squad", 30500, 30500)
	var view: PlayerView = PlayerView.of(world, 1)
	assert_int(view.seen_rows.size()).is_equal(2)
	var ai: DummyAi = Rig.dummy(1)
	ai.think(view, [] as Array[Command])
	# Two seen enemy rows against the Headquarters and the turret.
	assert_int(ai.defence.tests).is_equal(4)


func test_a_command_never_holds_more_units_than_the_sim_accepts() -> void:
	var rules: RulesDef = (load(Rig.RULES_PATH) as RulesDef).duplicate() as RulesDef
	rules.max_rows = 700
	rules.unit_cap = 700
	var shipped_map: Array[String] = []
	var world: World = Rig.start(shipped_map, rules)
	var loop: MatchLoop = Rig.loop_of(world)
	for _unit: int in 300:
		Rig.add_unit_of(world, 1, "light_tank", 5500, 12500)
	var moves: Array[Command] = _moves(_think(world, Rig.dummy(1)))
	assert_int(moves.size()).is_equal(2)
	assert_int(moves[0].unit_ids.size()).is_equal(Command.MAX_UNITS)
	assert_int(moves[0].unit_ids.size() + moves[1].unit_ids.size()).is_equal(302)
	Rig.step(world, loop, moves)
	assert_int(world.dropped_commands).is_equal(0)


## The shipped start, with every player's fog stamped once (the rows given after it are seen where
## the player's cells are).
func _start() -> World:
	var world: World = Rig.start()
	Rig.settle(world, Rig.loop_of(world))
	return world


## The shipped def with the defend radius `radius`.
func _def(radius: int) -> AiDef:
	var def: AiDef = Rig.dummy_def().duplicate() as AiDef
	def.defend_radius_tiles = radius
	return def


## One think of `ai` on a fresh view of its player.
func _think(world: World, ai: AiController) -> Array[Command]:
	var sent: Array[Command] = []
	ai.think(PlayerView.of(world, ai.player_id), sent)
	return sent


## The ATTACK_MOVE commands of `sent`.
func _moves(sent: Array[Command]) -> Array[Command]:
	var found: Array[Command] = []
	for command: Command in sent:
		if command.type == Command.Type.ATTACK_MOVE:
			found.append(command)
	return found


## The target points (milli-tiles) of the ATTACK_MOVE commands of `sent`.
func _targets(sent: Array[Command]) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for command: Command in _moves(sent):
		found.append(Vector2i(command.target_x, command.target_y))
	return found
