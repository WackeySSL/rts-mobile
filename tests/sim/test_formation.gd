extends GdUnitTestSuite
## Formation.assign (ADR 0003 section 4): lattice slots around the target, the r*r <= 2*K*K
## ring rule, map inset, greedy centre-out assignment and its tie rule, and from P37a that it
## prepares the world and gives Phase 1's slots on an open map. Hand-built worlds with literal
## stats, so no data file can agree with a wrong rule by repeating it. The tile rules (blocked
## slots, a target on a blocked tile) are in test_formation_tiles.

const FormationV1: GDScript = preload("res://tests/sim/support/formation_v1.gd")
const SPACING: int = 1200
const RADIUS: int = 400
const MAP: int = 48000

var _world: World


func before_test() -> void:
	_world = _make_world(MAP)
	_add_type(_world, SPACING, RADIUS)


func test_one_unit_lands_on_the_target() -> void:
	var rows: PackedInt32Array = _add_block(_world, 1, 1, 5000, 5000, 0, 0)
	Formation.assign(_world, rows, 20000, 30000)
	assert_that(_goal(_world, 0)).is_equal(Vector2i(20000, 30000))


func test_thirty_units_take_the_thirty_nearest_lattice_points() -> void:
	var rows: PackedInt32Array = _add_block(_world, 30, 6, 8500, 18500, 1500, 0)
	Formation.assign(_world, rows, 30500, 21500)
	var offsets: Array[Vector2i] = _offsets(rows, Vector2i(30500, 21500))
	# 29 lattice points have i*i + j*j <= 9. The 30th is the first one at 10 in generation order.
	assert_int(_within(offsets, 9)).is_equal(29)
	assert_array(offsets).contains([Vector2i(-1, -3)])
	for a: int in rows.size():
		for b: int in range(a + 1, rows.size()):
			var gap: Vector2i = _goal(_world, a) - _goal(_world, b)
			assert_int(gap.x * gap.x + gap.y * gap.y).is_greater_equal(SPACING * SPACING)


## K = 3 holds 49 points, and the 49 nearest are the ones with i*i + j*j <= 16. That reaches
## ring 4 at (+-4, 0) and (0, +-4), and leaves out the ring-3 corners at 18.
func test_forty_nine_units_reach_ring_four_and_skip_the_ring_three_corners() -> void:
	var rows: PackedInt32Array = _add_block(_world, 49, 7, 2500, 2500, 1500, 0)
	Formation.assign(_world, rows, 24000, 24000)
	var offsets: Array[Vector2i] = _offsets(rows, Vector2i(24000, 24000))
	assert_int(_distinct(offsets)).is_equal(49)
	assert_int(_within(offsets, 16)).is_equal(49)
	assert_array(offsets).contains(
		[Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4)]
	)
	assert_array(offsets).not_contains(
		[Vector2i(3, 3), Vector2i(-3, 3), Vector2i(3, -3), Vector2i(-3, -3)]
	)


func test_slots_near_a_corner_stay_inside_the_inset_map() -> void:
	var rows: PackedInt32Array = _add_block(_world, 30, 6, 8500, 18500, 1500, 0)
	for corner: int in [0, MAP]:
		Formation.assign(_world, rows, corner, corner)
		for row: int in rows:
			assert_int(_goal(_world, row).x).is_between(400, 47600)
			assert_int(_goal(_world, row).y).is_between(400, 47600)
		var clamped: Vector2i = Vector2i(400, 400) if corner == 0 else Vector2i(47600, 47600)
		var offsets: Array[Vector2i] = _offsets(rows, clamped)
		assert_int(_distinct(offsets)).is_equal(30)
		assert_array(offsets).contains([Vector2i.ZERO])


## A map that fits one slot: the leftover units get the clamped target, and nothing loops.
func test_units_without_a_slot_get_the_clamped_target() -> void:
	var small: World = _make_world(1000)
	_add_type(small, SPACING, RADIUS)
	var rows: PackedInt32Array = _add_block(small, 3, 3, 500, 500, 0, 0)
	Formation.assign(small, rows, 0, 0)
	for row: int in rows:
		assert_that(_goal(small, row)).is_equal(Vector2i(400, 400))
	small.goal_x[0] = 7
	Formation.assign(small, PackedInt32Array(), 0, 0)
	assert_int(small.goal_x[0]).is_equal(7)


