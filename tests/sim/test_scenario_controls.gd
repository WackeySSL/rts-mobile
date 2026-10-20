extends GdUnitTestSuite
## The controls scenario's map (plan P48): its rock, water and scrub stay out of the Phase 1 test
## area, and the phone check runs as a test: blue tanks sent across the south rock band drive round
## its end and fight the red group on the far side. Data units only, so the vision checks of
## P46b (authoring rule: a target inside sight_range) leave the fight as it is.

const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
const MAP_PATH: String = "res://data/maps/controls_test.tres"
const SEED: int = 42
## The Phase 1 test area, tiles x 6..37 and y 8..28.
const TEST_AREA: Rect2i = Rect2i(6, 8, 32, 21)
## The south band is rock in rows 33 and 34: columns 14 to 37 in row 33, 13 to 36 in row 34. A
## centre in those rows (y 33000 up to 35000) is west of column 14 or east of column 37, or it is
## on rock.
const BAND_FROM_Y: int = 33000
const BAND_TO_Y: int = 35000
const BAND_FROM_X: int = 14000
const BAND_TO_X: int = 38000
## A tap on the far side of the band, beside the red group at tiles (26..30, 40).
const FAR_SIDE: Vector2i = Vector2i(28500, 39500)
const TICKS: int = 400
## Blue's 30 tanks are ids 1-30; red's groups are ids 31-34, 35-37 and 38-40.
const BLUE_IDS: int = 30
const FIRST_FAR_RED: int = 38
const LAST_FAR_RED: int = 40


func test_the_map_has_rock_water_and_scrub_and_keeps_all_of_them_out_of_the_test_area() -> void:
	var map: MapDef = load(MAP_PATH) as MapDef
	var found: Dictionary[String, int] = {"#": 0, "~": 0, "^": 0}
	var inside: Array[Vector2i] = []
	for y: int in map.rows.size():
		for x: int in len(map.rows[y]):
			var symbol: String = map.rows[y][x]
			if symbol != "." and symbol != ":" and TEST_AREA.has_point(Vector2i(x, y)):
				inside.append(Vector2i(x, y))
			if found.has(symbol):
				found[symbol] += 1
	assert_array(inside).is_empty()
	for symbol: String in found:
		assert_int(found[symbol]).override_failure_message(symbol).is_greater(20)


func test_the_south_band_cuts_the_straight_line_from_the_blue_block_to_the_far_side() -> void:
	var world: World = _world()
	var tracked: int = World.MoveClass.TRACKED
	var block: Vector2i = Vector2i(12500, 21500)
	# The straight line is cut, and the band alone cuts a line that runs straight south across it.
	assert_bool(_clear(world, block, FAR_SIDE)).is_false()
	assert_bool(_clear(world, Vector2i(28500, 28500), Vector2i(28500, 38500))).is_false()
	# Both ends are open ground for the tanks, and so is the way round the band's west end.
	assert_bool(world.is_passable(world.cell_of(block.x, block.y), tracked)).is_true()
	assert_bool(world.is_passable(world.cell_of(FAR_SIDE.x, FAR_SIDE.y), tracked)).is_true()
	assert_bool(_clear(world, block, Vector2i(12500, 36500))).is_true()
	assert_bool(_clear(world, Vector2i(12500, 36500), FAR_SIDE)).is_true()


func test_tanks_sent_across_the_band_drive_round_it_and_fight_on_the_far_side() -> void:
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	var world: World = _world()
	var loop: MatchLoop = MatchLoop.create(scenario, SCENARIO_PATH, SEED, world)
	var ids: PackedInt32Array = PackedInt32Array(range(1, BLUE_IDS + 1))
	var tap: Array[Command] = [Command.attack_move(1, ids, FAR_SIDE.x, FAR_SIDE.y)]
	var none: Array[Command] = []
	var blocked: int = 0
	var in_band_rows: int = 0
	var beside_band: int = 0
	for tick: int in TICKS:
		loop.step(world, tap if tick == 0 else none)
		for row: int in world.unit_count():
			var x: int = world.pos_x[row]
			var y: int = world.pos_y[row]
			var move_class: int = world.type_move_class[world.type_index[row]]
			if not world.is_passable(world.cell_of(x, y), move_class):
				blocked += 1
			if world.owner[row] == 1 and y >= BAND_FROM_Y and y < BAND_TO_Y:
				in_band_rows += 1
				if x < BAND_FROM_X or x >= BAND_TO_X:
					beside_band += 1
	assert_int(blocked).is_equal(0)
	# Every tank that was in the band's rows was beside the band, and some were (the way round).
	assert_int(in_band_rows).is_greater(0)
	assert_int(beside_band).is_equal(in_band_rows)
	# All 30 stand south of the band, and the three red tanks there died. The other red groups never
	# saw a fight.
	var south: int = 0
	for id: int in range(1, BLUE_IDS + 1):
		var row: int = world.index_of(id)
		if row >= 0 and world.pos_y[row] >= BAND_TO_Y:
			south += 1
	assert_int(south).is_equal(BLUE_IDS)
	for id: int in range(FIRST_FAR_RED, LAST_FAR_RED + 1):
		assert_int(world.index_of(id)).override_failure_message(str(id)).is_equal(-1)
	for id: int in range(BLUE_IDS + 1, FIRST_FAR_RED):
		assert_int(world.index_of(id)).override_failure_message(str(id)).is_greater_equal(0)


## Whether the straight line between two points is open for tracked units.
func _clear(world: World, from: Vector2i, to: Vector2i) -> bool:
	return FixedMath.line_clear(world, from.x, from.y, to.x, to.y, World.MoveClass.TRACKED)


func _world() -> World:
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	return World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
