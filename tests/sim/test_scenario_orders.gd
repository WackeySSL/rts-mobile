extends GdUnitTestSuite
## ScenarioOrders (plan P35b, ADR 0007 section 9): the orders of a scenario as ordinary Commands.
## Literal numbers: the target is the centre of its tile (x * 1000 + 500), the ids are the ids of
## the spawn order, and a scenario is built in code so no data file can agree with a wrong rule.

const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const Samples: GDScript = preload("res://tests/sim/support/command_samples.gd")


## One order at tick 0 gives one Command with every row of its player that can move, in ascending
## id. The towers (speed 0), the neutral walker and the other player's walkers are not in it, and
## the ids that sit between two blocks of the player are.
func test_an_order_at_tick_0_gives_one_command_with_the_movable_rows_of_its_player() -> void:
	var world: World = World.from_scenario(_scenario())
	var out: Array[Command] = []
	_orders().collect(world, out)
	assert_int(out.size()).is_equal(2)
	# The scenario lists player 2's order first, and the commands come out in that order.
	assert_array(_fields(out[0])).is_equal([2, Command.Type.MOVE, 500, 19500, [4, 5], -1, 0, 0, []])
	assert_array(_fields(out[1])).is_equal(
		[1, Command.Type.ATTACK_MOVE, 7500, 3500, [1, 2, 3, 9, 10], -1, 0, 0, []]
	)


func test_nothing_comes_out_at_other_ticks_and_the_later_order_at_its_own() -> void:
	var world: World = World.from_scenario(_scenario())
	var orders: ScenarioOrders = _orders()
	for tick: int in [1, 2, 4, 6, 7, 100, -1]:
		world.tick = tick
		var out: Array[Command] = []
		orders.collect(world, out)
		assert_int(out.size()).override_failure_message("tick %d" % tick).is_equal(0)
	world.tick = 5
	var later: Array[Command] = []
	orders.collect(world, later)
	assert_int(later.size()).is_equal(1)
	assert_array(_fields(later[0])).is_equal(
		[1, Command.Type.STOP, 12500, 9500, [1, 2, 3, 9, 10], -1, 0, 0, []]
	)
	# Tick 0 again gives the first two, so collecting is a pure read of the order table.
	world.tick = 0
	var again: Array[Command] = []
	orders.collect(world, again)
	assert_int(again.size()).is_equal(2)


## The data: each side of the arena attack-moves to the centre of the other side's tile, with all
## 75 of its rows (30 tanks, 27 rifle squads and 18 rocket squads), ids 1-75 and 76-150.
func test_the_arena_orders_name_all_75_rows_of_each_side_and_the_tile_centre() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = World.from_scenario(scenario)
	var out: Array[Command] = []
	ScenarioOrders.create(scenario).collect(world, out)
	assert_int(out.size()).is_equal(2)
	var first: Array[int] = []
	var second: Array[int] = []
	for id: int in 75:
		first.append(id + 1)
		second.append(id + 76)
	assert_array(_fields(out[0])).is_equal(
		[1, Command.Type.ATTACK_MOVE, 39500, 32500, first, -1, 0, 0, []]
	)
	assert_array(_fields(out[1])).is_equal(
		[2, Command.Type.ATTACK_MOVE, 24500, 32500, second, -1, 0, 0, []]
	)


## The rows are read when the order fires: a dead unit is gone from the ids (ids are never reused),
## and an order for a player with nothing that can move still gives its Command, with no ids.
func test_a_dead_row_is_not_named_and_a_player_without_movers_gets_an_empty_command() -> void:
	var scenario: ScenarioDef = _scenario()
	scenario.orders.append(_order(5, 3, Command.Type.MOVE, Vector2i(1, 1)))
	scenario.orders.append(_order(5, 1, Command.Type.MOVE, Vector2i(2, 2)))
	var world: World = World.from_scenario(scenario)
	world.hp[1] = 0
	world.hp[8] = 0
	world.remove_dead()
	world.tick = 5
	var out: Array[Command] = []
	ScenarioOrders.create(scenario).collect(world, out)
	assert_int(out.size()).is_equal(3)
	assert_array(_fields(out[0])).is_equal(
		[1, Command.Type.STOP, 12500, 9500, [1, 3, 10], -1, 0, 0, []]
	)
	assert_array(_fields(out[1])).is_equal([3, Command.Type.MOVE, 1500, 1500, [], -1, 0, 0, []])
	assert_array(_fields(out[2])).is_equal(
		[1, Command.Type.MOVE, 2500, 2500, [1, 3, 10], -1, 0, 0, []]
	)


