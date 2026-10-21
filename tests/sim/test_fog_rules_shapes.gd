extends GdUnitTestSuite
## The cell rule of the fog rules (P46b; ADR 0010 section 1 "Users"), part 3 of test_fog.gd: which
## cell of the fog holds a point is `World.cell_of`'s rule on the fog's own sides, and the maps of
## test_fog_rules.gd are square, so a column bound cannot be told from a row bound there. These
## suites run the rule on a wide map (40 x 20 tiles) and a tall one (20 x 40), where a tile past the
## short side is still on the map, and on fogs whose sides do not make their cells (the guard of
## `Targeting.run` and `Targeting.sees`, and of the kernel's `has_cells`, which FogUpdate.run's
## guard is the twin of: no fog, so every cell is seen; `FogGrid.configure` never makes one):
## - `Targeting.sees` on both maps: in the map, off it (the nearest edge cell) and at the corner;
## - an enemy beyond the short side of the map is not acquired and an `ATTACK` on it is dropped
##   while it is out of sight, and is taken, locked and let go as on a square map when it is in
##   sight, under both implementations;
## - `Targeting.sees` on every shape of bent fog (its twin runs in test_targeting_lockstep_fog.gd,
##   which compares the two versions on the same fogs).
##
## Hand-built worlds with literal numbers, as in test_fog_rules.gd: a gun (type 0) sees 3000,
## acquires at 5000 and shoots 4000, so the tile 3 east of it is seen and the one 4 east is not;
## the scout (type 1) sees 3000 and has no weapon. Every cadence is 1. A point on a wide map is
## `(along, across)` = (x, y), and on a tall map (y, x): `_spot` makes the swap, so that one list
## of numbers serves both.

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const Worlds: GDScript = preload("res://tests/sim/support/targeting_worlds.gd")
const Bends: GDScript = preload("res://tests/sim/support/fog_bends.gd")
const TARGETING: int = SimProbe.Phase.TARGETING
const GUN: int = 0
const SCOUT: int = 1
## The wide and the tall map, in tiles. The short side is 20, so the tiles 20 to 39 along are on the
## map and past a row bound (and a column bound) that takes the other side's size.
const SHAPES: Array[Vector2i] = [Vector2i(40, 20), Vector2i(20, 40)]
const SQUARE: int = 30
const IDLE: int = World.Order.IDLE
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const ATTACK: int = World.Order.ATTACK
## The units of the wide and the tall map as [player, along, across, type]: the gun of player 1 in
## the tile 30 along and 10 across, its scout in the corner (39, 19) and the post of player 2 in the
## other corner (0, 0).
const UNITS: Array[Array] = [[1, 30500, 10500, 0], [1, 39500, 19500, 1], [2, 500, 500, 0]]
## What the fog says, as [player, along, across, seen], on the map of UNITS. The disc of a sight of
## 3000 is the tiles with dx^2 + dy^2 <= 9 from the unit's own tile.
const SPOTS: Array[Array] = [
	# The gun's row: the tiles 27 to 33 along it, past the short side (20) of the map, are in its disc.
	[1, 26999, 10500, false],
	[1, 27000, 10500, true],
	[1, 33999, 10500, true],
	[1, 34000, 10500, false],
	# The scout's disc in the corner: 36 to 39 along its row, and 16 to 19 across along its column.
	[1, 35999, 19500, false],
	[1, 36000, 19500, true],
	[1, 39999, 19500, true],
	[1, 39500, 15999, false],
	[1, 39500, 16000, true],
	# Off the map, the nearest edge cell: past the long side, the short side, and both.
	[1, 99000, 19500, true],
	[1, 39500, 99000, true],
	[1, 99000, 99000, true],
	[1, 99000, 10500, false],
	[1, 30500, 99000, false],
	[1, -5000, -5000, false],
	# The post's disc in the other corner: 0 to 3 along and across, and the corner for any point
	# off the map on its two low sides.
	[2, 3999, 500, true],
	[2, 4000, 500, false],
	[2, -5000, -5000, true],
	[2, 0, -1, true],
	[2, 3999, -5000, true],
	[2, 4000, -5000, false],
	[2, 99000, 99000, false]
]


func test_sees_reads_the_cell_on_the_fogs_own_sides_of_a_wide_and_a_tall_map() -> void:
	for shape: Vector2i in SHAPES:
		var world: World = _shaped(shape)
		for unit: Array in UNITS:
			var spot: Vector2i = _spot(shape, unit[1], unit[2])
			world.add_unit(unit[0], unit[3], spot.x, spot.y)
		Worlds.stamp_fog(world)
		for item: Array in SPOTS:
			var spot: Vector2i = _spot(shape, item[1], item[2])
			var label: String = "%s: player %d at %s" % [shape, item[0], spot]
			(
				assert_bool(Targeting.sees(world, item[0], spot.x, spot.y))
				. override_failure_message(label)
				. is_equal(item[3])
			)


