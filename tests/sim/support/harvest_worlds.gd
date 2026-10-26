extends RefCounted
## Worlds with ore for the harvest suites (plan rows P75 and P75b, ADR 0018 section 3): a map from
## one string per tile row over the shipped terrain set ('.' grass, 'o' ore, '#' rock, ':' sand, '~'
## water), loaded through `World.from_scenario`, so the ore cells are listed and filled the way a
## match does it. The roster is the shipped harvester, refinery, power plant and rifle squad; the
## rules are `data/rules.tres`. Harvesters and refineries are the test's to add. Not a test suite.

const RULES_PATH: String = "res://data/rules.tres"
const TERRAIN_PATH: String = "res://data/terrain/standard.tres"
const UNIT_DIR: String = "res://data/units/"
const ROSTER: Array[String] = ["harvester", "refinery", "power_plant", "rifle_squad"]


## A prepared World of the map `rows` with 2 players and the roster, then the unit and building ids
## of `extra` (a plain Array of strings: a caller reaches this through a preloaded script, so its
## literal is not typed; a case that builds with a factory asks for "vehicle_factory").
static func world(rows: Array[String], extra: Array = []) -> World:
	var map: MapDef = MapDef.new()
	map.rows = PackedStringArray(rows)
	map.terrain = load(TERRAIN_PATH) as TerrainSetDef
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map = map
	scenario.player_count = 2
	scenario.rules = load(RULES_PATH) as RulesDef
	for id: String in ROSTER + extra:
		scenario.roster.append(load(UNIT_DIR + id + ".tres") as UnitDef)
	return World.from_scenario(scenario)


## A map of `cols` x `lines` grass tiles with an ore tile at each of `ore` ((column, line) pairs).
static func grass(cols: int, lines: int, ore: Array = []) -> Array[String]:
	var rows: Array[String] = []
	for _line: int in lines:
		rows.append(".".repeat(cols))
	for tile: Vector2i in ore:
		rows[tile.y] = rows[tile.y].left(tile.x) + "o" + rows[tile.y].substr(tile.x + 1)
	return rows


## The type index of `id` in `world`, or -1.
static func type_of(world: World, id: String) -> int:
	return world.type_ids.find(StringName(id))


## Adds a harvester of `owner` at (x, y) milli-tiles in `mode`, working ore cell `slot` (an index
## into `ore_cell`, -1 none), with its refinery `home` (an id, 0 none) and `cargo` credits on board.
## Returns its id.
static func add_harvester(
	world: World,
	owner: int,
	x: int,
	y: int,
	mode: int = World.HarvestMode.SEEK,
	slot: int = -1,
	home: int = 0,
	cargo: int = 0
) -> int:
	var id: int = world.add_unit(owner, type_of(world, "harvester"), x, y)
	var row: int = world.index_of(id)
	world.harvest_mode[row] = mode
	world.harvest_slot[row] = slot
	world.home[row] = home
	world.cargo[row] = cargo
	return id


## Adds a refinery of `owner` with its top-left tile at (col, line); returns its id.
static func add_refinery(world: World, owner: int, col: int, line: int) -> int:
	return world.add_building(owner, type_of(world, "refinery"), col, line)


## One tick with `commands` (a plain Array, as a preloaded script's caller has no typed literal):
## each is stamped with the World's tick, so `Sim.step` applies it.
static func send(world: World, commands: Array) -> void:
	var stamped: Array[Command] = []
	stamped.assign(commands)
	for command: Command in stamped:
		command.tick = world.tick
	Sim.step(world, stamped)


## Runs `count` ticks with no commands.
static func step(world: World, count: int = 1) -> void:
	for _tick: int in count:
		Sim.step(world, [] as Array[Command])


## Gives unit `id` a MOVE to the milli point (x, y) the way Harvest's own orders do (the order, the
## goal, no group cell, a fresh DIRECT navigation), without touching its harvest mode.
static func walk_to(world: World, id: int, x: int, y: int) -> void:
	var row: int = world.index_of(id)
	world.order[row] = World.Order.MOVE
	world.goal_x[row] = x
	world.goal_y[row] = y
	world.group_cell[row] = -1
	Movement.reset_nav(world, PackedInt32Array([row]), World.NavMode.DIRECT)


## The first tick at or after `from` on which a row of `id` takes its turn at `period`: the ticks
## with `(tick + id) % period == 0` that the loop staggers its looks, mining and unloading on.
static func turn(from: int, id: int, period: int) -> int:
	return from + (period - (from + id) % period) % period


## The harvest mode of unit `id`.
static func mode_of(world: World, id: int) -> int:
	return world.harvest_mode[world.index_of(id)]


## The cargo of unit `id`.
static func cargo_of(world: World, id: int) -> int:
	return world.cargo[world.index_of(id)]


## The harvest state and order of unit `id`, to compare before and after: harvest mode, ore cell,
## order, goal x and y, cargo and home.
static func columns_of(world: World, id: int) -> Array[int]:
	var row: int = world.index_of(id)
	return [
		world.harvest_mode[row],
		world.harvest_slot[row],
		world.order[row],
		world.goal_x[row],
		world.goal_y[row],
		world.cargo[row],
		world.home[row],
	]
