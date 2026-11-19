extends GdUnitTestSuite
## Fairness of the skirmish maps (plan rows P550, P552): every map is its own half turn, so the two
## seats get the same ground, the same ore fields (cells, yield and kind) and the same ground
## distances, all read from the map and the World the runner makes, never from literals. A new map
## adds one entry to CASES and nothing else. A river map also pins its crossings: the river is
## passable only at them, and both bases reach each other.

const Rig: GDScript = preload("res://tests/sim/support/kestrel_rig.gd")
const SCENARIO_SUFFIXES: Array[String] = ["", "_mirrored", "_fossil_mirror", "_renew_mirror"]
## Per map: the `map` path, the `stem` of its four scenario files (`<stem><suffix>.tres`) and
## `river_rows`, the first and last row of a river across the map (empty = no river) with the
## number of `crossings` every river row must have, each `crossing_width` tiles wide or more.
const CASES: Array[Dictionary] = [
	{
		"map": "res://data/maps/kestrel_flats.tres",
		"stem": "res://data/scenarios/skirmish_kestrel_flats",
		"river_rows": [],
	},
	{
		"map": "res://data/maps/heron_fords.tres",
		"stem": "res://data/scenarios/skirmish_heron_fords",
		"river_rows": [28, 31],
		"crossings": 2,
		"crossing_width": 5,
	},
]


func test_every_map_is_valid_and_its_own_half_turn() -> void:
	for spec: Dictionary in CASES:
		var map: MapDef = load(spec["map"] as String) as MapDef
		assert_array(map.validate()).is_empty()
		var size: Vector2i = map.size_tiles()
		assert_int(size.x).is_equal(size.y)
		for line: int in size.y:
			var turned: String = ""
			for column: int in size.x:
				turned += map.rows[size.y - 1 - line][size.x - 1 - column]
			assert_str(map.rows[line]).is_equal(turned)
		for path: String in _paths(spec):
			var scenario: ScenarioDef = load(path) as ScenarioDef
			assert_object(scenario.map).is_same(map)
			assert_that(scenario.map_size_tiles).is_equal(size)


func test_the_bases_are_half_turns_of_each_other() -> void:
	for spec: Dictionary in CASES:
		var size: int = (load(spec["map"] as String) as MapDef).size_tiles().x
		for path: String in _paths(spec):
			var world: World = Rig.world(path)
			var first: Array[Vector2i] = _centres(world, 1)
			var second: Array[Vector2i] = _centres(world, 2)
			assert_int(first.size()).is_equal(second.size())
			var turned: Array[Vector2i] = []
			for centre: Vector2i in first:
				turned.append(Vector2i(size * 1000 - centre.x, size * 1000 - centre.y))
			turned.sort_custom(_before)
			assert_array(second).is_equal(turned)
			# The footprints of the buildings turn into each other too, building by building.
			var rows_1: PackedInt32Array = Rig.building_rows(world, 1)
			var rows_2: PackedInt32Array = Rig.building_rows(world, 2)
			assert_int(rows_1.size()).is_equal(rows_2.size())
			assert_int(rows_1.size()).is_greater(0)
			var turned_origins: Array[Vector2i] = []
			var origins_2: Array[Vector2i] = []
			for at: int in rows_1.size():
				var type: int = world.type_index[rows_1[at]]
				var a: Vector2i = world.footprint_origin(rows_1[at])
				turned_origins.append(
					Vector2i(
						size - a.x - world.type_foot_w[type], size - a.y - world.type_foot_h[type]
					)
				)
				origins_2.append(world.footprint_origin(rows_2[at]))
			turned_origins.sort_custom(_before)
			origins_2.sort_custom(_before)
			assert_array(origins_2).is_equal(turned_origins)


