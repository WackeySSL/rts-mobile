extends RefCounted
## The Worlds of the TARGETING lockstep runs (plan P41n2), each a static function that returns the
## same World for the same arguments, so the rig can build the twin's side and the kernels' side
## from one Callable (`Worlds.arena.bind(...)`). Not a test suite.
##
## arena: the seed-42 perf arena. controls: the controls_test scenario with a seed. lattice: a
## small field of the three shipped types on points of a 1000 milli lattice, so that several
## enemies stand at the same squared distance. open_field: a big map with sparse rock and two
## sides far apart. scouts: the roster of test_targeting_kernel_indexes.gd (an unarmed scout first,
## so type_weapon is [-1, 0, 1]) on a field with a little rock.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const CONTROLS_PATH: String = "res://data/scenarios/controls_test.tres"
const RIFLE: int = 0
const ROCKET: int = 1
const TANK: int = 2
## The fourth type of open_field(), and how many of each side have it.
const LONG_GUN: int = 3
const LONG_GUNS: int = 6
## The index of rock in GridWorld.GROUND ('#').
const ROCK: int = 2
## The indexes in GridWorld.GROUND of '^' (scrub: foot only), 'w' (not tracked) and 't' (not
## wheeled).
const SCRUB: int = 1
const TRACKED_BLOCKED: int = 3
const WHEELED_BLOCKED: int = 4
## The navigation modes a state that is stepped through Sim.step may start in (not FIELD, which
## needs a slot of the flow cache): NONE, DIRECT, HOLD and CHASE.
const MODES: Array[int] = [0, 1, 3, 4]


## The seed-42 perf arena (the jitter drawn as the runner draws it), with `rules` (null: the
## shipped data/rules.tres) and then the members of `members` set on the World.
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


## `per_side` units of each player on a field of 20 x 12 tiles: random types (the three shipped
## ones) at random points of a lattice of 1000 milli, side 1 in the three columns west of the
## middle and side 2 in the three east of it (1 to 5 tiles apart, so the sides are in reach of each
## other), and no orders. Many pairs stand at the same distance from a third unit, and units on the
## same point are possible. The points are the centres of tiles, or with `aligned` the corners of
## tiles, which are also corners of the cells of the targeting grid (4000 milli), so that a unit
## can stand exactly on the edge of the window that a scan covers. The members of `members` are
## set on the World, as in arena().
static func lattice(
	salt: int, per_side: int = 24, members: Dictionary = {}, aligned: bool = false
) -> World:
	var rng: DetRandom = DetRandom.create(salt, 31)
	var world: World = Rig.data_world(20, 12)
	for member: StringName in members:
		world.set(member, members[member])
	var offset: int = 0 if aligned else World.TILE_CENTRE
	for player: int in [1, 2]:
		for _unit: int in per_side:
			var column: int = 9 - rng.next_int(3) if player == 1 else 10 + rng.next_int(3)
			var line: int = rng.next_int(12)
			world.add_unit(player, rng.next_int(3), column * 1000 + offset, line * 1000 + offset)
	return world


## A field of `cols` x `rows` tiles with `rock_percent` of its tiles rock, and `per_side` units of
## each player in the first and the last two columns of the lower fifth of the map (so that the
## sides are `cols` tiles apart, and the segments between them are wide): the first `LONG_GUNS` of
## each side are a fourth type, a gun with a range and an acquire range of 60,000 milli (a squared
## distance of 3.6 * 10^9 is in reach, past 2^31), the others are the three shipped types.
@warning_ignore("integer_division")
static func open_field(
	salt: int, cols: int = 64, rows: int = 64, rock_percent: int = 4, per_side: int = 30
) -> World:
	var rng: DetRandom = DetRandom.create(salt, 32)
	var long_gun: UnitDef = Rig.unit(&"long_gun", 60000, 60000, 60000, 0, [100, 100, 100, 100])
	long_gun.weapon.damage = 1  # A shot from across the map is a pin prick: the field lasts.
	var units: Array[UnitDef] = [
		load(Rig.RIFLE_PATH) as UnitDef,
		load(Rig.ROCKET_PATH) as UnitDef,
		load(Rig.TANK_PATH) as UnitDef,
		long_gun
	]
	var world: World = Rig.world_of(units, cols, rows)
	world.terrain_cost = PackedByteArray(GridWorld.GROUND_COST)
	for tile: int in cols * rows:
		if rng.next_int(100) < rock_percent:
			world.set_terrain(tile, ROCK)
	for player: int in [1, 2]:
		for unit: int in per_side:
			var column: int = rng.next_int(2) if player == 1 else cols - 1 - rng.next_int(2)
			var line: int = rows - 1 - rng.next_int(maxi(rows / 5, 1))
			var type: int = LONG_GUN if unit < LONG_GUNS else rng.next_int(3)
			world.add_unit(player, type, column * 1000 + 500, line * 1000 + 500)
	return world


