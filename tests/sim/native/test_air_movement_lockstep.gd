extends GdUnitTestSuite
## Aircraft in the movement phases, the GDScript twin against the C++ kernels (plan row P240, ADR
## 0036 sections 4 and 13, ADR 0013 section 4). Two Worlds are built by one function, the first
## stepped with the GDScript phases and the second with every kernel the library has, each through
## its own MatchLoop with the same orders, and after every tick the state hash and the full state
## are compared (separation_lockstep_rig.gd). The roster is LayerWorlds' (gun, rocket, rifle, flak,
## jet AIR, bomber AIR, drone LOW_AIR, scout, post) and a 2 x 2 unarmed building.
## - SEPARATION per layer: rows of another layer are not looked at, so a stack of aircraft over
##   tanks over drone squads pushes only within each layer.
## - INTEGRATE and FLOW: aircraft cross a wall of rock and a footprint in a straight line with no
##   flow field while the ground rows of the same order walk round it by the field.
## - The requirement of P238's note (ADR 0036 section 5): a ground row with an ATTACK lock on a
##   LOW_AIR drone hovering over rock has no next step there (`Movement.NO_NEXT`), so it stops at
##   the rock and fires once in range.

const Rig: GDScript = preload("res://tests/sim/support/separation_lockstep_rig.gd")
const Layers: GDScript = preload("res://tests/sim/support/layer_worlds.gd")
const BuildingWorlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const COLS: int = 30
const ROWS: int = 16
## The wall of rock: columns 11 to 13, rows 0 to 12 (the gap is rows 13 to 15), and a 'w' column.
const WALL_FIRST: int = 11
const WALL_LAST: int = 13
## A column of 'w' (open to foot and wheeled rows, closed to tracked rows) beside the rock, in the
## same rows. The gun is the tracked row; the other walkers are foot.
const WATER: int = 14
const WALL_ROWS: int = 13
const BLOCK: int = 9
## Floors, about two thirds of the twin's tally, measured: the crossing (400 ticks) skipped 5,672
## rows of another layer, had 1,838 overlaps and 84 pairs of a mover and an idle row; the scatter
## run (60 ticks after the first phase) 2,011 overlaps and 13,780 skipped rows.
const FLOOR_CROSSING_OTHER: int = 3700
const FLOOR_CROSSING_HITS: int = 1200
const FLOOR_CROSSING_MIXED: int = 50
const FLOOR_SCATTER_HITS: int = 1300
const FLOOR_SCATTER_OTHER: int = 9000
const MOVE_TICKS: int = 400
const DUEL_TICKS: int = 200


## The roster, a 2 x 2 building of player 2 at tiles (18, 6) and the wall. `rifle_range` is the
## reach of the rifle (the ground shooter of the duels); the duel's drone is unarmed, so that it
## does not shoot the rifle and does not die.
func _world(rifle_range: int = 4000, drone_armed: bool = true) -> World:
	var units: Array[UnitDef] = Layers.roster()
	units[Layers.RIFLE].weapon.range = rifle_range
	units[Layers.GUN].move_class = World.MoveClass.TRACKED
	if not drone_armed:
		units[Layers.DRONE].weapon = null
		units[Layers.DRONE].max_hp = 100000
	units.append(BuildingWorlds.block("wall_2x2", 2, 2))
	var world: World = Layers.Rig.world_of(units, COLS, ROWS, true)
	world.terrain_cost = PackedByteArray(GridWorld.GROUND_COST)
	for column: int in range(WALL_FIRST, WALL_LAST + 1):
		for line: int in WALL_ROWS:
			world.set_terrain(line * COLS + column, GridWorld.GROUND.find("#"))
	for line: int in WALL_ROWS:
		world.set_terrain(line * COLS + WATER, GridWorld.GROUND.find("w"))
	world.terrain_buildable = PackedByteArray(BuildingWorlds.BUILDABLE)
	world.add_building(2, BLOCK, 18, 6)
	return world


