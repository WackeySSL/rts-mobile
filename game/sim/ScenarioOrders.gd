class_name ScenarioOrders
extends RefCounted
## The orders a scenario gives itself (ScenarioDef.orders), turned into ordinary Commands (ADR 0007
## section 9): MatchLoop stamps and records them like any order, so a replay and the state hash
## see them the same way. The orders are copied into ints once, so nothing here keeps a def (ADR
## 0012 section 2) and a later change of the Resource does not reach a running match.

## One entry per order, in the order of ScenarioDef.orders. Int64, so no value is truncated.
var _ticks: PackedInt64Array = PackedInt64Array()
var _players: PackedInt64Array = PackedInt64Array()
var _types: PackedInt64Array = PackedInt64Array()
## The centre of the order's target tile, in milli-tiles.
var _target_x: PackedInt64Array = PackedInt64Array()
var _target_y: PackedInt64Array = PackedInt64Array()


## The orders of `scenario`, copied. A null scenario, and a null entry in its orders, give none.
static func create(scenario: ScenarioDef) -> ScenarioOrders:
	var orders: ScenarioOrders = ScenarioOrders.new()
	if scenario == null:
		return orders
	for order: OrderDef in scenario.orders:
		if order == null:
			continue
		orders._ticks.append(order.tick)
		orders._players.append(order.player)
		orders._types.append(order.type)
		orders._target_x.append(order.target_tile.x * World.MILLI_PER_TILE + World.TILE_CENTRE)
		orders._target_y.append(order.target_tile.y * World.MILLI_PER_TILE + World.TILE_CENTRE)
	return orders


## How many orders there are.
func order_count() -> int:
	return _ticks.size()


## Appends one Command to `out` for each order whose tick is `world.tick`, in the order of the
## scenario. It holds the ids of every row of the order's player whose type has a speed above 0, in
## ascending id (row) order, and the centre of the order's target tile as its target. An order
## whose player has no such row still gives a Command, with no ids, which Sim.step drops and
## counts. `tick` and `sequence` are left as Command.new() has them: MatchLoop stamps them. A
## player with more than Command.MAX_UNITS such rows (data keeps `max_rows` within it) gives a
## Command that Sim.step drops. Allocates only on a tick that has an order.
func collect(world: World, out: Array[Command]) -> void:
	var tick: int = world.tick
	var ticks: PackedInt64Array = _ticks
	for index: int in ticks.size():
		if ticks[index] == tick:
			out.append(_command_for(world, index))


## The Command of order `index` for the rows of `world` as they are now.
func _command_for(world: World, index: int) -> Command:
	world.prepare()
	var command: Command = Command.new()
	var player: int = _players[index]
	command.type = _types[index]
	command.player_id = player
	command.target_x = _target_x[index]
	command.target_y = _target_y[index]
	var ids: PackedInt32Array = world.unit_id
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var speeds: PackedInt32Array = world.type_speed
	var movers: PackedInt32Array = PackedInt32Array()
	for row: int in ids.size():
		if owners[row] == player and speeds[types[row]] > 0:
			movers.append(ids[row])
	command.unit_ids = movers
	return command
