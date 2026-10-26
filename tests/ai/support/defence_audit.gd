extends RefCounted
## Audits of the orders of the dummy's defence (plan row P83b). Not a test suite. Each reads the
## World as it stands before the tick that applies the order, which is when the dummy thought.


## Whether the target of `command` is within `radius` tiles of the centre of a building of the
## command's player (the squared distance in milli-tiles, the edge included).
static func within(world: World, command: Command, radius: int) -> bool:
	for row: int in world.unit_count():
		if world.owner[row] != command.player_id or world.type_foot_w[world.type_index[row]] < 1:
			continue
		var dx: int = command.target_x - world.pos_x[row]
		var dy: int = command.target_y - world.pos_y[row]
		if dx * dx + dy * dy <= radius * radius * 1000000:
			return true
	return false


## Whether the target of `command` is the position of a row of `player`: an order at an enemy.
static func meets(world: World, command: Command, player: int) -> bool:
	for row: int in world.unit_count():
		if (
			world.owner[row] == player
			and world.pos_x[row] == command.target_x
			and world.pos_y[row] == command.target_y
		):
			return true
	return false