## A map thinner than twice the radius: the inset is half the map on that axis, so the clamp
## range is never empty. x is clamped by the radius, y by half of 600. Only the j = 0 row fits.
func test_a_thin_map_limits_the_inset_to_half_the_map_on_each_axis() -> void:
	var thin: World = _make_world(MAP)
	thin.map_h = 600
	_add_type(thin, SPACING, RADIUS)
	var rows: PackedInt32Array = _add_block(thin, 3, 3, 100, 100, 0, 0)
	Formation.assign(thin, rows, 60000, 60000)
	assert_that(_goal(thin, 0)).is_equal(Vector2i(MAP - RADIUS, 300))
	assert_that(_goal(thin, 1)).is_equal(Vector2i(MAP - RADIUS - SPACING, 300))
	assert_that(_goal(thin, 2)).is_equal(Vector2i(MAP - RADIUS - 2 * SPACING, 300))


## Slot order is centre, (0,-1), (-1,0). Id 2 is nearest the target, id 3 is nearer the second
## slot than id 1 is (a tie would go to id 1). Id 4 is not in the group and keeps its goal.
func test_the_nearest_unit_takes_the_centre_slot_and_the_rest_follow_greedily() -> void:
	_world.add_unit(1, 0, 13500, 10000)
	_world.add_unit(1, 0, 10000, 10500)
	_world.add_unit(1, 0, 7000, 10000)
	_world.add_unit(1, 0, 20000, 20000)
	Formation.assign(_world, PackedInt32Array([0, 1, 2]), 10000, 10000)
	assert_that(_goal(_world, 1)).is_equal(Vector2i(10000, 10000))
	assert_that(_goal(_world, 2)).is_equal(Vector2i(10000, 8800))
	assert_that(_goal(_world, 0)).is_equal(Vector2i(8800, 10000))
	assert_that(_goal(_world, 3)).is_equal(Vector2i(20000, 20000))


## Offsets from the centre slot: unit 0 (1500, 3500), unit 1 (4500, 0), unit 2 (3400, 3400).
## Squared distance picks unit 0. Manhattan distance would pick unit 1, Chebyshev unit 2.
func test_the_centre_slot_goes_to_the_unit_nearest_by_squared_distance() -> void:
	_world.add_unit(1, 0, 11500, 13500)
	_world.add_unit(1, 0, 14500, 10000)
	_world.add_unit(1, 0, 13400, 13400)
	Formation.assign(_world, PackedInt32Array([0, 1, 2]), 10000, 10000)
	assert_that(_goal(_world, 0)).is_equal(Vector2i(10000, 10000))


func test_equal_distances_go_to_the_lower_id_whatever_the_list_order() -> void:
	_world.add_unit(1, 0, 11000, 10000)
	_world.add_unit(1, 0, 9000, 10000)
	for order: Array in [[0, 1], [1, 0]]:
		Formation.assign(_world, PackedInt32Array(order), 10000, 10000)
		assert_that(_goal(_world, 0)).is_equal(Vector2i(10000, 10000))
		assert_that(_goal(_world, 1)).is_equal(Vector2i(10000, 8800))


## Types 0 and 1 differ in spacing and radius. The middle unit has the largest of both, so
## taking the first, the last or the smallest value gives other goals.
func test_the_group_uses_its_largest_spacing_and_radius() -> void:
	_add_type(_world, 2000, 700)
	_world.add_unit(1, 0, 5000, 700)
	_world.add_unit(1, 1, 700, 5000)
	_world.add_unit(1, 0, 900, 800)
	Formation.assign(_world, PackedInt32Array([0, 1, 2]), 0, 0)
	assert_that(_goal(_world, 2)).is_equal(Vector2i(700, 700))
	assert_that(_goal(_world, 0)).is_equal(Vector2i(2700, 700))
	assert_that(_goal(_world, 1)).is_equal(Vector2i(700, 2700))