func test_the_ore_fields_mirror_in_cells_yield_and_kind() -> void:
	for spec: Dictionary in CASES:
		var map: MapDef = load(spec["map"] as String) as MapDef
		var size: int = map.size_tiles().x
		var world: World = Rig.world(_paths(spec)[0])
		var fields: Array[PackedInt32Array] = Rig.ore_fields(world)
		assert_int(fields.size()).is_greater(1)
		assert_int(fields.size() % 2).is_equal(0)
		assert_int(map.field_kinds.size()).is_equal(fields.size())
		var yield_of: Dictionary[int, int] = _yield_by_cell(world)
		var partners: Dictionary[int, bool] = {}
		for index: int in fields.size():
			var partner: int = _field_of(fields, size * size - 1 - fields[index][0])
			assert_int(partner).is_not_equal(index)  # No field is its own half turn.
			assert_int(fields[partner].size()).is_equal(fields[index].size())
			assert_int(_yield_sum(fields[index], yield_of)).is_greater(0)
			assert_int(_yield_sum(fields[partner], yield_of)).is_equal(
				_yield_sum(fields[index], yield_of)
			)
			assert_str(map.field_kinds[partner]).is_equal(map.field_kinds[index])
			partners[partner] = true
			for cell: int in fields[index]:
				assert_bool(fields[partner].has(size * size - 1 - cell)).is_true()
		assert_int(partners.size()).is_equal(fields.size())


func test_the_ground_distances_from_the_real_starts_to_the_fields_mirror() -> void:
	for spec: Dictionary in CASES:
		_check_start_distances(spec)


## The distances of each seat's own starts (every mobile unit's tile and the ring around every
## building) to a field and to its half turn, read from the scenarios' own spawns.
func _check_start_distances(spec: Dictionary) -> void:
	var size: int = (load(spec["map"] as String) as MapDef).size_tiles().x
	for path: String in _paths(spec):
		var world: World = Rig.world(path)
		var fields: Array[PackedInt32Array] = Rig.ore_fields(world)
		for move_class: int in Rig.CLASSES:
			for index: int in fields.size():
				var flow_a: FlowField = _flow(world, fields[index][0], move_class)
				var flow_b: FlowField = _flow(world, size * size - 1 - fields[index][0], move_class)
				var one_to_f: Array[int] = _start_costs(world, 1, flow_a, size)
				var two_to_partner: Array[int] = _start_costs(world, 2, flow_b, size)
				assert_array(one_to_f).is_equal(two_to_partner)
				assert_array(_start_costs(world, 2, flow_a, size)).is_equal(
					_start_costs(world, 1, flow_b, size)
				)
				assert_int(one_to_f[one_to_f.size() - 1]).is_less(FlowField.UNREACHED)


## The costs of `player`'s starts in `flow`, sorted: one per mobile unit (its tile) and one per
## building (the cheapest tile of the ring around its footprint).
@warning_ignore("integer_division")
func _start_costs(world: World, player: int, flow: FlowField, size: int) -> Array[int]:
	var found: Array[int] = []
	for centre: Vector2i in _centres(world, player):
		found.append(_cost(flow, size, Vector2i(centre.x / 1000, centre.y / 1000)))
	for row: int in Rig.building_rows(world, player):
		var type: int = world.type_index[row]
		var origin: Vector2i = world.footprint_origin(row)
		var best: int = FlowField.UNREACHED
		for y: int in range(origin.y - 1, origin.y + world.type_foot_h[type] + 1):
			for x: int in range(origin.x - 1, origin.x + world.type_foot_w[type] + 1):
				if x < 0 or y < 0 or x >= size or y >= size:
					continue
				best = mini(best, _cost(flow, size, Vector2i(x, y)))
		found.append(best)
	found.sort()
	return found


func test_both_bases_reach_each_other_by_ground() -> void:
	for spec: Dictionary in CASES:
		var size: int = (load(spec["map"] as String) as MapDef).size_tiles().x
		for path: String in _paths(spec):
			var world: World = Rig.world(path)
			var one: Vector2i = _first_tile(world, 1)
			var two: Vector2i = _first_tile(world, 2)
			for move_class: int in Rig.CLASSES:
				var there: FlowField = Rig.field(world, two, move_class)
				var back: FlowField = Rig.field(world, one, move_class)
				assert_int(_cost(there, size, one)).is_not_equal(FlowField.UNREACHED)
				assert_int(_cost(back, size, two)).is_equal(_cost(there, size, one))


