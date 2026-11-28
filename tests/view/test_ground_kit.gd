extends GdUnitTestSuite
## The ground on the terrain kit (plan P656d1, ADR 0053 section 7 and amendment A2): a `Base` and an
## `Edge` layer at scale 0.5 on the kit page, every piece exactly its 128 x 64 diamond, the writes
## bounded (every cell once, then the changed cell and its 8 neighbours), `covers_map()` and the SVG
## fallback for a terrain or a look the kit has no pieces for. Rock is flat: no lip is drawn.

const Rig: GDScript = preload("res://tests/view/support/ground_rig.gd")
const KIT: String = "res://assets/art/terrain/kit.tres"
const MAPS: Array[String] = [
	"kestrel_flats", "curlew_crags", "heron_fords", "tutorial_basics", "tutorial_drills"
]
const ORE: int = 5  ## Its index in the standard terrain set.
const PAGE_ROWS: int = 512
const TILE: Vector2i = Vector2i(128, 64)

var _runner: MatchRunner
var _ground: GroundLayer


func before_test() -> void:
	_runner = auto_free(Rig.runner(Rig.scenario()))
	_ground = _add_ground(_runner, load(KIT) as TerrainKitDef)


func after_test() -> void:
	CommandQueue.clear()


func test_the_kit_layers_draw_128_by_64_pieces_at_half_size_before_the_fields() -> void:
	assert_that(_ground.base_layer().scale).is_equal(Vector2(0.5, 0.5))
	assert_that(_ground.edge_layer().scale).is_equal(Vector2(0.5, 0.5))
	assert_that(_ground.base_layer().position).is_equal(Vector2.ZERO)
	var names: Array[String] = []
	for child: Node in _ground.get_children():
		names.append(String(child.name))
	assert_array(names).is_equal(["Base", "Edge", "Fields"])
	var tiles: TileSet = _ground.base_layer().tile_set
	assert_that(tiles.tile_size).is_equal(TILE)
	assert_int(tiles.tile_layout).is_equal(TileSet.TILE_LAYOUT_DIAMOND_DOWN)
	assert_object(_ground.edge_layer().tile_set).is_same(tiles)
	var source: TileSetAtlasSource = tiles.get_source(0) as TileSetAtlasSource
	assert_that(source.texture_region_size).is_equal(TILE)
	assert_object(source.texture).is_not_same(_ground.atlas().texture())  # The kit page is its own.


func test_a_cell_sits_where_the_old_ground_put_it() -> void:
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(3, 2), Vector2i(7, 5)]:
		var kit_at: Vector2 = _ground.base_layer().map_to_local(cell) * 0.5
		assert_that(kit_at).is_equal(_ground.map_to_local(cell))
		assert_that(_ground.edge_layer().map_to_local(cell)).is_equal(
			_ground.base_layer().map_to_local(cell)
		)


func test_every_cell_has_its_hashed_base_piece_and_the_svg_layer_is_empty() -> void:
	var kit: TerrainKitDef = load(KIT) as TerrainKitDef
	for row: int in Rig.ROW_COUNT:
		for col: int in Rig.COLS:
			var id: StringName = _id(col, row)
			var key: StringName = TerrainKit.base_key(kit, id, col, row)
			assert_str(key).is_not_empty()
			assert_that(_ground.base_layer().get_cell_atlas_coords(Vector2i(col, row))).is_equal(
				_ground.atlas().kit_coords(key)
			)
	assert_int(_ground.get_used_cells().size()).is_equal(0)
	assert_bool(_ground.covers_map()).is_true()


func test_the_edge_layer_draws_blends_and_shores_and_none_on_rock() -> void:
	var edge: TileMapLayer = _ground.edge_layer()
	# Row 0 is `.:^#~...`: grass (0, 0) has sand on its se edge; water (4, 0) has rock on its nw edge,
	# grass on its sw and se edges: three open edges take the first outer corner, outer_s.
	assert_that(_edge_key(0, 0)).is_equal(&"sand/blend/side_se")
	assert_that(_edge_key(4, 0)).is_equal(&"water/shore/outer_s")
	assert_that(_edge_key(3, 0)).is_equal(&"")  # Rock: flat, no lip.
	assert_that(_edge_key(7, 3)).is_equal(&"")  # Grass inside grass.
	for cell: Vector2i in edge.get_used_cells():
		var key: StringName = _key_of(edge.get_cell_atlas_coords(cell))
		assert_bool(String(key).begins_with("rock/")).override_failure_message(str(key)).is_false()
		assert_bool(_id(cell.x, cell.y) != &"rock").is_true()


