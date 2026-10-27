extends GdUnitTestSuite
## The ground (plan P116, ADR 0023 sections 1, 2 and 5): an isometric `TileMapLayer` of 64 x 32
## diamonds on one runtime page, the tile of a cell its terrain's `a` or `b` by `(column + row) %
## 2`, filled once per match and again only for the cells a `map_version` change touched, sitting
## where `IsoProjection.cell_centre_px` puts a cell, with the off-map colour as the clear colour.
## Texels come from `GroundAtlas.image()`, never from the texture, which reads back stale. The
## fields and the wellheads are test_field_layer.gd's; the scenes are test_ground_scenes.gd's.

const Rig: GDScript = preload("res://tests/view/support/ground_rig.gd")
const TerrainPage: GDScript = preload("res://game/view/art_gallery_ground.gd")
const IDS: Array[StringName] = [&"grass", &"sand", &"scrub", &"rock", &"water", &"ore"]
const CLEAR_SETTING: String = "rendering/environment/defaults/default_clear_color"

var _runner: MatchRunner
var _ground: GroundLayer


func before_test() -> void:
	_runner = auto_free(Rig.runner(Rig.scenario()))
	_ground = _add_ground(_runner)


func after_test() -> void:
	CommandQueue.clear()


func test_the_tile_set_is_a_64_by_32_isometric_diamond_layout_on_the_one_page() -> void:
	var tiles: TileSet = _ground.tile_set
	assert_int(tiles.tile_shape).is_equal(TileSet.TILE_SHAPE_ISOMETRIC)
	assert_int(tiles.tile_layout).is_equal(TileSet.TILE_LAYOUT_DIAMOND_DOWN)
	assert_that(tiles.tile_size).is_equal(Vector2i(64, 32))
	assert_int(tiles.get_source_count()).is_equal(1)
	var source: TileSetAtlasSource = tiles.get_source(0) as TileSetAtlasSource
	assert_object(source.texture).is_same(_ground.atlas().texture())  # One texture for the ground.
	assert_bool(source.use_texture_padding).is_false()  # The page's gutter does that job.
	assert_that(source.texture_region_size).is_equal(Vector2i(64, 32))
	assert_that(source.margins).is_equal(Vector2i(2, 2))
	assert_that(source.separation).is_equal(Vector2i(4, 4))
	assert_int(source.get_tiles_count()).is_equal(18)  # Twelve ground tiles and six field stages.
	for key: StringName in Rig.tile_keys():
		var at: Vector2i = _ground.atlas().coords(key)
		var rect: Rect2i = source.get_tile_texture_region(at)
		assert_that(rect).override_failure_message(str(key)).is_equal(_ground.atlas().region(key))


func test_every_tile_on_the_page_is_its_whole_imported_picture_with_nothing_trimmed() -> void:
	var page: Image = _ground.atlas().image()
	for key: StringName in Rig.tile_keys():
		var region: Rect2i = _ground.atlas().region(key)
		var picture: Image = (load(_path_of(key)) as Texture2D).get_image()
		picture.convert(Image.FORMAT_RGBA8)
		assert_that(region.size).override_failure_message(str(key)).is_equal(Vector2i(64, 32))
		(
			assert_bool(page.get_region(region).get_data() == picture.get_data())
			. override_failure_message(str(key))
			. is_true()
		)
	# The props are bigger than a tile and sit after the tiles, on a shelf of their own.
	assert_that(_ground.atlas().region(GroundAtlas.WELLHEAD).size).is_equal(Vector2i(56, 58))
	assert_that(_ground.atlas().region(GroundAtlas.WELLHEAD_SHADOW).size).is_equal(Vector2i(70, 36))
	assert_int(_ground.atlas().region(GroundAtlas.WELLHEAD).position.y).is_greater(
		_ground.atlas().region(&"grass_a").position.y
	)