## create copies the orders into ints: the Resources can change afterwards without reaching it.
func test_create_copies_the_orders_once() -> void:
	var scenario: ScenarioDef = _scenario()
	var orders: ScenarioOrders = ScenarioOrders.create(scenario)
	assert_int(orders.order_count()).is_equal(3)
	for order: OrderDef in scenario.orders:
		order.tick = 3
		order.player = 2
		order.type = Command.Type.ATTACK
		order.target_tile = Vector2i(19, 19)
	scenario.orders.clear()
	var world: World = World.from_scenario(_scenario())
	var out: Array[Command] = []
	orders.collect(world, out)
	assert_int(out.size()).is_equal(2)
	assert_array(_fields(out[0]).slice(0, 4)).is_equal([2, Command.Type.MOVE, 500, 19500])
	assert_array(_fields(out[1]).slice(0, 4)).is_equal([1, Command.Type.ATTACK_MOVE, 7500, 3500])
	world.tick = 3
	var changed: Array[Command] = []
	orders.collect(world, changed)
	assert_int(changed.size()).is_equal(0)


func test_no_scenario_and_a_null_order_give_no_orders() -> void:
	var world: World = World.from_scenario(_scenario())
	var out: Array[Command] = []
	var none: ScenarioOrders = ScenarioOrders.create(null)
	none.collect(world, out)
	assert_array([none.order_count(), out.size()]).is_equal([0, 0])
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.orders.append(null)
	scenario.orders.append(_order(0, 1, Command.Type.MOVE, Vector2i(3, 4)))
	var orders: ScenarioOrders = ScenarioOrders.create(scenario)
	assert_int(orders.order_count()).is_equal(1)
	orders.collect(world, out)
	assert_int(out.size()).is_equal(1)
	assert_array(_fields(out[0]).slice(0, 4)).is_equal([1, Command.Type.MOVE, 3500, 4500])


## collect appends to what `out` holds and writes nothing to the world: the hash is the same.
func test_collect_appends_and_leaves_the_world_alone() -> void:
	var world: World = World.from_scenario(_scenario())
	var before: int = world.state_hash()
	var out: Array[Command] = [Samples.full(Command.Type.MOVE, 9, 9)]
	_orders().collect(world, out)
	assert_int(out.size()).is_equal(3)
	assert_array(Samples.fields(out[0])).is_equal(
		Samples.fields(Samples.full(Command.Type.MOVE, 9, 9))
	)
	assert_int(world.state_hash()).is_equal(before)


func _orders() -> ScenarioOrders:
	return ScenarioOrders.create(_scenario())


## Ids by spawn order: player 1 walkers 1-3, player 2 walkers 4-5, player 1 towers 6-7 (speed 0),
## a neutral walker 8, player 1 walkers 9-10. Orders: player 2 then player 1 at tick 0, and
## player 1 at tick 5.
func _scenario() -> ScenarioDef:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(20, 20)
	scenario.player_count = 3
	var walker: UnitDef = _unit(&"walker", 100)
	var tower: UnitDef = _unit(&"tower", 0)
	scenario.spawns.append(_block(1, walker, 3, Vector2i(1, 1)))
	scenario.spawns.append(_block(2, walker, 2, Vector2i(1, 5)))
	scenario.spawns.append(_block(1, tower, 2, Vector2i(1, 8)))
	scenario.spawns.append(_block(0, walker, 1, Vector2i(1, 10)))
	scenario.spawns.append(_block(1, walker, 2, Vector2i(1, 12)))
	scenario.orders.append(_order(0, 2, Command.Type.MOVE, Vector2i(0, 19)))
	scenario.orders.append(_order(0, 1, Command.Type.ATTACK_MOVE, Vector2i(7, 3)))
	scenario.orders.append(_order(5, 1, Command.Type.STOP, Vector2i(12, 9)))
	return scenario


func _unit(type_id: StringName, speed: int) -> UnitDef:
	var unit: UnitDef = UnitDef.new()
	unit.type_id = type_id
	unit.speed = speed
	return unit


func _block(owner: int, unit: UnitDef, count: int, origin: Vector2i) -> SpawnDef:
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = owner
	spawn.unit = unit
	spawn.count = count
	spawn.origin_tile = origin
	spawn.columns = count
	spawn.spacing = 1000
	return spawn


func _order(tick: int, player: int, type: int, tile: Vector2i) -> OrderDef:
	var order: OrderDef = OrderDef.new()
	order.tick = tick
	order.player = player
	order.type = type
	order.target_tile = tile
	return order


## player, type, target x and y, the ids, then tick, sequence, target_id and the payload.
func _fields(command: Command) -> Array:
	var all: Array = [command.player_id, command.type, command.target_x, command.target_y]
	all.append(Array(command.unit_ids))
	all.append_array([command.tick, command.sequence, command.target_id])
	all.append(Array(command.payload))
	return all