func test_the_same_input_gives_the_same_goals_in_any_list_order() -> void:
	var other: World = _make_world(MAP)
	_add_type(other, SPACING, RADIUS)
	var rows: PackedInt32Array = _add_block(_world, 30, 6, 8500, 18500, 1500, 0)
	_add_block(other, 30, 6, 8500, 18500, 1500, 0)
	var shuffled: PackedInt32Array = PackedInt32Array()
	for k: int in 30:
		shuffled.append(k * 7 % 30)
	Formation.assign(_world, rows, 30500, 21500)
	Formation.assign(other, shuffled, 30500, 21500)
	assert_array(other.goal_x).is_equal(_world.goal_x)
	assert_array(other.goal_y).is_equal(_world.goal_y)
	# A second call with the same input changes nothing, so no state is kept between calls.
	Formation.assign(_world, rows, 30500, 21500)
	assert_array(other.goal_x).is_equal(_world.goal_x)
	assert_array(other.goal_y).is_equal(_world.goal_y)


## P37a pin: an unprepared hand-built world (only the five Phase 1 type arrays) gets Phase 1's
## goals, and assign has prepared it: the type tables are padded to the types. A read of an
## unpadded `type_move_class` would be an out-of-bounds error line, which verify.sh fails.
func test_assign_prepares_an_unprepared_world_and_gives_phase_1_goals() -> void:
	var twin: World = _make_world(MAP)
	_add_type(twin, SPACING, RADIUS)
	var rows: PackedInt32Array = _add_block(_world, 30, 6, 8500, 18500, 1500, 0)
	_add_block(twin, 30, 6, 8500, 18500, 1500, 0)
	assert_bool(_world.prepared).is_false()
	assert_int(_world.type_move_class.size()).is_equal(0)
	Formation.assign(_world, rows, 30500, 21500)
	FormationV1.assign(twin, rows, 30500, 21500)
	assert_bool(_world.prepared).is_true()
	assert_int(_world.type_move_class.size()).is_equal(_world.type_ids.size())
	assert_array(_world.goal_x).is_equal(twin.goal_x)
	assert_array(_world.goal_y).is_equal(twin.goal_y)
	assert_int(_world.goal_x[0]).is_not_equal(8500)
	# Prepared once: a second call leaves the tables as they are.
	var padded: PackedInt32Array = _world.type_move_class.duplicate()
	Formation.assign(_world, rows, 20000, 20000)
	assert_array(_world.type_move_class).is_equal(padded)


## On an open map the slots are Phase 1's: random groups of 1 to 150 units of two types (spacing
## and radius differ), at random places and targets, also outside the map and on its edges, in a
## shuffled list order, against Phase 1's code on a twin world.
func test_on_an_open_map_the_slots_equal_phase_1s() -> void:
	var rng: DetRandom = DetRandom.create(37, 4)
	var sizes: Array[int] = [1, 2, 3, 7, 12, 30, 49, 75, 150]
	var wrong: Array[String] = []
	for case_index: int in 36:
		var count: int = sizes[case_index % sizes.size()]
		var worlds: Array[World] = [_make_world(MAP), _make_world(MAP)]
		var rows: PackedInt32Array = PackedInt32Array()
		for world: World in worlds:
			_add_type(world, SPACING, RADIUS)
			_add_type(world, 2000, 700)
		for k: int in count:
			var type: int = rng.next_int(2)
			var x: int = rng.range_int(0, MAP)
			var y: int = rng.range_int(0, MAP)
			for world: World in worlds:
				world.add_unit(1, type, x, y)
			rows.append(k)
		rng.shuffle(rows)
		var target: Vector2i = Vector2i(
			rng.range_int(-3000, MAP + 3000), rng.range_int(-3000, MAP + 3000)
		)
		Formation.assign(worlds[0], rows, target.x, target.y)
		FormationV1.assign(worlds[1], rows, target.x, target.y)
		if worlds[0].goal_x != worlds[1].goal_x or worlds[0].goal_y != worlds[1].goal_y:
			wrong.append("%d units to %s" % [count, target])
	assert_array(wrong).is_empty()


