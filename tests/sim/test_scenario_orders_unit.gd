extends GdUnitTestSuite
## QUEUE and SUPERWEAPON orders of a scenario (plan row P80, ADR 0021 section 2, ADR 0023 section
## 14): `OrderDef.unit` names the type a QUEUE order queues, or the strike building type whose
## first row of the player a SUPERWEAPON order fires. ScenarioOrders keeps the type id, not the def,
## and finds the type index and the building id in the World when the order fires. Part 2 of the
## ScenarioOrders tests; part 1 (the unit-group orders) is test_scenario_orders. The worlds are the
## strike rig's (a Deep Bore with a charge of 40 ticks, ids 1-5) and the production base (a barracks
## each); literal numbers are the ids of those rigs and the centre of a tile (x * 1000 + 500).

const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const Production: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")


func test_a_queue_order_is_the_queue_command_of_the_worlds_index_of_its_unit() -> void:
	var world: World = Production.base()
	var rifle: int = Worlds.type_of(world, "rifle_squad")
	var tank: int = Worlds.type_of(world, "light_tank")
	var scenario: ScenarioDef = _scenario(
		[
			_order(0, 1, Command.Type.QUEUE, "rifle_squad", Vector2i(7, 7)),
			_order(3, 2, Command.Type.QUEUE, "light_tank", Vector2i.ZERO),
		]
	)
	var orders: ScenarioOrders = ScenarioOrders.create(scenario)
	assert_int(orders.order_count()).is_equal(2)
	var out: Array[Command] = []
	orders.collect(world, out)
	assert_int(out.size()).is_equal(1)
	# No unit rows and no target (the tile of the order is not read), the item in the payload.
	assert_array(_fields(out[0])).is_equal([1, Command.Type.QUEUE, 0, 0, [], -1, 0, 0, [rifle]])
	world.tick = 3
	var later: Array[Command] = []
	orders.collect(world, later)
	assert_array(_fields(later[0])).is_equal([2, Command.Type.QUEUE, 0, 0, [], -1, 0, 0, [tank]])


## The sim applies what the order made: the cost leaves the credits and the item joins the queue of
## its tab. An order for a type that the World does not know gives the index -1, which Sim.step
## drops and counts like any invalid QUEUE.
func test_the_sim_pays_for_a_queue_order_and_drops_one_for_a_type_the_world_lacks() -> void:
	var world: World = Production.base()
	var rifle: int = Worlds.type_of(world, "rifle_squad")
	var credits: int = world.credits[1]
	var scenario: ScenarioDef = _scenario(
		[
			_order(0, 1, Command.Type.QUEUE, "rifle_squad", Vector2i.ZERO),
			_order(0, 1, Command.Type.QUEUE, "ghost", Vector2i.ZERO),
			_order(0, 1, Command.Type.QUEUE, "", Vector2i.ZERO),
		]
	)
	var out: Array[Command] = []
	ScenarioOrders.create(scenario).collect(world, out)
	assert_array(out[1].payload).is_equal([-1])
	assert_array(out[2].payload).is_equal([-1])
	Production.step(world, out)
	assert_int(world.credits[1]).is_equal(credits - world.type_cost[rifle])
	assert_array(Production.items(world, 1, World.Tab.INFANTRY)).is_equal([rifle])
	assert_int(world.dropped_commands).is_equal(2)