func test_the_first_fill_writes_each_cell_once_and_a_quiet_frame_none() -> void:
	assert_int(_ground.write_count()).is_equal(48)
	var edges: int = _ground.edge_write_count()
	assert_int(edges).is_between(1, 48)
	assert_int(_ground.edge_layer().get_used_cells().size()).is_equal(edges)
	for _i: int in 3:
		await await_idle_frame()
	assert_int(_ground.write_count()).is_equal(48)
	assert_int(_ground.edge_write_count()).is_equal(edges)


func test_a_change_rewrites_the_changed_cell_and_at_most_its_eight_neighbours() -> void:
	var before: Dictionary[Vector2i, Vector2i] = _edge_state()
	var base: int = _ground.write_count()
	var edges: int = _ground.edge_write_count()
	_runner.world.set_terrain(3 * Rig.COLS + 5, ORE)  # (5, 3): grass becomes ore.
	_runner.run_ticks(1)
	await await_idle_frame()
	assert_int(_ground.write_count()).is_equal(base + 1)
	var written: int = _ground.edge_write_count() - edges
	assert_int(written).is_between(1, 9)
	var after: Dictionary[Vector2i, Vector2i] = _edge_state()
	for cell: Vector2i in after:
		if after[cell] != before.get(cell, Vector2i(-1, -1)):
			assert_int(maxi(absi(cell.x - 5), absi(cell.y - 3))).is_less_equal(1)
	assert_that(_edge_key(4, 3)).is_equal(&"ore/blend/side_se")  # West of it: it is on its se edge.
	# A bump that leaves the terrain as it is writes nothing.
	_runner.world.set_terrain(3 * Rig.COLS + 5, ORE)
	_runner.run_ticks(1)
	await await_idle_frame()
	assert_int(_ground.write_count()).is_equal(base + 1)
	assert_int(_ground.edge_write_count()).is_equal(edges + written)


func test_a_change_at_a_corner_touches_only_the_cells_on_the_map() -> void:
	var edges: int = _ground.edge_write_count()
	_runner.world.set_terrain(0, Rig.ROCK)  # (0, 0): the corner.
	_runner.run_ticks(1)
	await await_idle_frame()
	assert_int(_ground.edge_write_count() - edges).is_between(0, 4)
	assert_that(_edge_key(0, 0)).is_equal(&"")


func test_the_kit_page_is_at_most_512_rows_of_4096_and_every_piece_is_its_whole_diamond() -> void:
	var art: GroundAtlas = _ground.atlas()
	var page: Image = art.kit_image()
	assert_int(page.get_width()).is_equal(4096)
	assert_int(page.get_height()).is_less_equal(PAGE_ROWS)
	var kit: TerrainKitDef = load(KIT) as TerrainKitDef
	var count: int = 0
	for key: StringName in kit.pieces:
		var coords: Vector2i = art.kit_coords(key)
		if coords == Vector2i(-1, -1):
			continue
		count += 1
		assert_that(art.kit_region(key).size).override_failure_message(str(key)).is_equal(TILE)
		var source: TileSetAtlasSource = art.kit_tile_set.get_source(0) as TileSetAtlasSource
		assert_that(source.get_tile_texture_region(coords)).is_equal(art.kit_region(key))
	assert_int(count).is_greater(50)  # Bases, blends and shores of the six terrains; no lip, no road.
	assert_that(art.kit_coords(&"rock/lip/side_ne")).is_equal(Vector2i(-1, -1))


func test_a_piece_taller_than_its_diamond_keeps_the_diamond_at_its_foot() -> void:
	var art: GroundAtlas = _ground.atlas()
	var path: String = "res://assets/art/terrain/water_shore_outer_n.png"
	var source: Image = (load(path) as Texture2D).get_image()
	source.convert(Image.FORMAT_RGBA8)
	assert_int(source.get_height()).is_greater(64)  # The kit's one piece with rows above its diamond.
	var rise: int = source.get_height() - 64
	var cut: Image = source.get_region(Rect2i(0, rise, 128, 64))
	var on_page: Image = art.kit_image().get_region(art.kit_region(&"water/shore/outer_n"))
	assert_bool(on_page.get_data() == cut.get_data()).is_true()


func test_a_terrain_the_kit_lacks_keeps_its_svg_diamonds_and_the_map_stays_covered() -> void:
	var kit: TerrainKitDef = (load(KIT) as TerrainKitDef).duplicate()
	kit.pieces = kit.pieces.duplicate()
	kit.pieces.erase(&"water/base/2")
	var runner: MatchRunner = auto_free(Rig.runner(Rig.scenario()))
	var ground: GroundLayer = _add_ground(runner, kit)
	assert_bool(ground.atlas().kit_covers(&"water")).is_false()
	assert_bool(ground.atlas().kit_covers(&"grass")).is_true()
	assert_bool(ground.covers_map()).is_true()
	assert_that(Rig.key_at(ground, ground.atlas(), 4, 0)).is_equal(&"water_a")  # SVG diamond.
	assert_that(ground.base_layer().get_cell_atlas_coords(Vector2i(4, 0))).is_equal(
		Vector2i(-1, -1)
	)
	assert_that(Rig.key_at(ground, ground.atlas(), 0, 0)).is_equal(&"")  # Grass is on the kit.
	assert_int(ground.write_count()).is_equal(48)
	assert_that(ground.edge_layer().get_cell_atlas_coords(Vector2i(4, 0))).is_equal(
		Vector2i(-1, -1)
	)


