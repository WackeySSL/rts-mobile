extends GdUnitTestSuite
## The power totals (plan row P74, ADR 0018 section 4, ADR 0017 sections 5 and 7, ADR 0016):
## `power_made` and `power_used` per player are summed over the building rows by `Power.run` in
## ECONOMY, only when `rows_version` has moved since the totals were last built, whoever rebuilt the
## derived lists in between; they are in no hash section, and a rebuild from the rows restores them
## at every checkpoint of a match with buildings. `Power.is_low` is `power_used > power_made`.
## The expected numbers come from the World's `type_power` table, so a retuned data file does not
## break a case; the shipped signs are pinned once.

const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const INFANTRY: int = World.Tab.INFANTRY
## Every shipped type with a power value, as one typed literal (`Rig.IDS` has no turret, and a type
## enters the table only when it is listed or required by a listed one).
const POWER_TYPES: Array[String] = [
	"power_plant",
	"headquarters",
	"barracks",
	"vehicle_factory",
	"refinery",
	"defence_turret",
]


## `Rig.base()`: player 1 owns a power plant, a barracks, a refinery and a vehicle factory, player 2
## a barracks (no plant).
func _power(world: World, id: String) -> int:
	var type: int = Worlds.type_of(world, id)
	# A missing type is -1, which a packed array reads as its last entry: it must fail here.
	assert_int(type).override_failure_message("no type %s in the table" % id).is_greater_equal(0)
	return world.type_power[type]


func _step(world: World, commands: Array = []) -> void:
	Rig.step(world, commands)


## What a scan of the rows gives for `player`: [made, used], from the type table alone.
func _scan(world: World, player: int) -> Array[int]:
	var made: int = 0
	var used: int = 0
	for row: int in world.unit_count():
		var type: int = world.type_index[row]
		if world.owner[row] == player and world.type_foot_w[type] > 0:
			if world.type_power[type] > 0:
				made += world.type_power[type]
			else:
				used -= world.type_power[type]
	return [made, used]


func _totals(world: World, player: int) -> Array[int]:
	return [world.power_made[player], world.power_used[player]]


func test_the_shipped_signs_a_plant_and_the_headquarters_make_and_the_rest_use() -> void:
	var world: World = Worlds.open(Rig.COLS, Rig.ROWS, POWER_TYPES)
	assert_int(_power(world, "power_plant")).is_greater(0)
	assert_int(_power(world, "headquarters")).is_greater(0)
	for id: String in ["barracks", "refinery", "vehicle_factory", "defence_turret"]:
		assert_int(_power(world, id)).override_failure_message(id).is_less(0)


func test_the_totals_sum_the_positive_and_the_negative_power_of_each_players_buildings() -> void:
	var world: World = Rig.base()
	assert_array(_totals(world, 1)).is_equal([0, 0])  # Derived: nothing before ECONOMY.
	_step(world)
	var used: int = -(
		_power(world, "barracks") + _power(world, "refinery") + _power(world, "vehicle_factory")
	)
	assert_array(_totals(world, 1)).is_equal([_power(world, "power_plant"), used])
	assert_array(_totals(world, 2)).is_equal([0, -_power(world, "barracks")])
	assert_array(_totals(world, 0)).is_equal([0, 0])
	for player: int in [1, 2]:
		assert_array(_totals(world, player)).is_equal(_scan(world, player))


func test_low_power_is_used_above_made_and_equal_is_not_low() -> void:
	var world: World = Rig.base()
	_step(world)
	assert_bool(Power.is_low(world, 1)).is_false()  # Less used than made in the shipped data.
	assert_bool(Power.is_low(world, 2)).is_true()  # A barracks and no plant.
	# Player 2 with a plant and a barracks that uses exactly what the plant makes.
	var tied: World = Rig.base()
	Rig.add_plant(tied, 2, 2, 12)
	var plant: int = Worlds.type_of(tied, "power_plant")
	var barracks: int = Worlds.type_of(tied, "barracks")
	tied.type_power[barracks] = -tied.type_power[plant]
	_step(tied)
	assert_array(_totals(tied, 2)).is_equal([tied.type_power[plant], tied.type_power[plant]])
	assert_bool(Power.is_low(tied, 2)).is_false()
	tied.type_power[barracks] -= 1  # One more used than made.
	tied._power_version = -1  # The table moved, not the rows: ask for the rebuild.
	_step(tied)
	assert_bool(Power.is_low(tied, 2)).is_true()