func test_a_superweapon_order_fires_the_first_building_of_its_type_that_the_player_owns() -> void:
	var world: World = Strikes.world()
	var scenario: ScenarioDef = _scenario(
		[
			_order(5, 1, Command.Type.SUPERWEAPON, "bore", Vector2i(15, 10)),
			_order(5, 1, Command.Type.SUPERWEAPON, "array", Vector2i(2, 3)),
			_order(5, 2, Command.Type.SUPERWEAPON, "bore", Vector2i(15, 10)),
			_order(5, 1, Command.Type.SUPERWEAPON, "ghost", Vector2i(15, 10)),
			_order(5, 1, Command.Type.SUPERWEAPON, "", Vector2i(15, 10)),
		]
	)
	world.tick = 5
	var out: Array[Command] = []
	ScenarioOrders.create(scenario).collect(world, out)
	assert_int(out.size()).is_equal(5)
	# Two Deep Bores are the player's (ids 1 and 2): the lower id, at the centre of the tile.
	assert_array(_fields(out[0])).is_equal(
		[1, Command.Type.SUPERWEAPON, 15500, 10500, [], -1, 0, Strikes.BORE_A, []]
	)
	assert_array(_fields(out[1])).is_equal(
		[1, Command.Type.SUPERWEAPON, 2500, 3500, [], -1, 0, Strikes.ARRAY, []]
	)
	# Player 2 owns no Deep Bore, and a type the World lacks and no unit name no building: id 0,
	# which the sim drops.
	for index: int in [2, 3, 4]:
		assert_int(out[index].target_id).override_failure_message(str(index)).is_equal(0)


## A Deep Bore placed at tick 0 charges for its `charge_ticks`: an order at tick 39 is dropped and
## counted, one at tick 40 fires (the stamp reaches `ready_tick`) and writes the pending rupture.
func test_the_order_is_accepted_on_the_tick_the_charge_ends_and_not_one_before() -> void:
	for tick: int in [39, 40]:
		var world: World = Strikes.world()
		var charge: int = Strikes.charge_of(world, "bore")
		var delay: int = Strikes.delay_of(world, "bore")
		assert_int(charge).is_equal(40)
		var scenario: ScenarioDef = _scenario(
			[_order(tick, 1, Command.Type.SUPERWEAPON, "bore", Vector2i(15, 10))]
		)
		var loop: MatchLoop = MatchLoop.create(scenario, "", 1, world)
		var none: Array[Command] = []
		for _step: int in tick + 1:
			loop.step(world, none)
		var fired: bool = tick >= charge
		assert_int(world.dropped_commands).override_failure_message(str(tick)).is_equal(
			0 if fired else 1
		)
		assert_int(world.strike_tick[1]).override_failure_message(str(tick)).is_equal(
			tick + 1 + delay if fired else 0
		)


## create copies the type id: a later change of the Resource does not reach the order, and an order
## of another kind ignores the unit it carries.
func test_create_copies_the_unit_and_a_unit_group_order_ignores_it() -> void:
	var world: World = Production.base()
	var rifle: int = Worlds.type_of(world, "rifle_squad")
	var scenario: ScenarioDef = _scenario(
		[
			_order(0, 1, Command.Type.QUEUE, "rifle_squad", Vector2i.ZERO),
			_order(0, 1, Command.Type.ATTACK_MOVE, "light_tank", Vector2i(4, 5)),
		]
	)
	var orders: ScenarioOrders = ScenarioOrders.create(scenario)
	scenario.orders[0].unit = _unit(&"light_tank")
	var out: Array[Command] = []
	orders.collect(world, out)
	assert_array(out[0].payload).is_equal([rifle])
	# Player 1 owns no mobile row in this base, so the group order has no ids and its tile centre.
	assert_array(_fields(out[1]).slice(0, 5)).is_equal(
		[1, Command.Type.ATTACK_MOVE, 4500, 5500, []]
	)
	assert_array(out[1].payload).is_empty()


func _scenario(orders: Array[OrderDef]) -> ScenarioDef:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.orders = orders
	return scenario


func _order(tick: int, player: int, type: int, unit: String, tile: Vector2i) -> OrderDef:
	var order: OrderDef = OrderDef.new()
	order.tick = tick
	order.player = player
	order.type = type
	order.target_tile = tile
	if not unit.is_empty():
		order.unit = _unit(StringName(unit))
	return order


func _unit(type_id: StringName) -> UnitDef:
	var unit: UnitDef = UnitDef.new()
	unit.type_id = type_id
	return unit


## player, type, target x and y, the ids, then tick, sequence, target_id and the payload.
func _fields(command: Command) -> Array:
	var all: Array = [command.player_id, command.type, command.target_x, command.target_y]
	all.append(Array(command.unit_ids))
	all.append_array([command.tick, command.sequence, command.target_id])
	all.append(Array(command.payload))
	return all