func test_without_a_kit_the_layers_are_empty_and_the_ground_is_the_svg_diamonds() -> void:
	var runner: MatchRunner = auto_free(Rig.runner(Rig.scenario()))
	var ground: GroundLayer = _add_ground(runner, null)
	assert_int(ground.write_count()).is_equal(48)
	assert_int(ground.get_used_cells().size()).is_equal(48)
	assert_int(ground.base_layer().get_used_cells().size()).is_equal(0)
	assert_int(ground.edge_write_count()).is_equal(0)
	assert_bool(ground.covers_map()).is_true()
	assert_that(ground.atlas().kit_image().get_size()).is_equal(Vector2i(0, 0))


func test_a_map_look_with_no_kit_of_its_own_uses_the_svg_diamonds() -> void:
	var scenario: ScenarioDef = Rig.scenario()
	scenario.map.ground_look = &"heron"
	var runner: MatchRunner = auto_free(Rig.runner(scenario))
	var ground: GroundLayer = _add_ground(runner, load(KIT) as TerrainKitDef)
	assert_int(ground.get_used_cells().size()).is_equal(48)
	assert_int(ground.base_layer().get_used_cells().size()).is_equal(0)
	assert_bool(ground.covers_map()).is_true()


func test_every_piece_on_every_shipped_map_is_its_128_by_64_diamond_and_no_rock_lip() -> void:
	var kit: TerrainKitDef = load(KIT) as TerrainKitDef
	var on_kit: int = 0
	for map_name: String in MAPS:
		var scenario: ScenarioDef = ScenarioDef.new()
		scenario.map = load("res://data/maps/%s.tres" % map_name)
		scenario.rules = load(Rig.RULES)
		var runner: MatchRunner = auto_free(Rig.runner(scenario))
		var ground: GroundLayer = _add_ground(runner, kit)
		await await_idle_frame()
		var cells: int = runner.snapshot.map_cols * runner.snapshot.map_rows
		assert_int(ground.write_count()).override_failure_message(map_name).is_equal(cells)
		assert_bool(ground.covers_map()).override_failure_message(map_name).is_true()
		if scenario.map.ground_look != &"":  # P656c2's looks have no kit yet: the SVG diamonds.
			assert_int(ground.base_layer().get_used_cells().size()).is_equal(0)
			continue
		on_kit += 1
		assert_int(ground.edge_write_count()).is_less_equal(cells)
		for layer: TileMapLayer in [ground.base_layer(), ground.edge_layer()]:
			for cell: Vector2i in layer.get_used_cells():
				var key: StringName = _key_of(
					layer.get_cell_atlas_coords(cell), ground.atlas(), kit
				)
				(
					assert_that(ground.atlas().kit_region(key).size)
					. override_failure_message("%s %s" % [map_name, key])
					. is_equal(TILE)
				)
				assert_bool(String(key).contains("/lip/")).is_false()
	assert_int(on_kit).is_greater(0)


func _add_ground(runner: MatchRunner, kit: TerrainKitDef) -> GroundLayer:
	var ground: GroundLayer = auto_free(GroundLayer.new())
	ground.runner = runner
	ground.kit = kit
	add_child(ground)
	return ground


## The terrain id of a cell of the fixture map.
func _id(col: int, row: int) -> StringName:
	var ids: Array[StringName] = [&"grass", &"sand", &"scrub", &"rock", &"water", &"ore"]
	return ids[".:^#~o".find(Rig.ROWS[row][col])]


func _edge_key(col: int, row: int) -> StringName:
	return _key_of(_ground.edge_layer().get_cell_atlas_coords(Vector2i(col, row)))


## The kit key whose tile is at `coords`, "" for none.
func _key_of(
	coords: Vector2i, art: GroundAtlas = _ground.atlas(), kit: TerrainKitDef = null
) -> StringName:
	if coords == Vector2i(-1, -1):
		return &""
	for key: StringName in (load(KIT) as TerrainKitDef if kit == null else kit).pieces:
		if art.kit_coords(key) == coords:
			return key
	return &""


func _edge_state() -> Dictionary[Vector2i, Vector2i]:
	var state: Dictionary[Vector2i, Vector2i] = {}
	for row: int in Rig.ROW_COUNT:
		for col: int in Rig.COLS:
			state[Vector2i(col, row)] = _ground.edge_layer().get_cell_atlas_coords(
				Vector2i(col, row)
			)
	return state