## An enemy at the tile 33 or 34 of the long side of the map: the tile is past the short side (20),
## a column bound that took it would clamp it to a cell of the middle of the map, and the enemy
## would be seen there or not seen there whatever its own cell says. On both maps and under both
## implementations (the lock, the keep and the scan of the phase, and the validation of `ATTACK`).
func test_an_enemy_past_the_short_side_of_the_map_is_seen_by_its_own_cell(
	impl: int, _test_parameters := _both()
) -> void:
	for shape: Vector2i in SHAPES:
		var world: World = _shaped(shape)
		var at: Vector2i = _spot(shape, 30500, 10500)
		var far: Vector2i = _spot(shape, 34500, 10500)
		var near: Vector2i = _spot(shape, 33500, 10500)
		var mine: int = world.add_unit(1, GUN, at.x, at.y)
		var theirs: int = world.add_unit(2, GUN, far.x, far.y)
		Worlds.stamp_fog(world)
		_in(world, impl)
		var label: String = "%s" % shape
		# Tile 34 is outside the disc: the order is dropped and counted, and nobody acquires anybody.
		Sim.step(world, [_attack(world, mine, theirs)])
		assert_int(world.dropped_commands).override_failure_message(label).is_equal(1)
		(
			assert_array([world.order[0], world.order_target[0]])
			. override_failure_message(label)
			. is_equal([IDLE, 0])
		)
		Sim.step(world, [])
		assert_array([world.target[0], world.target[1]]).override_failure_message(label).is_equal(
			[0, 0]
		)
		# Tile 33 is inside it: the scan takes the enemy (the order is still IDLE), and the same
		# `ATTACK` is taken now and locks.
		world.pos_x[1] = near.x
		world.pos_y[1] = near.y
		Sim.step(world, [])
		assert_array([world.order[0], world.target[0]]).override_failure_message(label).is_equal(
			[IDLE, theirs]
		)
		Sim.step(world, [_attack(world, mine, theirs)])
		assert_int(world.dropped_commands).override_failure_message(label).is_equal(1)
		(
			assert_array([world.order[0], world.order_target[0], world.target[0]])
			. override_failure_message(label)
			. is_equal([ATTACK, theirs, theirs])
		)
		# Out of the disc again: on the next tick the lock is let go for the attack-move to the point
		# it was seen at.
		world.pos_x[1] = far.x
		world.pos_y[1] = far.y
		Sim.step(world, [])
		(
			assert_array([world.order[0], world.order_target[0], world.target[0]])
			. override_failure_message(label)
			. is_equal([ATTACK_MOVE, 0, 0])
		)
		assert_array([world.goal_x[0], world.goal_y[0]]).override_failure_message(label).is_equal(
			[near.x, near.y]
		)


## A fog whose sides do not make its cells is no fog: `Targeting.sees` gives every player every
## point, as it does a player with no block. The point (20500, 20500) is out of sight of both guns,
## and sees() says so before the fog is bent.
func test_sees_takes_a_fog_whose_sides_do_not_make_its_cells_for_no_grid() -> void:
	for how: String in Bends.NAMES:
		var world: World = _square()
		for player: int in [1, 2]:
			assert_bool(Targeting.sees(world, player, 20500, 20500)).is_false()
		Bends.apply(world.fog, how)
		for player: int in [1, 2]:
			var label: String = "%s, player %d" % [how, player]
			(
				assert_bool(Targeting.sees(world, player, 20500, 20500))
				. override_failure_message(label)
				. is_true()
			)
			(
				assert_bool(Targeting.sees(world, player, -5000, 99000))
				. override_failure_message(label)
				. is_true()
			)
	# The guard tests the sides and the cells, not what they were: a grid of other sides that make
	# the same 900 cells (15 x 60) is a grid, and its cell rule is its own. The cell of the point
	# (10, 20) of the map is the cell 20 * 15 + 10 = 310 of the block, which is where the gun of
	# player 1 stands in the layout of 30 columns (10 * 30 + 10), and the cell of (10, 10) is the cell
	# 160, which no disc covers.
	var world: World = _square()
	world.fog.cols = 15
	world.fog.rows = 60
	assert_bool(Targeting.sees(world, 1, 10500, 20500)).is_true()
	assert_bool(Targeting.sees(world, 1, 10500, 10500)).is_false()
	assert_bool(Targeting.sees(world, 2, 10500, 20500)).is_false()


## gdUnit4's parameter sets: the GDScript phase and the C++ kernel, a case each (SimImpls.CASES).
func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## `world` running `impl`: the kernels attached and TARGETING really in the implementation asked
## for (the problems of SimImpls.attach, none).
func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, TARGETING)).is_empty()
	return world


## The point `along` the long side of `shape` and `across` it, in milli-tiles: (x, y) on a wide map,
## (y, x) on a tall one.
func _spot(shape: Vector2i, along: int, across: int) -> Vector2i:
	return Vector2i(along, across) if shape.x > shape.y else Vector2i(across, along)


## A map of `shape` tiles with the gun and the scout, real fog, every cadence 1.
func _shaped(shape: Vector2i) -> World:
	var units: Array[UnitDef] = _units()
	var world: World = Rig.world_of(units, shape.x, shape.y, false)
	world.retarget_period_ticks = 1
	world.fog_period_ticks = 1
	return world


## A 30 x 30 map with a gun of each player at (10500, 10500) and (14000, 10500), real fog.
func _square() -> World:
	var units: Array[UnitDef] = _units()
	var world: World = Rig.world_of(units, SQUARE, SQUARE, false)
	world.retarget_period_ticks = 1
	world.fog_period_ticks = 1
	world.add_unit(1, GUN, 10500, 10500)
	world.add_unit(2, GUN, 14000, 10500)
	Worlds.stamp_fog(world)
	return world


func _units() -> Array[UnitDef]:
	var gun: UnitDef = Rig.unit(&"gun", 3000, 5000, 4000, 0, [100, 100, 100, 100])
	var scout: UnitDef = Rig.unit(&"scout", 3000, 3000, 0, 0, [])
	var units: Array[UnitDef] = [gun, scout]
	return units


## An ATTACK of the unit `id` (whose player's it is) on `target`, for the tick the World is at.
func _attack(world: World, id: int, target: int) -> Command:
	var player: int = world.owner[world.index_of(id)]
	var command: Command = Command.attack(player, PackedInt32Array([id]), target)
	command.tick = world.tick
	return command
