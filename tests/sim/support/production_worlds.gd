extends RefCounted
## Worlds and steps for the production suites (plan row P73, ADR 0018 section 5). Not a test suite.
##
## `base()` is a 24 x 16 open map with the shipped rules, two players, the shipped units and
## buildings, revealed. Player 1 owns a power plant (id 1, 2x2 at tile (2, 1)), a barracks (id 2,
## 2x2 at (8, 1), exit tile (9, 3)), a refinery (id 3, 3x3 at (12, 1)) and a vehicle factory (id 4,
## 3x3 at (17, 1), exit tile (18, 4)); player 2 owns a barracks (id 5, 2x2 at (8, 12), exit tile
## (9, 14)). Both start with the 2,000 credits of the rules. No row of either player can see or hit
## the other's: the buildings are unarmed and the units spawn 8 tiles or more apart.

const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const IDS: Array[String] = [
	"rifle_squad",
	"rocket_squad",
	"light_tank",
	"heavy_tank",
	"harvester",
	"power_plant",
	"barracks",
	"vehicle_factory",
	"refinery",
]
const COLS: int = 24
const ROWS: int = 16
const PLANT: int = 1
const BARRACKS: int = 2
const REFINERY: int = 3
const FACTORY: int = 4
const ENEMY_BARRACKS: int = 5


## The base world; `rock` is a list of Vector2i tiles of rock.
static func base(rock: Array = []) -> World:
	var world: World = Worlds.world(GridWorld.grass(COLS, ROWS, rock), IDS)
	world.add_building(1, Worlds.type_of(world, "power_plant"), 2, 1)
	world.add_building(1, Worlds.type_of(world, "barracks"), 8, 1)
	world.add_building(1, Worlds.type_of(world, "refinery"), 12, 1)
	world.add_building(1, Worlds.type_of(world, "vehicle_factory"), 17, 1)
	world.add_building(2, Worlds.type_of(world, "barracks"), 8, 12)
	return world


## Gives player 1 a headquarters (3x3 at tile (2, 5), clear of every other building and of both
## exits) and returns its id. It is the one shipped building that produces the STRUCTURES tab, so a
## case that pins the unit-tab gate needs it: without one, `Production.producer_row` finds no
## producer for that tab and a refusal or a stalled queue would be the missing producer's.
static func add_headquarters(world: World) -> int:
	return world.add_building(1, Worlds.type_of(world, "headquarters"), 2, 5)


## One tick: `commands` (a plain Array: a caller reaches this through a preloaded script, so its
## literal is not typed) are stamped with the World's tick and `Sim.step` runs.
static func step(world: World, commands: Array = []) -> void:
	var stamped: Array[Command] = []
	stamped.assign(commands)
	for command: Command in stamped:
		command.tick = world.tick
	Sim.step(world, stamped)


## `ticks` ticks without commands.
static func run(world: World, ticks: int) -> void:
	for _tick: int in ticks:
		step(world)


## A QUEUE of the type `id` for `player`, with `sequence` to order it within a tick.
static func queue(world: World, player: int, id: String, sequence: int = 0) -> Command:
	var command: Command = Command.queue(player, Worlds.type_of(world, id))
	command.sequence = sequence
	return command


## The queue index of `player` and `tab` (the second index of the per-tab arrays).
static func queue_of(player: int, tab: int) -> int:
	return player * World.TABS + tab


## The type indexes in the queue of `player` and `tab`, head first.
static func items(world: World, player: int, tab: int) -> Array[int]:
	var queue_index: int = queue_of(player, tab)
	var found: Array[int] = []
	for slot: int in world.queue_count[queue_index]:
		found.append(world.queue_type[queue_index * world.queue_slots + slot])
	return found


## The rows of `player`'s units of the type `id`, ascending.
static func rows_of(world: World, player: int, id: String) -> Array[int]:
	var type: int = Worlds.type_of(world, id)
	var found: Array[int] = []
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_index[row] == type:
			found.append(row)
	return found