## Two jets, two bombers, two drones and three ground units west of the wall, rows 4 to 9.
func _crossing() -> World:
	var world: World = _world()
	for k: int in 2:
		world.add_unit(1, Layers.JET, 3500, 6500 + k * 1000)
		world.add_unit(1, Layers.BOMBER, 4500, 6500 + k * 1000)
		world.add_unit(1, Layers.DRONE, 5500, 6500 + k * 1000)
	world.add_unit(1, Layers.GUN, 3500, 4500)
	world.add_unit(1, Layers.SCOUT, 4500, 4500)
	world.add_unit(1, Layers.RIFLE, 5500, 4500)
	return world


## 5 each of guns, jets, drones and scouts within one tile, so that every layer overlaps every
## other, and one lone jet on the same point as one lone gun far away.
func _pile() -> World:
	var world: World = _world()
	for k: int in 5:
		for type: int in [Layers.GUN, Layers.JET, Layers.DRONE, Layers.SCOUT]:
			world.add_unit(1, type, 6000 + k * 60, 6000 + (k % 2) * 60)
	world.add_unit(1, Layers.JET, 4000, 12000)
	world.add_unit(1, Layers.GUN, 4000, 12000)
	return world


## One rifle (ground, mask 5) of player 1 at tile (4, 6) and one drone (LOW_AIR) of player 2
## hovering at (12500, 6500), over the rock of the wall; the rifle is ordered to attack it.
func _duel(rifle_range: int, drone_at: Vector2i = Vector2i(12500, 6500)) -> World:
	var world: World = _world(rifle_range, false)
	world.add_unit(1, Layers.RIFLE, 4500, 6500)
	world.add_unit(2, Layers.DRONE, drone_at.x, drone_at.y)
	return world


## The rows of player 1's units of `types` (the building of player 2 is row 0).
func _rows_of(world: World, types: Array) -> PackedInt32Array:
	var found: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		if world.type_index[row] in types and world.owner[row] == 1:
			found.append(row)
	return found


func _ids_of(world: World, types: Array) -> PackedInt32Array:
	var found: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		if world.type_index[row] in types and world.owner[row] == 1:
			found.append(world.unit_id[row])
	return found


func _send_all(world: World, tick: int) -> Array[Command]:
	var out: Array[Command] = []
	if tick == 0:
		var every: Array = [
			Layers.GUN, Layers.JET, Layers.DRONE, Layers.SCOUT, Layers.BOMBER, Layers.RIFLE
		]
		out.append(Command.move(1, _ids_of(world, every), 26500, 6500))
	return out


func _attack_drone(world: World, tick: int) -> Array[Command]:
	var out: Array[Command] = []
	if tick == 0:
		out.append(
			Command.attack(1, _ids_of(world, [Layers.RIFLE]), world.unit_id[_drone_row(world)])
		)
	return out


func _drone_row(world: World) -> int:
	for row: int in world.unit_count():
		if world.owner[row] == 2 and world.type_index[row] == Layers.DRONE:
			return row
	return -1


func _scatter(world: World, tick: int) -> Array[Command]:
	var out: Array[Command] = []
	if tick == 0:
		for type: int in [Layers.GUN, Layers.JET, Layers.DRONE, Layers.SCOUT]:
			var ids: PackedInt32Array = _ids_of(world, [type])
			out.append(Command.move(1, ids, 14000 + type * 1500, 3000 + type * 2500))
	return out


