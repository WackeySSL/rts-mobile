extends GdUnitTestSuite
## Kestrel Flats, the map (plan row P79, ADR 0023 sections 6 and 11): 64 x 64 on the standard
## terrain set, the same after a half turn so that neither base has the better ground, a base in
## each of two opposite corners with two safe ore fields beside it, and two contested fields in the
## middle, each in a walled pocket whose two three-tile gaps are the vehicle chokepoints (and a
## scrub gap that only foot units cross). The view-only `field_kinds` name each field oil or gas,
## moving no digest. Reach is the sim's own: a finished FlowField over the World's `move_cost`,
## buildings in place.

const Rig: GDScript = preload("res://tests/sim/support/kestrel_rig.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const TERRAIN_PATH: String = "res://data/terrain/standard.tres"
const FOOT: int = World.MoveClass.FOOT
## The six ore fields in `ore_cell` order: player 1's north and west fields, the contested field in
## the north-east pocket and the one in the south-west pocket, then player 2's east and south fields
## (a half turn sends field k to field 5 - k).
const FIELD_CELLS: Array[int] = [12, 12, 16, 16, 12, 12]
const FIELD_KINDS: Array[String] = ["oil", "gas", "oil", "oil", "gas", "oil"]
const SAFE: Array[int] = [0, 1, 4, 5]
const CONTESTED: Array[int] = [2, 3]
## Each contested field's pocket: the two three-tile gaps (the vehicle chokepoints) and the scrub
## gap (foot only), as tile rectangles. The pocket of field 3 is the half turn of field 2's.
const GAPS: Dictionary[int, Array] = {
	2: [Rect2i(38, 20, 2, 3), Rect2i(44, 26, 3, 2)],
	3: [Rect2i(24, 41, 2, 3), Rect2i(17, 36, 3, 2)],
}
const SCRUB_GAP: Dictionary[int, Rect2i] = {2: Rect2i(42, 16, 2, 2), 3: Rect2i(20, 46, 2, 2)}


func _map() -> MapDef:
	return load(Rig.MAP_PATH) as MapDef


func _cell(tile: Vector2i) -> int:
	return tile.y * Rig.SIZE + tile.x


## The World of `scenario` on `map`, made the way the runner makes it.
func _world_on(scenario: ScenarioDef, map: MapDef) -> World:
	var copy: ScenarioDef = scenario.duplicate() as ScenarioDef
	copy.map = map
	return World.from_scenario(copy, DetRandom.create(Rig.SEED, DetRandom.STREAM_SIM))


## `costs` with the tiles of every rectangle in `rects` closed to every class.
func _closed(world: World, rects: Array[Rect2i]) -> PackedByteArray:
	var cells: int = world.map_cols * world.map_rows
	var costs: PackedByteArray = world.move_cost.duplicate()
	for rect: Rect2i in rects:
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				for move_class: int in World.MoveClass.size():
					costs[move_class * cells + _cell(Vector2i(x, y))] = 0
	return costs


## Whether a field from the first cell of ore field `index` over `costs` reaches both bases' start
## tiles for `move_class`, as an array of the two answers.
func _reached_from_field(
	world: World, index: int, move_class: int, costs: PackedByteArray
) -> Array[bool]:
	var cells: PackedInt32Array = Rig.ore_fields(world)[index]
	var goal: Vector2i = Vector2i(cells[0] % Rig.SIZE, cells[0] / Rig.SIZE)
	var flow: FlowField = Rig.field(world, goal, move_class, costs)
	var answers: Array[bool] = []
	for player: int in [1, 2]:
		answers.append(Rig.reaches(flow, Rig.SIZE, Rig.start_tile(world, player)))
	return answers


func test_the_map_is_64_by_64_on_the_standard_terrain_and_validates() -> void:
	var map: MapDef = _map()
	assert_array(map.validate()).is_empty()
	assert_that(map.size_tiles()).is_equal(Vector2i(Rig.SIZE, Rig.SIZE))
	assert_str(map.terrain.resource_path).is_equal(TERRAIN_PATH)
	# Every terrain of the set is on the map: the ground, the scenery and the ore.
	var symbols: Dictionary[String, int] = {}
	for line: String in map.rows:
		for x: int in len(line):
			symbols[line[x]] = symbols.get(line[x], 0) + 1
	assert_array(symbols.keys()).contains_exactly_in_any_order([".", ":", "^", "#", "~", "o"])
	assert_int(symbols["o"]).is_equal(80)


func test_the_map_is_the_same_after_a_half_turn() -> void:
	var rows: PackedStringArray = _map().rows
	var odd: Array[Vector2i] = []
	for y: int in Rig.SIZE:
		for x: int in Rig.SIZE:
			if rows[y][x] != rows[Rig.SIZE - 1 - y][Rig.SIZE - 1 - x]:
				odd.append(Vector2i(x, y))
	assert_array(odd).is_empty()


func test_the_ore_is_six_fields_two_safe_ones_by_each_base_and_two_contested_ones() -> void:
	var world: World = Rig.world(Rig.SKIRMISH_PATH)
	var fields: Array[PackedInt32Array] = Rig.ore_fields(world)
	var sizes: Array[int] = []
	for cells: PackedInt32Array in fields:
		sizes.append(cells.size())
	assert_array(sizes).is_equal(FIELD_CELLS)
	assert_int(world.ore_cell.size()).is_equal(80)
	# The distance (the larger of the two tile differences) from each base's start tile to the
	# nearest tile of a field: a safe field is close to its own base and far from the other, a
	# contested one is far from both.
	var starts: Array[Vector2i] = [Rig.start_tile(world, 1), Rig.start_tile(world, 2)]
	for index: int in fields.size():
		var near: Array[int] = [999, 999]
		for cell: int in fields[index]:
			for side: int in 2:
				var apart: Vector2i = (
					(Vector2i(cell % Rig.SIZE, cell / Rig.SIZE) - starts[side]).abs()
				)
				near[side] = mini(near[side], maxi(apart.x, apart.y))
		var own: int = 0 if index < 3 else 1
		if SAFE.has(index):
			assert_int(near[own]).override_failure_message("field %d" % index).is_less(12)
			assert_int(near[1 - own]).override_failure_message("field %d" % index).is_greater(40)
		else:
			(
				assert_int(mini(near[0], near[1]))
				. override_failure_message("field %d" % index)
				. is_greater(25)
			)
	# A half turn sends each field to its partner, cell for cell.
	for index: int in fields.size():
		for cell: int in fields[index]:
			var turned: int = Rig.SIZE * Rig.SIZE - 1 - cell
			assert_bool(fields[5 - index].has(turned)).is_true()


func test_field_kinds_name_each_field_oil_or_gas_and_a_half_turn_keeps_the_kind() -> void:
	var kinds: PackedStringArray = _map().field_kinds
	assert_array(Array(kinds)).is_equal(FIELD_KINDS)
	for index: int in kinds.size():
		assert_str(kinds[index]).is_equal(kinds[kinds.size() - 1 - index])
	# Both kinds are on the map, and each base has one of each among its two safe fields.
	assert_array(Array(kinds)).contains(["oil", "gas"])
	assert_bool(kinds[0] != kinds[1]).is_true()
	assert_bool(kinds[4] != kinds[5]).is_true()
	assert_array(Array(MapDef.new().field_kinds)).is_empty()


## The view reads `field_kinds`; the loader never does. A scenario on a copy of the map without
## them, and one on a copy with every field gas, builds the same World: the map digest, the state
## hash, the defs hash and every member the lockstep diff lists. A copy with one tile of sand where
## the shipped map has grass is the control: its digest and state hash move.
func test_field_kinds_move_no_digest_and_no_hash() -> void:
	var scenario: ScenarioDef = load(Rig.SKIRMISH_PATH) as ScenarioDef
	var worlds: Array[World] = []
	var sets: Array[PackedStringArray] = [
		_map().field_kinds,
		PackedStringArray(),
		PackedStringArray(["gas", "gas", "gas", "gas", "gas", "gas"])
	]
	for kinds: PackedStringArray in sets:
		var map: MapDef = _map().duplicate() as MapDef
		map.field_kinds = kinds
		worlds.append(_world_on(scenario, map))
	assert_bool(sets[0] != sets[1] and sets[0] != sets[2]).is_true()
	for other: int in [1, 2]:
		assert_int(WorldHash.map_digest(worlds[other])).is_equal(WorldHash.map_digest(worlds[0]))
		assert_int(worlds[other].state_hash()).is_equal(worlds[0].state_hash())
		assert_int(worlds[other].defs_hash()).is_equal(worlds[0].defs_hash())
		assert_str(StateDiff.first(worlds[0], worlds[other])).is_empty()
	var changed: MapDef = _map().duplicate() as MapDef
	var rows: PackedStringArray = changed.rows.duplicate()
	rows[0] = ":" + rows[0].substr(1)
	changed.rows = rows
	var control: World = _world_on(scenario, changed)
	assert_int(WorldHash.map_digest(control)).is_not_equal(WorldHash.map_digest(worlds[0]))
	assert_int(control.state_hash()).is_not_equal(worlds[0].state_hash())


func test_every_base_reaches_every_ore_field_and_the_other_base_for_every_class() -> void:
	var world: World = Rig.world(Rig.SKIRMISH_PATH)
	var cells: int = world.map_cols * world.map_rows
	var starts: Array[Vector2i] = [Rig.start_tile(world, 1), Rig.start_tile(world, 2)]
	for move_class: int in Rig.CLASSES:
		for side: int in 2:
			var start: Vector2i = starts[side]
			assert_bool(world.is_passable(_cell(start), move_class)).is_true()
			var flow: FlowField = Rig.field(world, start, move_class)
			var lost: Array[Vector2i] = []
			for cell: int in world.ore_cell:
				var tile: Vector2i = Vector2i(cell % Rig.SIZE, cell / Rig.SIZE)
				if not Rig.reaches(flow, Rig.SIZE, tile):
					lost.append(tile)
			(
				assert_array(lost)
				. override_failure_message("class %d from base %d" % [move_class, side + 1])
				. is_empty()
			)
			assert_bool(Rig.reaches(flow, Rig.SIZE, starts[1 - side])).is_true()
	# Not vacuous: a field that cannot reach, because rock stands on the way, says so.
	var shut: PackedByteArray = world.move_cost.duplicate()
	for y: int in Rig.SIZE:
		for move_class: int in World.MoveClass.size():
			shut[move_class * cells + _cell(Vector2i(30, y))] = 0
	var cut: FlowField = Rig.field(world, starts[0], FOOT, shut)
	assert_bool(Rig.reaches(cut, Rig.SIZE, starts[1])).is_false()


## A contested field has two three-tile gaps for vehicles and a scrub gap for foot: with the two
## gaps shut, only foot reaches it (and it reaches both bases); with the scrub gap shut too, nobody
## does; with one gap shut, everybody still does.
func test_a_contested_field_is_behind_two_vehicle_chokepoints_and_a_foot_only_gap() -> void:
	var world: World = Rig.world(Rig.SKIRMISH_PATH)
	for index: int in CONTESTED:
		var gaps: Array[Rect2i] = []
		gaps.assign(GAPS[index])
		for gap: Rect2i in gaps:
			assert_int(maxi(gap.size.x, gap.size.y)).is_equal(3)
		var scrub: Array[Rect2i] = [SCRUB_GAP[index]]
		for move_class: int in Rig.CLASSES:
			var label: String = "field %d class %d" % [index, move_class]
			var open: Array[bool] = _reached_from_field(world, index, move_class, PackedByteArray())
			assert_array(open).override_failure_message(label).is_equal([true, true])
			for kept: int in 2:
				var one_shut: Array[Rect2i] = [gaps[1 - kept]]
				var one: Array[bool] = _reached_from_field(
					world, index, move_class, _closed(world, one_shut)
				)
				assert_array(one).override_failure_message(label).is_equal([true, true])
			var only_foot: bool = move_class == FOOT
			var two: Array[bool] = _reached_from_field(
				world, index, move_class, _closed(world, gaps)
			)
			assert_array(two).override_failure_message(label).is_equal([only_foot, only_foot])
			var all_three: Array[Rect2i] = gaps + scrub
			var none: Array[bool] = _reached_from_field(
				world, index, move_class, _closed(world, all_three)
			)
			assert_array(none).override_failure_message(label).is_equal([false, false])
		# The scrub gap costs foot units the grass price and every vehicle class nothing at all.
		var rect: Rect2i = SCRUB_GAP[index]
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				var costs: Array[int] = []
				for move_class: int in World.MoveClass.size():
					costs.append(
						world.move_cost[
							move_class * world.map_cols * world.map_rows + _cell(Vector2i(x, y))
						]
					)
				assert_array(costs).is_equal([10, 0, 0])


## A pocket is a fixed shape: its two gaps are open grass for every class, so that the closing cases
## above close ground that was open.
func test_the_gaps_are_open_grass_for_every_class() -> void:
	var world: World = Rig.world(Rig.SKIRMISH_PATH)
	var cells: int = world.map_cols * world.map_rows
	for index: int in CONTESTED:
		var gaps: Array[Rect2i] = []
		gaps.assign(GAPS[index])
		for gap: Rect2i in gaps:
			for y: int in range(gap.position.y, gap.end.y):
				for x: int in range(gap.position.x, gap.end.x):
					for move_class: int in World.MoveClass.size():
						var cost: int = world.move_cost[move_class * cells + _cell(Vector2i(x, y))]
						assert_int(cost).override_failure_message("%d,%d" % [x, y]).is_equal(10)


## The dummy builds around its Headquarters by a spiral of at most `place_tries` tiles, so each base
## has room: buildable ground (grass and sand) all round, not only the footprint the scenario uses.
func test_each_base_has_room_to_build_the_whole_roster() -> void:
	var world: World = Rig.world(Rig.SKIRMISH_PATH)
	for player: int in [1, 2]:
		var origin: Vector2i = world.footprint_origin(Rig.building_rows(world, player)[0])
		var room: int = 0
		for y: int in range(maxi(origin.y - 10, 0), mini(origin.y + 13, Rig.SIZE)):
			for x: int in range(maxi(origin.x - 10, 0), mini(origin.x + 13, Rig.SIZE)):
				var kind: int = world.terrain[_cell(Vector2i(x, y))]
				room += world.terrain_buildable[kind]
		assert_int(room).override_failure_message("base %d" % player).is_greater_equal(300)