func test_every_cells_tile_is_its_terrains_a_or_b_by_column_plus_row() -> void:
	var source: TileSetAtlasSource = _ground.tile_set.get_source(0) as TileSetAtlasSource
	var seen: Dictionary[StringName, bool] = {}
	for row: int in Rig.ROW_COUNT:
		for col: int in Rig.COLS:
			var symbol: String = Rig.ROWS[row][col]
			var id: StringName = IDS[".:^#~o".find(symbol)]
			var variant: String = "a" if (col + row) % 2 == 0 else "b"
			var key: StringName = StringName("%s_%s" % [id, variant])
			seen[key] = true
			assert_that(_key(col, row)).override_failure_message("%d,%d" % [col, row]).is_equal(key)
			assert_int(_ground.get_cell_source_id(Vector2i(col, row))).is_equal(0)
			assert_that(_ground.get_cell_atlas_coords(Vector2i(col, row))).is_equal(
				_ground.atlas().coords(key)
			)
			assert_bool(source.has_tile(_ground.atlas().coords(key))).is_true()
	# The small map shows both variants of grass and ore and one of each other terrain.
	assert_array(seen.keys()).contains_exactly_in_any_order(
		[&"grass_a", &"grass_b", &"ore_a", &"ore_b", &"sand_b", &"scrub_a", &"rock_b", &"water_a"]
	)
	assert_int(_ground.get_used_cells().size()).is_equal(Rig.COLS * Rig.ROW_COUNT)


func test_the_layer_sits_so_that_each_tile_is_its_cells_diamond() -> void:
	assert_that(_ground.position).is_equal(IsoProjection.TILE_LAYER_OFFSET)
	assert_int(_ground.z_index).is_equal(0)
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(7, 0), Vector2i(0, 5), Vector2i(7, 5)]:
		var centre: Vector2 = IsoProjection.cell_centre_px(cell.x, cell.y)
		assert_that(_ground.position + _ground.map_to_local(cell)).is_equal(centre)
		assert_that(_ground.local_to_map(centre - _ground.position)).is_equal(cell)


func test_the_first_fill_writes_each_cell_once_and_a_quiet_frame_none() -> void:
	assert_int(_ground.write_count()).is_equal(48)
	for _i: int in 3:
		await await_idle_frame()
	assert_int(_ground.write_count()).is_equal(48)
	assert_bool(_ground.covers_map()).is_true()


func test_a_map_version_change_rewrites_the_cells_that_changed_and_no_others() -> void:
	var before: int = _runner.snapshot.map_version
	_runner.world.set_terrain(0, Rig.ROCK)  # (0, 0): grass becomes rock.
	_runner.world.set_terrain(47, Rig.WATER)  # (7, 5): grass becomes water.
	_runner.run_ticks(1)
	await await_idle_frame()
	assert_int(_runner.snapshot.map_version).is_greater(before)
	assert_int(_ground.write_count()).is_equal(50)
	assert_that(_key(0, 0)).is_equal(&"rock_a")
	assert_that(_key(7, 5)).is_equal(&"water_a")  # 7 + 5 is even.
	assert_that(_key(1, 0)).is_equal(&"sand_b")  # A neighbour is as it was.
	# A bump that leaves the terrain as it is changes no cell.
	_runner.world.set_terrain(0, Rig.ROCK)
	_runner.run_ticks(1)
	await await_idle_frame()
	assert_int(_runner.snapshot.map_version).is_greater(before + 2)
	assert_int(_ground.write_count()).is_equal(50)
	# And a cell can change back: the tile follows the terrain, not the history.
	_runner.world.set_terrain(0, Rig.GRASS)
	_runner.run_ticks(1)
	await await_idle_frame()
	assert_int(_ground.write_count()).is_equal(51)
	assert_that(_key(0, 0)).is_equal(&"grass_a")


func test_a_new_match_clears_the_layer_and_fills_the_new_map_on_the_same_page() -> void:
	var page: GroundAtlas = _ground.atlas()
	_runner.scenario = Rig.scenario(PackedStringArray(["...", ".:."]))
	_runner.start()
	await await_idle_frame()
	assert_int(_ground.get_used_cells().size()).is_equal(6)
	assert_int(_ground.write_count()).is_equal(54)  # The 48 of the first match and the 6.
	assert_that(_key(1, 1)).is_equal(&"sand_a")
	assert_that(_key(7, 5)).is_equal(&"")  # Nothing is left of the first map.
	assert_object(_ground.atlas()).is_same(page)  # The same terrains: no new page.


