extends RefCounted
## The Worlds of the FOG lockstep runs (plan P46n2), each a static function that returns the same
## World for the same arguments, so the rig can build the twin's side and the kernels' side from one
## Callable (`Worlds.arena.bind(...)`). Not a test suite.
##
## arena: the seed-42 perf arena. controls: the controls_test scenario with a seed. field: a
## hand-built World of any size and any number of players (a type per sight, no speed, so the
## units stand where a case puts them), with its units stamped by prepare(). random: a seeded random
## state of field(). bend: a grid that configure() never makes.

const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const CONTROLS_PATH: String = "res://data/scenarios/controls_test.tres"
## The sights of the types of random(), in milli-tiles: the pad sight, a sight below a tile, one
## tile exactly, sights that do not end on a tile, the arena's, and one that covers any map there.
const SIGHTS: Array[int] = [
	0, 500, 999, 1000, 1500, 2000, 2500, 3999, 6000, 7000, 9000, 15000, 91000
]
## The cadences of random(): below 1, the shipped one, shorter and longer ones, and a very long one.
const PERIODS: Array[int] = [-3, 0, 1, 2, 3, 3, 3, 4, 7, 1 << 40]
## The ticks a random state may start at: before 0, early, late, and near the top of the range that
## core/fog.h records.
const TICKS: Array[int] = [-20, -3, 0, 1, 2, 30, 99, 1 << 40, (1 << 61) + 5]


## The seed-42 perf arena (the jitter drawn as the runner draws it), with `rules` (null: the shipped
## data/rules.tres) and then the members of `members` set on the World.
static func arena(rules: RulesDef = null, members: Dictionary = {}) -> World:
	var scenario: ScenarioDef = (load(ARENA_PATH) as ScenarioDef).duplicate() as ScenarioDef
	if rules != null:
		scenario.rules = rules
	var world: World = World.from_scenario(scenario, DetRandom.create(42, DetRandom.STREAM_SIM))
	for member: StringName in members:
		world.set(member, members[member])
	return world


## The controls_test scenario (30 blue tanks and 10 red ones on 48 x 48 tiles) with `match_seed`.
static func controls(match_seed: int) -> World:
	var scenario: ScenarioDef = load(CONTROLS_PATH) as ScenarioDef
	return World.from_scenario(scenario, DetRandom.create(match_seed, DetRandom.STREAM_SIM))


## A World of `cols` x `rows` tiles for `players` players with one type per entry of `sights` (the
## sight of type k is `sights[k]` milli-tiles), the members of `members` set on it
## (fog_period_ticks, tick...), and then `units` added, each [owner, type, x, y] in milli-tiles, and
## the World prepared, which stamps their discs. The types have speed 0, so nothing moves unless a
## case moves it.
static func field(
	cols: int, rows: int, players: int, sights: Array, units: Array = [], members: Dictionary = {}
) -> World:
	var world: World = World.new()
	world.map_w = cols * World.MILLI_PER_TILE
	world.map_h = rows * World.MILLI_PER_TILE
	world.player_count = players
	for kind: int in sights.size():
		world.type_ids.append(StringName("sight_%d" % kind))
		world.type_sight.append(int(sights[kind]))
	for member: StringName in members:
		world.set(member, members[member])
	for unit: Array in units:
		world.add_unit(unit[0], unit[1], unit[2], unit[3])
	world.prepare()
	return world


## The middle of tile `tile` in milli-tiles.
static func centre(tile: int) -> int:
	return tile * World.MILLI_PER_TILE + World.TILE_CENTRE