## SEPARATION on the stacks, alone, with INTEGRATE and with every phase. A lone jet on a gun's point
## pushes nothing and is pushed by nothing (no look, no push), while the rows of one layer in the
## pile push one another; the run that follows scatters the types in four directions.
func test_separation_pairs_only_rows_of_one_layer() -> void:
	for mask: int in [Rig.ONLY, Rig.WITH_INTEGRATE, Rig.ALL]:
		var rig: RefCounted = Rig.new().setup(_pile, mask)
		assert_array(rig.problems).is_empty()
		assert_str(rig.once()).override_failure_message("mask %d" % mask).is_empty()
		var world: World = rig.worlds[0]
		var tally: Dictionary[StringName, int] = rig.tally()
		# The scout is ground like the gun: 10 ground rows meet 9 of their own layer and stop at the
		# cap on hits (8), 5 jets and 5 drones meet 4 each; every other layer is skipped, not looked at.
		assert_int(tally[&"looks"]).is_equal(10 * 8 + 5 * 4 + 5 * 4)
		assert_int(tally[&"other_layer"]).is_greater(0)
		var lone_jet: int = world.unit_count() - 2
		assert_int(world.push_x[lone_jet]).is_equal(0)
		assert_int(world.push_x[lone_jet + 1]).is_equal(0)
		assert_int(world.push_y[lone_jet]).is_equal(0)
		var found: String = rig.run(60, _scatter)
		assert_str(found).override_failure_message("mask %d" % mask).is_empty()
		assert_int(rig.tally()[&"hits"]).is_greater(FLOOR_SCATTER_HITS)
		assert_int(rig.tally()[&"other_layer"]).is_greater(FLOOR_SCATTER_OTHER)


## Aircraft over rock, a column closed to tracked rows ('w') and a footprint, the ground rows round
## them: the same orders on both
## sides. The twin's aircraft never ask for a flow field and reach the goal, while each ground row
## has one at some tick and never stands on the wall; the lockstep holds the kernels to every
## position, goal, mode, field slot and the flow cache after each tick. The floors are about two
## thirds of the twin's tally (see the figures at the assertions).
func test_aircraft_cross_rock_and_a_footprint_in_a_straight_line() -> void:
	for mask: int in [Rig.WITH_INTEGRATE, Rig.ALL]:
		var rig: RefCounted = Rig.new().setup(_crossing, mask)
		assert_array(rig.problems).is_empty()
		var world: World = rig.worlds[0]
		var flyers: PackedInt32Array = _rows_of(world, [Layers.JET, Layers.BOMBER, Layers.DRONE])
		var walkers: PackedInt32Array = _rows_of(world, [Layers.GUN, Layers.SCOUT, Layers.RIFLE])
		assert_int(flyers.size()).is_equal(6)
		assert_int(walkers.size()).is_equal(3)
		# The first jet flies along row 6: rock at column 12, the footprint at column 18.
		var lead: int = flyers[0]
		var crossed_rock: bool = false
		var crossed_footprint: bool = false
		var asked: Dictionary[int, bool] = {}
		for _tick: int in MOVE_TICKS:
			assert_str(rig.step(_send_all)).is_empty()
			for row: int in flyers:
				assert_int(world.field[row]).override_failure_message("flyer %d" % row).is_equal(-1)
			for row: int in walkers:
				var on_x: int = world.pos_x[row] / World.MILLI_PER_TILE
				var on_y: int = world.pos_y[row] / World.MILLI_PER_TILE
				var closed_to: int = WATER if world.type_index[row] == Layers.GUN else WALL_LAST
				var on_wall: bool = on_x >= WALL_FIRST and on_x <= closed_to and on_y < WALL_ROWS
				(
					assert_bool(on_wall)
					. override_failure_message("walker %d on the wall" % row)
					. is_false()
				)
				asked[row] = asked.get(row, false) or world.field[row] >= 0
			var tile_x: int = world.pos_x[lead] / World.MILLI_PER_TILE
			var tile_y: int = world.pos_y[lead] / World.MILLI_PER_TILE
			crossed_rock = crossed_rock or (tile_x == 12 and tile_y == 6)
			crossed_footprint = crossed_footprint or (tile_x == 18 and tile_y == 6)
		assert_bool(crossed_rock).is_true()
		assert_bool(crossed_footprint).is_true()
		for row: int in flyers:
			assert_int(world.order[row]).is_equal(World.Order.IDLE)
			assert_int(absi(world.pos_x[row] - 26500)).is_less(2000)
		# The ground rows walked round the wall by the gap, by a flow field: they stand east of it.
		for row: int in walkers:
			(
				assert_bool(asked[row])
				. override_failure_message("walker %d had no field" % row)
				. is_true()
			)
			assert_int(world.pos_x[row]).is_greater((WALL_LAST + 1) * World.MILLI_PER_TILE)
		var tally: Dictionary[StringName, int] = rig.tally()
		assert_int(tally[&"other_layer"]).is_greater(FLOOR_CROSSING_OTHER)
		assert_int(tally[&"hits"]).is_greater(FLOOR_CROSSING_HITS)
		assert_int(tally[&"mixed"]).is_greater(FLOOR_CROSSING_MIXED)


