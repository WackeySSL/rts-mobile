extends GdUnitTestSuite
## The last-seen records through `Sim.step` and the real fog (plan row P77, ADR 0017 section 5): the
## rules of test_last_seen.gd on worlds where units light and darken the cells themselves. One case
## follows a scouted Headquarters through the whole story (seen, out of sight, destroyed out of
## sight, seen gone) and reads it through PlayerView; the other plays Worlds.fight() (the base fight
## of the building lockstep) and checks every rule after every tick: who may change, what may be
## added, what may be dropped, what a seen building must have, the cap and the zeroed free places.
## FOG's two implementations give the memory the same inputs, and
## native/test_building_lockstep.gd compares the whole state of both, ghost arrays included, tick
## by tick on this same fight.

const Memory: GDScript = preload("res://tests/sim/support/memory_worlds.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const TargetingWorlds: GDScript = preload("res://tests/sim/support/targeting_worlds.gd")
const TICKS: int = 450
## The fight's orders, as test_building_lockstep.gd gives them: a power plant for player 1 and a
## turret for player 2 placed at PLACE_TICK, and two buildings that die at DESTROY_TICKS.
const PLACE_TICK: int = 100
const DESTROY_TICKS: Array[int] = [200, 260]
const DESTROYED_IDS: Array[int] = [5, 2]


## The mobile ids of `player`, ascending.
func _army(world: World, player: int) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_speed[world.type_index[row]] > 0:
			ids.append(world.unit_id[row])
	return ids


## The fight's commands of tick `tick`, and the buildings it places and kills.
func _orders(world: World, tick: int) -> Array[Command]:
	var orders: Array[Command] = []
	if tick == 0:
		orders.append(Command.attack_move(1, _army(world, 1), 22500, 7500))
		orders.append(Command.attack_move(2, _army(world, 2), 5500, 7500))
	if tick == PLACE_TICK:
		var plant: int = world.add_building(1, Worlds.type_of(world, "power_plant"), 10, 12)
		var turret: int = world.add_building(2, Worlds.type_of(world, "defence_turret"), 21, 3)
		world.hp[world.index_of(plant)] = 150
		world.hp[world.index_of(turret)] = 120
	for which: int in DESTROY_TICKS.size():
		var row: int = world.index_of(DESTROYED_IDS[which])
		if tick == DESTROY_TICKS[which] and row >= 0:
			world.hp[row] = 0
	return orders


## What a step that ran at `tick` may have done to the records of each player, as the first rule
## it broke, or "" when it kept them all. `before` holds each player's records from before the step
## (`Memory.records`); `tally` counts the records added and dropped, so that a run cannot pass by
## never meeting either.
func _broken_rule(
	world: World, tick: int, before: Dictionary, tally: Dictionary[String, int]
) -> String:
	for player: int in range(1, world.player_count + 1):
		var now: Array[Array] = Memory.records(world, player)
		var problem: String = _shape_problem(world, player, now)
		if problem == "" and (tick - player + 1) % world.fog_period_ticks != 0:
			problem = "" if now == before[player] else "records changed off the player's fog turn"
		elif problem == "":
			problem = _turn_problem(world, player, before[player], now, tally)
		if problem != "":
			return "tick %d player %d: %s" % [tick, player, problem]
	return ""


## The block's size and its free places: at most ghost_cap records, and every place after the last
## one holds zeros.
func _shape_problem(world: World, player: int, now: Array[Array]) -> String:
	if now.size() > world.ghost_cap:
		return "more records than ghost_cap"
	var first: int = player * world.ghost_cap
	for entry: int in range(first + now.size(), first + world.ghost_cap):
		var held: int = world.ghost_id[entry] | world.ghost_type[entry]
		if (held | world.ghost_owner[entry] | world.ghost_cell[entry]) != 0:
			return "a free place is not zero"
	return ""


## What a fog turn of `player` must have done to its records (see LastSeen's header): each record
## is an enemy building's, once, and agrees with the building if it stands and with the fog if it is
## gone; each one added is a building seen now; each one dropped is gone from a cell seen now; and
## no enemy building seen now lacks one, unless the block is full.
func _turn_problem(
	world: World, player: int, before: Array, now: Array[Array], tally: Dictionary[String, int]
) -> String:
	var block: int = (player - 1) * world.fog.cells
	var visible: PackedInt32Array = world.fog.visible
	var known: Dictionary[int, bool] = {}
	for record: Array in before:
		known[record[0]] = true
	var kept: Dictionary[int, bool] = {}
	for record: Array in now:
		var problem: String = _record_problem(world, player, record, kept.has(record[0]))
		if problem != "":
			return problem
		kept[record[0]] = true
		if not known.has(record[0]):
			tally["added"] += 1
			if visible[block + record[3]] <= 0 or world.index_of(record[0]) < 0:
				return "a record added for a building the player does not see"
	for record: Array in before:
		if not kept.has(record[0]):
			tally["dropped"] += 1
			if world.index_of(record[0]) >= 0 or visible[block + record[3]] <= 0:
				return "a record dropped though its building stands or its cell is dark"
	return _unrecorded_problem(world, player, kept) if now.size() < world.ghost_cap else ""


## What one record of `player` must be: an enemy building's, once (`twice` says it was already
## seen in this block), the building's own type, owner and cell while it stands, and on a cell the
## player does not see once it is gone.
func _record_problem(world: World, player: int, record: Array, twice: bool) -> String:
	var row: int = world.index_of(record[0])
	var seen: bool = world.fog.visible[(player - 1) * world.fog.cells + record[3]] > 0
	if twice:
		return "a building is recorded twice"
	if record[2] == player or record[2] < 1 or record[2] > world.player_count:
		return "a record of a building that is not an enemy's"
	if row < 0:
		return "a record of a gone building on a cell the player sees" if seen else ""
	var cell: int = world.cell_of(world.pos_x[row], world.pos_y[row])
	if world.type_index[row] != record[1] or world.owner[row] != record[2] or cell != record[3]:
		return "a record that is not the building's type, owner and cell"
	return ""


## The first enemy building that `player` sees now and has no record of (ids in `kept`), or "".
func _unrecorded_problem(world: World, player: int, kept: Dictionary[int, bool]) -> String:
	var block: int = (player - 1) * world.fog.cells
	for row: int in world.unit_count():
		var owner: int = world.owner[row]
		var cell: int = world.cell_of(world.pos_x[row], world.pos_y[row])
		var enemy_building: bool = (
			world.type_foot_w[world.type_index[row]] > 0 and owner != player and owner >= 1
		)
		if (
			enemy_building
			and world.fog.visible[block + cell] > 0
			and not kept.has(world.unit_id[row])
		):
			return "an enemy building the player sees has no record"
	return ""


func test_every_rule_holds_after_every_tick_of_a_base_fight() -> void:
	var world: World = Worlds.fight()
	var loop: MatchLoop = MatchLoop.create(null, "", 0, world)
	var tally: Dictionary[String, int] = {"added": 0, "dropped": 0}
	var most: int = 0
	for tick: int in TICKS:
		var before: Dictionary = {}
		for player: int in range(1, world.player_count + 1):
			before[player] = Memory.records(world, player)
		loop.step(world, _orders(world, tick))
		var broken: String = _broken_rule(world, tick, before, tally)
		assert_str(broken).is_empty()
		if broken != "":
			return
		most = maxi(most, maxi(world.ghost_count[1], world.ghost_count[2]))
	# What the run reached: both players remembered buildings, and a building that died in sight
	# was forgotten.
	assert_int(tally["added"]).is_greater_equal(3)
	assert_int(tally["dropped"]).is_greater_equal(1)
	assert_int(most).is_greater_equal(2)


func test_a_scouted_headquarters_is_remembered_after_it_dies_out_of_sight_until_seen_gone() -> void:
	var world: World = Memory.world()
	var hq: int = Memory.build(world, 2, "headquarters", 16, 6)
	var scout: int = world.add_unit(1, Worlds.type_of(world, "rifle_squad"), 11500, 7500)
	TargetingWorlds.stamp_fog(world)  # The scout sees 6 tiles: the Headquarters' tile, 6 east.
	var none: Array[Command] = []
	var period: int = world.fog_period_ticks
	# Player 1's first turn (tick 0): the Headquarters is seen and remembered.
	Sim.step(world, none)
	assert_array(Memory.ids(world, 1)).is_equal([hq])
	var view: PlayerView = PlayerView.of(world, 1)
	assert_int(view.row_of(hq)).is_not_equal(PlayerView.MISSING)
	assert_int(view.ghost_of(hq)).is_equal(0)
	# The scout goes west: the Headquarters leaves its sight, and the record stays.
	var row: int = world.index_of(scout)
	world.pos_x[row] = 1500
	world.pos_y[row] = 1500
	for _step: int in 2 * period:
		Sim.step(world, none)
	var hq_row: int = world.index_of(hq)
	var position: Vector2i = Vector2i(world.pos_x[hq_row], world.pos_y[hq_row])
	view = PlayerView.of(world, 1)
	assert_int(view.row_of(hq)).is_equal(PlayerView.MISSING)
	assert_int(view.ghost_of(hq)).is_equal(0)
	assert_vector(view.ghost_pos(0)).is_equal(position)
	# It dies out of sight: still remembered, however long the player waits.
	world.hp[hq_row] = 0
	for _step: int in 3 * period:
		Sim.step(world, none)
	assert_int(world.index_of(hq)).is_equal(-1)
	view = PlayerView.of(world, 1)
	assert_int(view.ghost_count).is_equal(1)
	assert_int(view.ghost_of(hq)).is_equal(0)
	assert_int(view.row_of(hq)).is_equal(PlayerView.MISSING)
	# The scout returns: on its player's next turn FOG lights the cell and MEMORY, which follows it
	# in the same step, sees the building gone and forgets it.
	row = world.index_of(scout)
	world.pos_x[row] = 11500
	world.pos_y[row] = 7500
	for _step: int in period:
		var tick: int = world.tick
		Sim.step(world, none)
		var turn: bool = tick % period == 0  # Player 1's turn: (tick - 1 + 1) % period == 0.
		assert_int(world.ghost_count[1]).override_failure_message("tick %d" % tick).is_equal(
			0 if turn else 1
		)
		if turn:
			break
	assert_int(PlayerView.of(world, 1).ghost_of(hq)).is_equal(PlayerView.MISSING)