## Seeded random state number `salt`: a map of 1 to 40 x 1 to 30 tiles, 1 to 4 players, 1 to 4
## types of the SIGHTS (with `pad_types`, some rows have a type past them, with no sight entry:
## the pad mask; Sim.step cannot run such a World, as the other phases index their tables by the
## type), a cadence of PERIODS and a tick of TICKS, and 0 to 119 units of the players and the
## neutral player at random points, on the map and off it, a few on one point. After prepare()
## some rows are moved to another stamped cell (their discs follow, so the counts stay
## consistent), some are left unstamped (`fog_cell` -1, a row that joined late), some belong to
## no player (the neutral player 0, or a player past player_count, which no longer have a disc),
## and then every row moves to a new random point, so the first update has work, and a few have
## hit points 0 (taken out first). The grid is whole; bend() makes a bad one.
@warning_ignore("integer_division")
static func random(salt: int, pad_types: bool = true) -> World:
	var rng: DetRandom = DetRandom.create(salt, 61)
	var cols: int = 1 + rng.next_int(40)
	var rows: int = 1 + rng.next_int(30)
	var players: int = 1 + rng.next_int(4)
	var sights: Array = []
	for _kind: int in 1 + rng.next_int(4):
		sights.append(SIGHTS[rng.next_int(SIGHTS.size())])
	var members: Dictionary = {
		&"fog_period_ticks": PERIODS[rng.next_int(PERIODS.size())],
		&"tick": TICKS[rng.next_int(TICKS.size())]
	}
	var width: int = cols * World.MILLI_PER_TILE
	var height: int = rows * World.MILLI_PER_TILE
	var units: Array = []
	for _unit: int in rng.next_int(120):
		var owner: int = rng.next_int(players + 1)
		var type: int = rng.next_int(sights.size() + int(pad_types))
		var at: Vector2i = _point(rng, width, height)
		units.append([owner, type, at.x, at.y])
		if rng.next_int(10) == 0:
			units.append([owner, type, at.x, at.y])
	var world: World = field(cols, rows, players, sights, units, members)
	var pad: int = world.type_sight.size()
	for row: int in world.unit_count():
		var owner: int = world.owner[row]
		var stamped: int = world.fog_cell[row]
		var kind: int = rng.next_int(12)
		var target: int = rng.next_int(world.fog.cells)
		if stamped < 0 or kind > 4:
			continue
		var mask: int = mini(world.type_index[row], pad)
		world.fog.stamp(owner, stamped, mask, -1)
		if kind == 0:
			world.fog_cell[row] = -1
		elif kind == 1:
			world.fog_cell[row] = -1
			world.owner[row] = 0
		elif kind == 2:
			world.fog_cell[row] = -1
			world.owner[row] = players + 1 + rng.next_int(3)
		else:
			world.fog.stamp(owner, target, mask, 1)
			world.fog_cell[row] = target
	if rng.next_int(3) != 0:
		_perturb(world, rng)
	for row: int in world.unit_count():
		var at: Vector2i = _point(rng, width, height)
		world.pos_x[row] = at.x
		world.pos_y[row] = at.y
		if rng.next_int(14) == 0:
			world.hp[row] = 0
	return world


## Makes the grid of `world` say something that configure() never does: "one column less", "one row
## more", "no columns", "no rows", "no rows, no cells" (no cells at all), "cells that the columns do
## not divide" (the arrays sized for them), or anything else: sides of minus the columns and rows.
@warning_ignore("integer_division")
static func bend(world: World, how: String) -> void:
	var fog: FogGrid = world.fog
	match how:
		"one column less":
			fog.cols -= 1
		"one row more":
			fog.rows += 1
		"no columns":
			fog.cols = 0
		"no rows":
			fog.rows = 0
		"no rows, no cells":
			fog.configure(fog.cols, 0, fog.player_count)
		"cells that the columns do not divide":
			fog.cells += 5
			fog.dirty_capacity = fog.cells / 4
			fog.visible.resize(fog.player_count * fog.cells)
			fog.explored.resize(fog.player_count * fog.cells)
			fog.listed.resize(fog.player_count * fog.cells)
			fog.dirty.resize(fog.player_count * fog.dirty_capacity)
		_:
			fog.cols = -fog.cols
			fog.rows = -fog.rows


## Writes into the fog of `world` what the sim never makes, which the rule still defines: up to 30
## cells with a visible count from -1 to 3, an explored byte and a mark at random (so a stamp may
## leave a cell visible that is not explored, and a mark may stand for a cell that is not in a
## list), and for half of the players a dirty block of random cells with its count, flag and
## version.
static func _perturb(world: World, rng: DetRandom) -> void:
	var fog: FogGrid = world.fog
	for _n: int in rng.next_int(30):
		var at: int = rng.next_int(fog.player_count * fog.cells)
		fog.visible[at] = rng.next_int(5) - 1
		fog.explored[at] = rng.next_int(2)
		fog.listed[at] = rng.next_int(2)
	for block: int in fog.player_count:
		if rng.next_int(2) == 0:
			continue
		var used: int = rng.next_int(fog.dirty_capacity + 1)
		for entry: int in used:
			fog.dirty[block * fog.dirty_capacity + entry] = rng.next_int(fog.cells)
		fog.dirty_count[block] = used
		fog.dirty_full[block] = rng.next_int(2)
		fog.version[block] = rng.next_int(1000)


## A point for a unit of a random state: on the map (7 in 10), on a tile's corner (1), at the edge
## of the map or past it (1) or off the map by up to 3 tiles (1).
static func _point(rng: DetRandom, width: int, height: int) -> Vector2i:
	var x: int = rng.next_int(maxi(width, 1))
	var y: int = rng.next_int(maxi(height, 1))
	var kind: int = rng.next_int(10)
	if kind == 7:
		return Vector2i(x / 1000 * 1000, y / 1000 * 1000)
	if kind == 8:
		return Vector2i(width - rng.next_int(2), height + rng.next_int(2) - 1)
	if kind == 9:
		return Vector2i(rng.next_int(width + 6000) - 3000, rng.next_int(height + 6000) - 3000)
	return Vector2i(x, y)