func test_is_low_is_false_for_the_neutral_player_and_for_players_past_the_arrays() -> void:
	var world: World = Rig.base()
	_step(world)
	assert_bool(Power.is_low(world, 0)).is_false()
	assert_bool(Power.is_low(world, -1)).is_false()
	assert_bool(Power.is_low(world, world.power_made.size())).is_false()
	assert_bool(Power.is_low(world, 99)).is_false()


func test_a_building_added_between_steps_counts_in_the_next_economy_and_not_before() -> void:
	var world: World = Rig.base()
	_step(world)
	var before: Array[int] = _totals(world, 2)
	var plant: int = world.add_building(2, Worlds.type_of(world, "power_plant"), 2, 12)
	assert_array(_totals(world, 2)).is_equal(before)  # Derived: stale until the next ECONOMY.
	_step(world)
	assert_array(_totals(world, 2)).is_equal([_power(world, "power_plant"), before[1]])
	assert_bool(Power.is_low(world, 2)).is_false()
	assert_int(plant).is_greater(0)


func test_a_building_that_dies_leaves_the_totals_in_the_same_ticks_economy() -> void:
	var world: World = Rig.base()
	_step(world)
	world.hp[world.index_of(Rig.PLANT)] = 0
	_step(world)  # REMOVE takes the row, ECONOMY of the same step sums the rows that are left.
	assert_int(world.power_made[1]).is_equal(0)
	assert_array(_totals(world, 1)).is_equal(_scan(world, 1))
	assert_bool(Power.is_low(world, 1)).is_true()


func test_the_totals_are_rebuilt_only_when_the_rows_version_moved() -> void:
	var world: World = Rig.base()
	_step(world)
	var honest: Array[int] = _totals(world, 1)
	world.power_made[1] = 12345  # Corrupted by hand: a rebuild would put the honest sum back.
	_step(world)
	_step(world)
	assert_int(world.power_made[1]).is_equal(12345)
	world.add_unit(1, Worlds.type_of(world, "rifle_squad"), 15500, 9500)  # A row joins.
	_step(world)
	assert_array(_totals(world, 1)).is_equal(honest)


func test_a_rebuild_of_the_row_lists_by_someone_else_does_not_leave_the_totals_stale() -> void:
	var world: World = Rig.base()
	_step(world)
	var plant: int = _power(world, "power_plant")
	world.add_building(1, Worlds.type_of(world, "power_plant"), 20, 6)
	# Production.producer_row asks Buildings.rebuild_lists first, as a QUEUE or a PRODUCTION step
	# does: the lists are now current, and a rebuild_lists inside Power.run would say "nothing".
	assert_int(Production.producer_row(world, 1, INFANTRY)).is_greater_equal(0)
	assert_bool(Buildings.rebuild_lists(world)).is_false()
	assert_int(world.power_made[1]).is_equal(plant)
	_step(world)
	assert_int(world.power_made[1]).is_equal(2 * plant)


func test_a_queue_in_commands_does_not_leave_the_totals_stale_either() -> void:
	var world: World = Rig.base()
	_step(world)
	var plant: int = _power(world, "power_plant")
	world.add_building(1, Worlds.type_of(world, "power_plant"), 20, 6)
	_step(world, [Rig.queue(world, 1, "rifle_squad")])  # apply_queue runs producer_row in COMMANDS.
	assert_int(world.power_made[1]).is_equal(2 * plant)


func test_neutral_buildings_and_players_past_the_arrays_get_no_entry() -> void:
	var world: World = Rig.base()
	_step(world)
	var before: Array = [_totals(world, 1), _totals(world, 2)]
	world.add_building(0, Worlds.type_of(world, "power_plant"), 2, 8)  # A neutral plant.
	world.player_count = 3  # Raised after prepare(), as a hand-built World may: its arrays stay at 2.
	world.add_building(3, Worlds.type_of(world, "power_plant"), 12, 8)
	_step(world)
	assert_array([_totals(world, 1), _totals(world, 2)]).is_equal(before)
	assert_array(_totals(world, 0)).is_equal([0, 0])
	assert_int(world.power_made.size()).is_equal(3)  # Nothing was resized to fit the late player.
	assert_bool(Power.is_low(world, 3)).is_false()


func test_run_on_a_world_that_is_not_prepared_writes_nothing_and_builds_later() -> void:
	var world: World = World.new()
	Power.run(world)
	assert_int(world._power_version).is_equal(-1)  # No stamp: the arrays are not sized yet.
	assert_array(world.power_made).is_empty()
	assert_bool(Power.is_low(world, 1)).is_false()
	var made: World = Rig.base()
	made._power_version = -1
	Power.run(made)  # Prepared, so it builds, without a step.
	assert_array(_totals(made, 1)).is_equal(_scan(made, 1))


