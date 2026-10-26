extends RefCounted
## Worlds and Commands for the PLACE suites (plan row P73b, ADR 0018 sections 3 and 5). Not a test
## suite. Built on `production_worlds.gd`'s base world (24 x 16 open tiles, the shipped rules, two
## players, every cell explored): `world()` adds player 1's headquarters (3x3 at tile (2, 5), tiles
## x 2..4 and y 5..7), so the STRUCTURES tab has a producer. A 2x2 power plant fits at tile (6, 5)
## and a 3x3 refinery too (x 6..8, y 5..7, dock tile (7, 8)), both within reach of the headquarters
## and clear of every other building and exit. Expected costs and ticks are the World's tables'.

const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
## The tile where `place()` puts the plant and the refinery.
const SPOT: Vector2i = Vector2i(6, 5)


## The base world with player 1's headquarters; `rock` is a list of Vector2i tiles of rock.
static func world(rock: Array = []) -> World:
	var made: World = Rig.base(rock)
	Rig.add_headquarters(made)
	return made


## A PLACE of `player` at the point inside tile (`col`, `line`) that is off the tile's corner, so
## that the rule "the origin is the tile that holds the point" is what the case exercises.
static func place(col: int, line: int, player: int = 1) -> Command:
	return Command.place(
		player, col * World.MILLI_PER_TILE + 700, line * World.MILLI_PER_TILE + 300
	)


## QUEUEs `id` for player 1 and runs to the step that makes it ready: the head of the STRUCTURES
## queue is at its goal when this returns, and no PLACE has been given.
static func ready(world: World, id: String) -> void:
	Rig.step(world, [Rig.queue(world, 1, id)])
	Rig.run(world, build_ticks(world, id) - 1)


## `Worlds.type_of`, `type_build_ticks` and `type_cost` of the type `id`.
static func build_ticks(world: World, id: String) -> int:
	return world.type_build_ticks[Worlds.type_of(world, id)]


static func cost(world: World, id: String) -> int:
	return world.type_cost[Worlds.type_of(world, id)]


## The `Placement.Reason` that player 1 gets for the type `id` at tile (`col`, `line`) now.
static func reason(world: World, id: String, col: int, line: int) -> int:
	var input: PlacementInput = PlacementInput.of_world(world)
	return Placement.reason(input, 1, Worlds.type_of(world, id), col, line)


## The queue index of player 1's STRUCTURES queue.
static func queue() -> int:
	return Rig.queue_of(1, World.Tab.STRUCTURES)
