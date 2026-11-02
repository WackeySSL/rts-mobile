extends RefCounted
## Worlds and Commands for the place-first construction suites (plan row P128, ADR 0026). Not a
## test suite. A 24 x 16 open map with the shipped rules, the shipped units and buildings, two
## players, every cell explored and visible (`Worlds.world`).
##
## | id | owner | what | origin tile |
## | 1 | 1 | headquarters 3x3 (the STRUCTURES producer; a fossil building) | (2, 5) |
## | 2 | 1 | power plant 2x2 | (2, 1) |
## | 3 | 1 | barracks 2x2 | (8, 1) |
## | 4 | 1 | refinery 3x3, dock tile (13, 4) | (12, 1) |
## | 5 | 2 | renew headquarters 3x3 (a producer of another faction) | (18, 11) |
##
## Player 1 makes 120 power and uses 50, so it is on low power only when a case lowers a table.
## Both start with the 2,000 credits of the rules. Player 1's spots: a 2x2 at `SPOT` (6, 5), a 3x3
## at `WIDE` (6, 9) and a 3x3 at `FAR` (12, 8), all within `build_reach_tiles` of an own building;
## player 2's 2x2 spot is `SPOT_2`. Every cost, build time and hit point a case needs is read from
## the World's tables (`done`, `cost`, `hit_points`), and a case that wants a short build time
## writes `type_build_ticks` through `fast`.

const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const IDS: Array[String] = [
	"rifle_squad",
	"harvester",
	"power_plant",
	"barracks",
	"refinery",
	"defence_turret",
	"fossil_radar",
	"fossil_strike",
	"renew_power",
]
const COLS: int = 24
const ROWS: int = 16
const HQ: int = 1
const PLANT: int = 2
const BARRACKS: int = 3
const REFINERY: int = 4
const HQ_2: int = 5
const SPOT: Vector2i = Vector2i(6, 5)
const WIDE: Vector2i = Vector2i(6, 9)
const FAR: Vector2i = Vector2i(12, 8)
const SPOT_2: Vector2i = Vector2i(14, 11)


## The world described above; `rock` is a list of Vector2i tiles of rock.
static func world(rock: Array = []) -> World:
	var made: World = Worlds.world(GridWorld.grass(COLS, ROWS, rock), IDS)
	made.add_building(1, type_of(made, "headquarters"), 2, 5)
	made.add_building(1, type_of(made, "power_plant"), 2, 1)
	made.add_building(1, type_of(made, "barracks"), 8, 1)
	made.add_building(1, type_of(made, "refinery"), 12, 1)
	made.add_building(2, type_of(made, "renew_hq"), 18, 11)
	return made


static func type_of(made: World, id: String) -> int:
	return Worlds.type_of(made, id)


## A PLACE of `player` for the type `id` at the point inside tile `at` that is off the tile's
## corner (the origin is the tile that holds the point).
static func place(made: World, id: String, at: Vector2i, player: int = 1) -> Command:
	var point: Vector2i = at * World.MILLI_PER_TILE + Vector2i(700, 300)
	return Command.place(player, point.x, point.y, type_of(made, id))


## One tick with `commands` (a plain Array) stamped with the World's tick.
static func step(made: World, commands: Array = []) -> void:
	Rig.step(made, commands)


static func run(made: World, ticks: int) -> void:
	Rig.run(made, ticks)


## `Production.apply_place` for a command stamped with the World's tick: the state a PLACE leaves
## before the same tick's PRODUCTION runs. True when it was applied.
static func apply(made: World, command: Command) -> bool:
	command.tick = made.tick
	return Production.apply_place(made, command)


## The work of the type `id` in hundredths of a tick: what `build_left` holds when a site starts.
static func done(made: World, id: String) -> int:
	return made.type_build_ticks[type_of(made, id)] * Production.PROGRESS_PER_TICK


static func cost(made: World, id: String) -> int:
	return made.type_cost[type_of(made, id)]


static func hit_points(made: World, id: String) -> int:
	return made.type_max_hp[type_of(made, id)]


## Writes a short build time for the type `id`, so a case runs few ticks.
static func fast(made: World, id: String, ticks: int) -> void:
	made.type_build_ticks[type_of(made, id)] = ticks


## The rows with `build_left` above 0, ascending.
static func sites(made: World) -> Array[int]:
	var found: Array[int] = []
	for row: int in made.unit_count():
		if made.build_left[row] > 0:
			found.append(row)
	return found


## The last row, which is the one a PLACE or a spawn has just added.
static func last(made: World) -> int:
	return made.unit_count() - 1


## The rows of `player`'s units of the type `id`, ascending.
static func rows_of(made: World, player: int, id: String) -> Array[int]:
	return Rig.rows_of(made, player, id)


## Gives the building row `row` an unfinished state by hand: `work` hundredths of a tick left.
static func unfinish(made: World, row: int, work: int = 100000) -> void:
	made.build_left[row] = work