func test_the_clear_colour_is_the_off_map_colour_while_the_layer_is_in_the_tree() -> void:
	assert_that(GroundLayer.OFF_MAP_COLOR).is_equal(TerrainPage.OFF_MAP_COLOR)
	assert_str(GroundLayer.OFF_MAP_COLOR.to_html(false).to_upper()).is_equal("16191D")
	assert_that(RenderingServer.get_default_clear_color()).is_equal(GroundLayer.OFF_MAP_COLOR)
	remove_child(_ground)
	assert_that(RenderingServer.get_default_clear_color()).is_equal(
		ProjectSettings.get_setting(CLEAR_SETTING, Color(0.3, 0.3, 0.3))
	)
	add_child(_ground)


func test_a_terrain_with_no_art_leaves_its_cells_empty_and_the_map_view_to_draw() -> void:
	var set_def: TerrainSetDef = TerrainSetDef.new()
	set_def.terrains.assign((load(Rig.TERRAIN) as TerrainSetDef).terrains)
	var lava: TerrainDef = TerrainDef.new()
	lava.symbol = "L"
	lava.id = &"lava"
	set_def.terrains.append(lava)
	var scenario: ScenarioDef = Rig.scenario(PackedStringArray(["..", ".L"]))
	scenario.map.terrain = set_def
	var runner: MatchRunner = auto_free(Rig.runner(scenario))
	var ground: GroundLayer = _add_ground(runner)
	assert_that(ground.atlas().coords(&"grass_a")).is_not_equal(Vector2i(-1, -1))
	assert_that(ground.atlas().coords(&"lava_a")).is_equal(Vector2i(-1, -1))
	assert_that(Rig.key_at(ground, ground.atlas(), 0, 0)).is_equal(&"grass_a")
	assert_that(Rig.key_at(ground, ground.atlas(), 1, 1)).is_equal(&"")  # The lava cell: no tile.
	assert_bool(ground.covers_map()).is_false()  # So the bake under it stays drawn.
	assert_bool(auto_free(GroundLayer.new()).covers_map()).is_false()  # And with no match.
	var view: MapView = auto_free(MapView.new())
	view.runner = runner
	view.ground = ground
	add_child(view)
	for _i: int in 2:
		await await_idle_frame()
	assert_int(view.draw_count()).is_equal(1)  # The map view draws what the ground cannot.
	var page: GroundAtlas = ground.atlas()
	runner.scenario = Rig.scenario()  # A match on the standard six terrains: a page of their own.
	runner.start()
	for _i: int in 2:
		await await_idle_frame()
	assert_object(ground.atlas()).is_not_same(page)
	assert_bool(ground.covers_map()).is_true()
	assert_int(view.draw_count()).is_equal(0)


func test_a_map_view_under_the_ground_does_not_draw_and_keeps_its_bake() -> void:
	var view: MapView = auto_free(MapView.new())
	view.runner = _runner
	view.ground = _ground
	add_child(view)
	for _i: int in 2:
		await await_idle_frame()
	assert_int(view.draw_count()).is_equal(0)
	assert_that(view.drawn_rect()).is_equal(Rect2())
	assert_int(view.bake_count()).is_equal(1)  # The bake stays: the minimap and P52 read it.
	assert_that(view.image().get_size()).is_equal(Vector2i(64, 48))
	assert_str(view.image().get_pixel(3, 3).to_html(false)).is_equal("5e7d4a")
	view.ground = null  # Without a ground the rect is drawn, as it was.
	for _i: int in 2:
		await await_idle_frame()
	assert_int(view.draw_count()).is_equal(1)
	assert_that(view.drawn_rect()).is_equal(Rect2(0, 0, 8, 6))


func _add_ground(runner: MatchRunner) -> GroundLayer:
	var ground: GroundLayer = auto_free(GroundLayer.new())
	ground.runner = runner
	add_child(ground)
	return ground


## The imported picture of a tile key: ground/<id>_<a|b>.svg or fields/<kind>_<stage>.svg.
func _path_of(key: StringName) -> String:
	var folder: String = (
		"fields" if String(key).begins_with("oil") or String(key).begins_with("gas") else "ground"
	)
	return "res://assets/art/svg/%s/%s.svg" % [folder, key]


## The key of the tile on cell (`col`, `row`) of the ground.
func _key(col: int, row: int) -> StringName:
	return Rig.key_at(_ground, _ground.atlas(), col, row)