func test_the_totals_are_in_no_hash_section_and_a_rebuild_from_the_rows_restores_them() -> void:
	var world: World = Rig.base()
	var twin: World = Rig.base()
	for _tick: int in 20:
		_step(world)
		_step(twin)
	assert_int(twin.state_hash()).is_equal(world.state_hash())
	twin.power_made.fill(777)
	twin.power_used.fill(555)
	assert_int(twin.state_hash()).is_equal(world.state_hash())  # Derived: no section reads them.
	assert_array(twin.hash_parts()).is_equal(world.hash_parts())
	twin._power_version = -1
	Power.run(twin)
	assert_array(twin.power_made).is_equal(world.power_made)
	assert_array(twin.power_used).is_equal(world.power_used)
	for name: StringName in [&"power_made", &"power_used"]:
		assert_bool(World.DERIVED_ARRAYS.has(name)).is_true()
		assert_bool(World.ROW_ARRAYS.has(name)).is_false()
		assert_bool(World.PLAYER_ARRAYS.has(name)).is_false()
		assert_bool(World.hash_section_names().has(String(name))).is_false()
	assert_bool(World.UNHASHED_SCALARS.has(&"_power_version")).is_true()


## One match of two bases with buildings that are placed and destroyed while the armies fight: a
## second turret for player 1 at tick 60, its plant dying at tick 150 (low power) and a new one at
## tick 300 (enough again), a plant of player 2 dying at tick 210. At every checkpoint the totals
## are compared with a scan of the rows and with a rebuild from the rows (wiped, stamp reset, run
## again), and the state hash is the same before and after the rebuild.
func test_every_checkpoint_of_a_match_with_buildings_equals_a_rebuild_from_the_rows() -> void:
	var world: World = Worlds.fight()
	var loop: MatchLoop = MatchLoop.create(null, "", 0, world)
	var seen: Dictionary[String, int] = {"checkpoints": 0, "low": 0, "changes": 0}
	var last: Array[int] = [-1, -1]
	for tick: int in 450:
		var orders: Array[Command] = []
		if tick == 0:
			orders.append(Command.attack_move(1, _army(world, 1), 22500, 7500))
			orders.append(Command.attack_move(2, _army(world, 2), 5500, 7500))
		if tick == 60:
			world.add_building(1, Worlds.type_of(world, "defence_turret"), 6, 12)
		if tick == 150:
			_kill(world, 2)  # Player 1's plant: its two turrets and Headquarters now use more.
		if tick == 210:
			_kill(world, 6)  # Player 2's plant.
		if tick == 300:
			world.add_building(1, Worlds.type_of(world, "power_plant"), 10, 12)
		loop.step(world, orders)
		if world.tick % Replay.CHECKPOINT_PERIOD != 0:
			continue
		seen["checkpoints"] += 1
		var hash_before: int = world.state_hash()
		for player: int in [1, 2]:
			var held: Array[int] = _totals(world, player)
			(
				assert_array(held)
				. override_failure_message(
					"tick %d, player %d against a scan" % [world.tick, player]
				)
				. is_equal(_scan(world, player))
			)
			if player == 1 and held != last:
				seen["changes"] += 1
				last = held
			if Power.is_low(world, player):
				seen["low"] += 1
		var wiped: Array[Array] = [_totals(world, 1), _totals(world, 2)]
		world.power_made.fill(-1)
		world.power_used.fill(-1)
		world._power_version = -1
		Power.run(world)
		(
			assert_array([_totals(world, 1), _totals(world, 2)])
			. override_failure_message("tick %d, a rebuild from the rows" % world.tick)
			. is_equal(wiped)
		)
		assert_int(world.state_hash()).is_equal(hash_before)
	assert_int(seen["checkpoints"]).is_equal(30)
	assert_int(seen["changes"]).is_greater_equal(3)  # Made and used moved at least thrice.
	assert_int(seen["low"]).is_greater(0)  # The run met low power, so it checked that side too.


## The mobile ids of `player`, ascending.
func _army(world: World, player: int) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_speed[world.type_index[row]] > 0:
			ids.append(world.unit_id[row])
	return ids


## Sets the hit points of the row with `id` to 0, when it is still there.
func _kill(world: World, id: int) -> void:
	var row: int = world.index_of(id)
	if row >= 0:
		world.hp[row] = 0