func test_a_river_is_passable_only_at_its_crossings() -> void:
	var checked: int = 0
	for spec: Dictionary in CASES:
		var span: Array = spec["river_rows"] as Array
		if span.is_empty():
			continue
		checked += 1
		var world: World = Rig.world(_paths(spec)[0])
		var cols: int = world.map_cols
		var cells: int = cols * world.map_rows
		var one: Vector2i = _first_tile(world, 1)
		var two: Vector2i = _first_tile(world, 2)
		var crossings: int = spec["crossings"] as int
		for move_class: int in Rig.CLASSES:
			var lines: Array[int] = []
			var runs: Array[Array] = []
			for line: int in range(span[0] as int, (span[1] as int) + 1):
				var found: Array[Vector2i] = _runs(world, move_class, line, cells)
				assert_int(found.size()).is_equal(crossings)
				for run: Vector2i in found:
					assert_int(run.y - run.x + 1).is_greater_equal(spec["crossing_width"] as int)
				lines.append(line)
				runs.append(found)
			# Closing every crossing cuts the bases apart; closing all but one leaves them joined.
			var shut: PackedByteArray = world.move_cost.duplicate()
			for kept: int in crossings:
				var one_open: PackedByteArray = world.move_cost.duplicate()
				for at: int in lines.size():
					for crossing: int in crossings:
						_close_run(shut, move_class, lines[at], runs[at][crossing], cells, cols)
						if crossing != kept:
							_close_run(
								one_open, move_class, lines[at], runs[at][crossing], cells, cols
							)
				var flow: FlowField = Rig.field(world, two, move_class, one_open)
				assert_int(_cost(flow, cols, one)).is_not_equal(FlowField.UNREACHED)
			var cut: FlowField = Rig.field(world, two, move_class, shut)
			assert_int(_cost(cut, cols, one)).is_equal(FlowField.UNREACHED)
	assert_int(checked).is_greater(0)


func _paths(spec: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for suffix: String in SCENARIO_SUFFIXES:
		found.append("%s%s.tres" % [spec["stem"], suffix])
	return found


static func _before(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


## The positions in milli-tiles of the mobile units of `player`, sorted.
func _centres(world: World, player: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_speed[world.type_index[row]] > 0:
			found.append(Vector2i(world.pos_x[row], world.pos_y[row]))
	found.sort_custom(_before)
	return found


## The tile of the first mobile unit of `player` (lowest position).
@warning_ignore("integer_division")
func _first_tile(world: World, player: int) -> Vector2i:
	var centres: Array[Vector2i] = _centres(world, player)
	return Vector2i(centres[0].x / 1000, centres[0].y / 1000)


@warning_ignore("integer_division")
func _flow(world: World, goal_cell: int, move_class: int) -> FlowField:
	var cols: int = world.map_cols
	return Rig.field(world, Vector2i(goal_cell % cols, goal_cell / cols), move_class)


func _cost(flow: FlowField, cols: int, tile: Vector2i) -> int:
	return flow.cost[(tile.y + 1) * (cols + FlowField.PAD) + tile.x + 1]


func _field_of(fields: Array[PackedInt32Array], cell: int) -> int:
	for index: int in fields.size():
		if fields[index].has(cell):
			return index
	return -1


func _yield_by_cell(world: World) -> Dictionary[int, int]:
	var found: Dictionary[int, int] = {}
	for at: int in world.ore_cell.size():
		found[world.ore_cell[at]] = world.ore_amount[at]
	return found


func _yield_sum(field: PackedInt32Array, yield_of: Dictionary[int, int]) -> int:
	var total: int = 0
	for cell: int in field:
		total += yield_of[cell]
	return total


## The runs (first column, last column) of tiles `move_class` can enter on map row `line`.
func _runs(world: World, move_class: int, line: int, cells: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var start: int = -1
	for column: int in world.map_cols + 1:
		var open: bool = (
			column < world.map_cols
			and world.move_cost[move_class * cells + line * world.map_cols + column] > 0
		)
		if open and start < 0:
			start = column
		elif not open and start >= 0:
			found.append(Vector2i(start, column - 1))
			start = -1
	return found


func _close_run(
	costs: PackedByteArray, move_class: int, line: int, run: Vector2i, cells: int, cols: int
) -> void:
	for column: int in range(run.x, run.y + 1):
		costs[move_class * cells + line * cols + column] = 0