## P37a fix 1: the world is prepared first, also for an empty group, which returns right after.
func test_assign_prepares_the_world_for_an_empty_group_too() -> void:
	assert_bool(_world.prepared).is_false()
	Formation.assign(_world, PackedInt32Array(), 20000, 20000)
	assert_bool(_world.prepared).is_true()
	assert_int(_world.type_move_class.size()).is_equal(_world.type_ids.size())


## P37a fix 1: a world with no map (map_w = 0, so no tile grid) blocks no tile: the goals are the
## clamped target, with no read of a grid that is not there (an error line otherwise).
func test_assign_on_a_world_without_a_map_gives_the_clamped_target() -> void:
	var bare: World = World.new()
	_add_type(bare, SPACING, RADIUS)
	var rows: PackedInt32Array = _add_block(bare, 3, 3, 0, 0, 100, 0)
	Formation.assign(bare, rows, 5000, -7000)
	assert_int(bare.map_cols).is_equal(0)
	for row: int in rows:
		assert_that(_goal(bare, row)).is_equal(Vector2i(0, 0))


## ADR 0012 section 2, the alias rule: assign runs on the worker, where a per-row `world.pos_x[row]`
## read ran 1.8 times slower while the main thread moved rigs. The source reads no World member
## inside a loop or any other block: a line that names `world.` is at the top level of its function,
## which is where the columns are aliased into locals. This is the source scan of the rule; the
## behaviour cannot show it.
func test_formation_reads_no_world_member_inside_a_block() -> void:
	var source: String = FileAccess.get_file_as_string("res://game/sim/Formation.gd")
	assert_int(len(source)).is_greater(1000)
	var reads: int = 0
	var inside: Array[String] = []
	for line: String in source.split("\n"):
		if line.strip_edges().begins_with("#") or not "world." in line:
			continue
		reads += 1
		if line.begins_with("\t\t"):
			inside.append(line.strip_edges())
	assert_int(reads).is_greater(10)
	assert_array(inside).is_empty()


func _make_world(map: int) -> World:
	var world: World = World.new()
	world.map_w = map
	world.map_h = map
	return world


## Appends a type with the given stats. Its name is only a placeholder.
func _add_type(world: World, spacing: int, radius: int) -> void:
	world.type_ids.append(&"tank")
	world.type_speed.append(120)
	world.type_radius.append(radius)
	world.type_selection_radius.append(500)
	world.type_spacing.append(spacing)


## `count` units of type `type` on a grid, `columns` wide. Returns their rows.
@warning_ignore("integer_division")
func _add_block(
	world: World, count: int, columns: int, x: int, y: int, step: int, type: int
) -> PackedInt32Array:
	var rows: PackedInt32Array = PackedInt32Array()
	for k: int in count:
		world.add_unit(1, type, x + (k % columns) * step, y + (k / columns) * step)
		rows.append(world.unit_count() - 1)
	return rows


func _goal(world: World, row: int) -> Vector2i:
	return Vector2i(world.goal_x[row], world.goal_y[row])


## Each goal as a lattice offset (i, j) from `target`, so goal = target + (i, j) * SPACING.
@warning_ignore("integer_division")
func _offsets(rows: PackedInt32Array, target: Vector2i) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	for row: int in rows:
		var delta: Vector2i = _goal(_world, row) - target
		assert_that(delta % SPACING).is_equal(Vector2i.ZERO)
		offsets.append(delta / SPACING)
	return offsets


func _within(offsets: Array[Vector2i], limit: int) -> int:
	return offsets.filter(func(o: Vector2i) -> bool: return o.length_squared() <= limit).size()


func _distinct(offsets: Array[Vector2i]) -> int:
	var seen: Dictionary[Vector2i, bool] = {}
	for offset: Vector2i in offsets:
		seen[offset] = true
	return seen.size()