## The roster of test_targeting_kernel_indexes.gd on a field of `cols` x `rows` tiles with a little
## rock, `per_side` units of each player of a random type of the three (the scout, the wheeled gun A
## and the tracked gun B), at random points: type 0 has no weapon, and the weapon index of a gun is
## its type index minus 1.
@warning_ignore("integer_division")
static func scouts(salt: int, cols: int = 30, rows: int = 16, per_side: int = 20) -> World:
	var rng: DetRandom = DetRandom.create(salt, 33)
	var world: World = Rig.world_of(scout_roster(), cols, rows)
	world.terrain_cost = PackedByteArray(GridWorld.GROUND_COST)
	for tile: int in cols * rows:
		if rng.next_int(100) < 5:
			world.set_terrain(tile, ROCK)
	paint_classes(world, DetRandom.create(salt, 36))
	for player: int in [1, 2]:
		for _unit: int in per_side:
			var column: int = rng.next_int(cols / 2) + (0 if player == 1 else cols / 2)
			world.add_unit(
				player,
				rng.next_int(3),
				column * 1000 + rng.next_int(1000),
				rng.next_int(rows) * 1000 + rng.next_int(1000)
			)
	return world


## The roster of test_targeting_kernel_indexes.gd: type 0 a scout with no weapon (foot, acquire
## range 9000), type 1 gun A (wheeled, light armour, weapon 0: range 4000, minimum range 1000, 0%
## against light armour) and type 2 gun B (tracked, infantry armour, weapon 1: range 3000, minimum
## range 500), so that type_weapon is [-1, 0, 1] and no weapon index is a type index.
static func scout_roster() -> Array[UnitDef]:
	var scout: UnitDef = Rig.unit(&"scout", 9000, 9000, 0, 0, [])
	var gun_a: UnitDef = Rig.unit(&"gun_a", 9000, 5000, 4000, 1000, [100, 0, 100, 100])
	gun_a.move_class = World.MoveClass.WHEELED
	gun_a.armour = World.Armour.LIGHT
	var gun_b: UnitDef = Rig.unit(&"gun_b", 9000, 6000, 3000, 500, [100, 100, 100, 100])
	gun_b.move_class = World.MoveClass.TRACKED
	return [scout, gun_a, gun_b]


