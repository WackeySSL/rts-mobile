extends GdUnitTestSuite
## A footprint stops units and nothing moves a building (plan row P71, ADR 0017 section 1), under
## both implementations: the units of one player are ordered onto the centres of three of its own
## buildings (no fights) for 900 ticks, a crowd of the widest radius that data allows (500) pushing
## at a 1x1, a 2x2 and a 3x3 building, and every tick no unit stands on a tile that costs 0 for its
## class while no building has moved or lost a hit point. Separation's rule (a pair is pushed when
## the units are closer than the sum of their radii; a building has radius 0) cannot reach a
## building: a unit outside its footprint is at least half a tile from its centre.

const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const TICKS: int = 900
const WIDEST: int = 500


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## The buildings' rows and their (x, y) at the start.
func _building_rows(world: World) -> Dictionary[int, Vector2i]:
	var found: Dictionary[int, Vector2i] = {}
	for row: int in world.unit_count():
		if world.type_speed[world.type_index[row]] == 0:
			found[row] = Vector2i(world.pos_x[row], world.pos_y[row])
	return found


@warning_ignore("integer_division")
func test_units_never_enter_a_footprint_and_no_building_moves_in_900_ticks(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = Worlds.open(16, 12)
	var tank: int = Worlds.type_of(world, "light_tank")
	var rifle: int = Worlds.type_of(world, "rifle_squad")
	world.type_radius[tank] = WIDEST
	world.type_radius[rifle] = WIDEST
	var hq: int = world.add_building(1, Worlds.type_of(world, "headquarters"), 6, 4)
	var turret: int = world.add_building(1, Worlds.type_of(world, "defence_turret"), 2, 8)
	var plant: int = world.add_building(1, Worlds.type_of(world, "power_plant"), 11, 8)
	var groups: Array[PackedInt32Array] = [
		PackedInt32Array(), PackedInt32Array(), PackedInt32Array()
	]
	for unit: int in 24:
		var type: int = rifle if unit % 3 == 2 else tank
		var id: int = world.add_unit(1, type, 500 + unit % 8 * 1900, 500 + unit / 8 * 400)
		groups[unit % 3].append(id)
	var targets: Array[Vector2i] = [
		Vector2i(7500, 5500), Vector2i(2500, 8500), Vector2i(12000, 9000)
	]
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.INTEGRATE)).is_empty()
	var loop: MatchLoop = MatchLoop.create(null, "", 0, world)
	var fixed: Dictionary[int, Vector2i] = _building_rows(world)
	var hits: Dictionary[int, int] = {}
	for row: int in fixed:
		hits[row] = world.hp[row]
	assert_array(fixed.keys()).is_equal([0, 1, 2])
	var near: int = 0
	for tick: int in TICKS:
		var orders: Array[Command] = []
		if tick % 300 == 0:  # Again after the stalls of the first order have ended it.
			for group: int in 3:
				var at: Vector2i = targets[group]
				orders.append(Command.move(1, groups[group], at.x, at.y))
		loop.step(world, orders)
		for row: int in world.unit_count():
			var cell: int = world.cell_of(world.pos_x[row], world.pos_y[row])
			if fixed.has(row):
				assert_vector(Vector2i(world.pos_x[row], world.pos_y[row])).is_equal(fixed[row])
				assert_int(world.hp[row]).is_equal(hits[row])
			else:
				var class_of: int = world.type_move_class[world.type_index[row]]
				var where: String = (
					"tick %d row %d at %d, %d" % [tick, row, world.pos_x[row], world.pos_y[row]]
				)
				(
					assert_bool(world.is_passable(cell, class_of))
					. override_failure_message(where)
					. is_true()
				)
		if tick == TICKS - 1:
			near = _units_at_a_wall(world, fixed)
	assert_array([hq, turret, plant]).is_equal([1, 2, 3])
	assert_int(world.unit_count()).is_equal(27)
	assert_int(near).override_failure_message("units at the walls").is_greater(5)


## How many mobile units stand within half a radius of a building's footprint edge (they pushed up
## to it).
func _units_at_a_wall(world: World, fixed: Dictionary[int, Vector2i]) -> int:
	var count: int = 0
	for row: int in world.unit_count():
		if fixed.has(row):
			continue
		for wall: int in fixed:
			var type: int = world.type_index[wall]
			var half_w: int = world.type_foot_w[type] * World.TILE_CENTRE
			var half_h: int = world.type_foot_h[type] * World.TILE_CENTRE
			var dx: int = maxi(absi(world.pos_x[row] - fixed[wall].x) - half_w, 0)
			var dy: int = maxi(absi(world.pos_y[row] - fixed[wall].y) - half_h, 0)
			if dx * dx + dy * dy <= WIDEST * WIDEST * 2:
				count += 1
				break
	return count


func test_a_unit_walks_round_a_building_that_stands_in_its_way(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = Worlds.open(14, 9)
	world.add_building(1, Worlds.type_of(world, "headquarters"), 3, 3)  # Tiles 3..5 and 3..5.
	var tank: int = Worlds.type_of(world, "light_tank")
	var row: int = world.index_of(world.add_unit(1, tank, 500, 4500))
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.INTEGRATE)).is_empty()
	var loop: MatchLoop = MatchLoop.create(null, "", 0, world)
	var orders: Array[Command] = [
		Command.move(1, PackedInt32Array([world.unit_id[row]]), 8500, 4500)
	]
	loop.step(world, orders)
	var detoured: bool = false
	for _tick: int in 300:
		loop.step(world, [] as Array[Command])
		detoured = detoured or world.pos_y[row] < 3000 or world.pos_y[row] >= 6000
	assert_bool(detoured).is_true()  # The straight line is blocked: it went north or south round.
	assert_int(world.pos_x[row]).is_between(8500 - 400, 8500 + 400)
	assert_int(world.pos_y[row]).is_between(4500 - 400, 4500 + 400)