## A ground rifle ordered to attack a drone that hovers over rock (P238's requirement, ADR 0036
## section 5). In every case the rifle never enters the wall and keeps its ATTACK order; the
## kernels agree with the twin after every tick.
## - The drone over the middle column (12500, 6500): all eight tiles round its own are rock, so the
##   field reaches no ground west of the wall and the rifle walks straight to the face, then the
##   slide stops it. A reach of 1500 never gets the drone in range (it stops 1,501 away), 2500 does.
## - The drone over the first rock column (11400, 6700): the field reaches the tile west of it,
##   whose next step is the key, blocked for the rifle, so `Movement.NO_NEXT` (twin `_refresh_next`,
##   kernel the same), first in tile column `WALL_FIRST - 1`. A reach of 300 and one of 420 (it ends
##   420.04 from the drone) hold there and never fire; 430 and 1000 take NO_NEXT, and their first
##   hit lands on a NO_NEXT tick (they fire from the key-blocked stop, at the rock).
func test_a_ground_row_locking_a_drone_over_rock_stops_at_the_rock() -> void:
	var middle: Vector2i = Vector2i(12500, 6500)
	var first: Vector2i = Vector2i(11400, 6700)
	# [reach, where the drone hovers, whether the rifle fires]
	var cases: Array = [
		[1500, middle, false],
		[2500, middle, true],
		[300, first, false],
		[420, first, false],
		[430, first, true],
		[1000, first, true],
	]
	for found: Array in cases:
		var reach: int = found[0]
		var label: String = "reach %d, drone %s" % [reach, found[1]]
		var rig: RefCounted = Rig.new().setup(_duel.bind(reach, found[1]), Rig.ALL)
		assert_array(rig.problems).is_empty()
		var world: World = rig.worlds[0]
		var held_column: int = -1
		var hit_held: bool = false
		var shooter: int = _rows_of(world, [Layers.RIFLE])[0]
		var drone: int = _drone_row(world)
		var max_hp: int = world.hp[drone]
		var first_hit: bool = true
		for _tick: int in DUEL_TICKS:
			assert_str(rig.step(_attack_drone)).override_failure_message(label).is_empty()
			var column: int = world.pos_x[shooter] / World.MILLI_PER_TILE
			var on_next: bool = world.nav_next[shooter] == Movement.NO_NEXT
			if on_next and held_column < 0:
				held_column = column
			if first_hit and world.hp[drone] < max_hp:
				first_hit = false
				hit_held = on_next
			assert_int(world.pos_x[shooter]).is_less(WALL_FIRST * World.MILLI_PER_TILE)
		assert_int(world.order[shooter]).override_failure_message(label).is_equal(
			World.Order.ATTACK
		)
		assert_bool(world.hp[drone] < max_hp).override_failure_message(label).is_equal(found[2])
		assert_bool(held_column >= 0).override_failure_message("never held: " + label).is_true()
		if found[1] == first:
			assert_int(held_column).override_failure_message(label).is_equal(WALL_FIRST - 1)
			if found[2]:
				assert_bool(hit_held).override_failure_message("first hit: " + label).is_true()