## Seeded random state number `salt`: a map of 4 to 31 x 4 to 23 tiles with rock on up to 12% of
## them, the three shipped types or the scout roster (one state in four has a type without a weapon
## or with a weapon index past the tables), 20 to 119 units of the two players and the neutral
## player (one in eight), on the map, off it and on one point, with random orders, targets (a unit,
## itself, one that is gone, none), hit points (a few units die in the first tick), a random tick
## (some below 0) and cadences from -3 to 9. One state in three has a targeting grid of another cell
## side (500 to 12,000 milli, which changes the cells a reach covers). With `garbage` the
## navigation columns hold any value too (a state for one TARGETING phase, the rig's once());
## without, they hold what a unit can hold (a state to step through Sim.step).
@warning_ignore("integer_division")
static func random(salt: int, garbage: bool = false) -> World:
	var rng: DetRandom = DetRandom.create(salt, 34)
	var cols: int = 4 + rng.next_int(28)
	var rows: int = 4 + rng.next_int(20)
	var scouts_roster: bool = rng.next_int(2) == 0
	var world: World = (
		Rig.world_of(scout_roster(), cols, rows) if scouts_roster else Rig.data_world(cols, rows)
	)
	world.terrain_cost = PackedByteArray(GridWorld.GROUND_COST)
	var rock: int = rng.next_int(13)
	for tile: int in cols * rows:
		if rng.next_int(100) < rock:
			world.set_terrain(tile, ROCK)
	if scouts_roster:
		paint_classes(world, DetRandom.create(salt, 35))
	var count: int = 20 + rng.next_int(100)
	var width: int = cols * 1000
	var height: int = rows * 1000
	for _unit: int in count:
		var x: int = rng.next_int(width)
		var y: int = rng.next_int(height)
		match rng.next_int(10):
			0:
				x = rng.next_int(width + 6000) - 3000
				y = rng.next_int(height + 6000) - 3000
			1:
				x = (x / 1000) * 1000
				y = (y / 1000) * 1000
		var owner: int = 0 if rng.next_int(8) == 0 else 1 + rng.next_int(2)
		var row: int = world.index_of(world.add_unit(owner, rng.next_int(3), x, y))
		world.order[row] = rng.next_int(4)
		world.hp[row] = 1 if rng.next_int(12) == 0 else world.hp[row]
		world.goal_x[row] = rng.next_int(width)
		world.goal_y[row] = rng.next_int(height)
		world.nav_mode[row] = rng.next_int(5) if garbage else MODES[rng.next_int(MODES.size())]
		world.nav_cell[row] = rng.next_int(2) - 1
	for row: int in count:
		world.target[row] = _any_id(rng, row, count, garbage)
		world.order_target[row] = _any_id(rng, row, count, garbage)
		if garbage:
			world.nav_cell[row] = rng.next_int(3) - 1
			world.field[row] = rng.next_int(4) - 1
			world.nav_next[row] = rng.next_int(3) - 2
			world.best_dist[row] = rng.next_int(100)
			world.stall[row] = rng.next_int(5)
	var unarmed: int = rng.next_int(8)
	if unarmed == 0:
		world.type_weapon[TANK] = -1
	elif unarmed == 1:
		world.type_weapon[ROCKET] = world.weapon_range.size() + rng.next_int(3)
	var periods: Array[int] = [-3, -1, 0, 1, 2, 3, 4, 5, 9]
	world.retarget_period_ticks = periods[rng.next_int(periods.size())]
	world.line_check_period_ticks = periods[rng.next_int(periods.size())]
	world.tick = rng.next_int(100) - 20
	if rng.next_int(3) == 0:
		var sides: Array[int] = [500, 1000, 2000, 3000, 4000, 5500, 8000, 12000]
		world.prepare()
		world.target_grid.configure(
			world.map_w, world.map_h, sides[rng.next_int(sides.size())], world.max_rows
		)
	return world


## A unit id for a random reference: 0, the unit itself (only with `own`), another unit or one that
## is gone.
static func _any_id(rng: DetRandom, row: int, count: int, own: bool) -> int:
	var kind: int = rng.next_int(10)
	if kind < 4:
		return 0
	if kind == 4:
		return row + 1 if own else 1 + (row + 1) % count
	if kind == 5:
		return count + 1 + rng.next_int(5)
	return 1 + rng.next_int(count)


## Takes the targeting grid `grid` apart to `cols` x `rows` cells with every head empty: a grid that
## SpatialGrid.configure never makes when one of the two is 0 and the other is not.
static func emptied(grid: SpatialGrid, cols: int, rows: int) -> void:
	grid.cols = cols
	grid.rows = rows
	grid.head.resize(cols * rows)
	grid.head.fill(-1)


## Paints 4% of the tiles of `world` with scrub (foot units only cross it), 4% with 'w' (open to
## foot and wheeled units, closed to tracked ones) and 4% with 't' (open to foot and tracked units,
## closed to wheeled ones), over what is there, so that a line is clear for one movement class and
## blocked for another. The shipped types are foot, foot and tracked, so this is for the scout
## roster, whose guns are wheeled and tracked.
@warning_ignore("integer_division")
static func paint_classes(world: World, rng: DetRandom) -> void:
	for tile: int in world.map_cols * world.map_rows:
		var roll: int = rng.next_int(100)
		if roll < 12:
			world.set_terrain(tile, [SCRUB, TRACKED_BLOCKED, WHEELED_BLOCKED][roll / 4])
