extends GdUnitTestSuite
## A terrain change during a match (plan P48): set_terrain's range guard, and a live change that
## MapView draws. The guard keeps `terrain` (one byte per cell) and the cost tables in step, so the
## view never meets an index it has no tile for. Colours are STYLE.md's, typed again here.

const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
## Indices into data/terrain/standard.tres.
const GRASS: int = 0
const SAND: int = 1
const ROCK: int = 3
const WATER: int = 4
const TILE: int = 8
## Texel (3, 3) of a tile: the base colour of every terrain (scrub has a bush near the middle).
const ROCK_HEX: String = "6E6A66"
const WATER_HEX: String = "2E5E7E"
const SAND_HEX: String = "CDB98F"
## Tiles of the controls map's test area, grass: x + y even and odd.
const EVEN_TILE: Vector2i = Vector2i(20, 22)
const ODD_TILE: Vector2i = Vector2i(21, 22)
const GRASS_HEX: String = "5E7D4A"
const GRASS_B_HEX: String = "6F8F57"


func after_test() -> void:
	CommandQueue.clear()


## `terrain` keeps a byte per cell, so an index above 255 would be stored as another terrain's and
## drawn as that one while move_cost took the cost of the index asked for. A world with 300 terrains
## (hand-built: no shipped set has more than five) refuses 256 and 299 and keeps 255.
func test_set_terrain_refuses_an_index_that_a_byte_cannot_hold() -> void:
	var world: World = World.new()
	world.map_w = 3000
	world.map_h = 1000
	world.prepare()
	var classes: int = World.MoveClass.size()
	world.terrain_cost = PackedByteArray()
	world.terrain_cost.resize(300 * classes)
	world.terrain_cost.fill(World.GRASS_COST)
	for move_class: int in classes:
		world.terrain_cost[255 * classes + move_class] = 0
		world.terrain_cost[256 * classes + move_class] = 0
		world.terrain_cost[299 * classes + move_class] = 0
	var costs: PackedByteArray = world.move_cost.duplicate()
	for refused: int in [256, 257, 299, 300, -1]:
		world.set_terrain(1, refused)
		assert_int(world.terrain[1]).override_failure_message(str(refused)).is_equal(0)
		assert_array(world.move_cost).override_failure_message(str(refused)).is_equal(costs)
		assert_int(world.map_version).override_failure_message(str(refused)).is_equal(0)
	world.set_terrain(1, World.TERRAIN_INDEX_MAX)
	assert_int(world.terrain[1]).is_equal(255)
	assert_bool(world.is_passable(1, World.MoveClass.TRACKED)).is_false()
	assert_int(world.map_version).is_equal(1)


## In a world from a scenario the terrain table, its ids and its costs are one table, so the bound
## of the cost rows is the bound of the ids and every terrain byte of the map has an id (and so a
## tile in the view).
func test_a_scenario_world_keeps_ids_costs_and_cell_bytes_in_one_table() -> void:
	for path: String in [SCENARIO_PATH, ARENA_PATH]:
		var world: World = World.from_scenario(load(path) as ScenarioDef)
		var classes: int = World.MoveClass.size()
		assert_int(world.terrain_ids.size()).is_equal(5)
		assert_int(world.terrain_cost.size()).is_equal(world.terrain_ids.size() * classes)
		assert_int(world.terrain.size()).is_equal(world.map_cols * world.map_rows)
		var top: int = 0
		for cell: int in world.terrain.size():
			top = maxi(top, world.terrain[cell])
		assert_int(top).override_failure_message(path).is_less(world.terrain_ids.size())
		# The first index past the table is refused, so the table stays closed.
		var version: int = world.map_version
		world.set_terrain(0, world.terrain_ids.size())
		assert_int(world.map_version).is_equal(version)
		assert_int(world.terrain[0]).is_less(world.terrain_ids.size())


## A set_terrain during a running match reaches the next snapshot, and MapView bakes and draws it:
## one more bake, still one draw command, and the changed tiles show their new terrain while the
## tiles next to them do not change.
func test_a_set_terrain_during_a_match_is_drawn_by_map_view() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(SCENARIO_PATH) as ScenarioDef
	runner.start()
	var view: MapView = auto_free(MapView.new())
	view.runner = runner
	add_child(view)
	runner.run_ticks(30)  # Mid-match, not at the start.
	await await_idle_frame()
	assert_int(view.bake_count()).is_equal(1)
	assert_str(_hex(view, EVEN_TILE)).is_equal(GRASS_HEX)
	assert_str(_hex(view, ODD_TILE)).is_equal(GRASS_B_HEX)
	var world: World = runner.world
	var tracked: int = World.MoveClass.TRACKED
	var rock_cell: int = EVEN_TILE.y * world.map_cols + EVEN_TILE.x
	var water_cell: int = ODD_TILE.y * world.map_cols + ODD_TILE.x
	assert_bool(world.is_passable(rock_cell, tracked)).is_true()
	world.set_terrain(rock_cell, ROCK)
	world.set_terrain(water_cell, WATER)
	assert_bool(world.is_passable(rock_cell, tracked)).is_false()
	runner.run_ticks(1)  # The view reads the snapshot, which shows the change from the next capture.
	await await_idle_frame()
	await await_idle_frame()
	assert_int(runner.snapshot.map_version).is_equal(2)
	assert_int(view.bake_count()).is_equal(2)
	assert_str(_hex(view, EVEN_TILE)).is_equal(ROCK_HEX)
	assert_str(_hex(view, ODD_TILE)).is_equal(WATER_HEX)
	assert_str(_hex(view, EVEN_TILE + Vector2i(0, 1))).is_equal(GRASS_B_HEX)  # Its neighbour.
	assert_int(view.draw_count()).is_equal(1)
	assert_that(view.drawn_rect()).is_equal(Rect2(0, 0, 48 * 64, 48 * 64))
	# A later change shows too: the water turns to sand, and a refused index changes nothing.
	world.set_terrain(water_cell, SAND)
	world.set_terrain(water_cell, 256)
	runner.run_ticks(1)
	await await_idle_frame()
	await await_idle_frame()
	assert_int(view.bake_count()).is_equal(3)
	assert_str(_hex(view, ODD_TILE)).is_equal(SAND_HEX)
	assert_str(_hex(view, EVEN_TILE)).is_equal(ROCK_HEX)


## The colour of texel (3, 3) of `tile`, as 6 upper-case hex digits, read from the CPU-side bake.
func _hex(view: MapView, tile: Vector2i) -> String:
	return view.image().get_pixelv(tile * TILE + Vector2i(3, 3)).to_html(false).to_upper()
