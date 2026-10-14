extends GdUnitTestSuite
## MapView (P36) on a 6 x 2 map of every terrain of data/terrain/standard.tres, baked at 8 texels
## per tile. Texels are read from image(), never from the ImageTexture (stale after update()). The
## colours are STYLE.md's, typed again here, so a wrong default in MapView fails.

const Gallery: GDScript = preload("res://game/view/art_gallery.gd")
const TERRAIN: String = "res://data/terrain/standard.tres"
## Columns: grass, sand, scrub, rock, water, grass. x + y is even at (0, 0) and odd at (0, 1), so
## both grass tones occur, and the second grass tile (5, 0) is odd too.
const ROWS: PackedStringArray = [".:^#~.", ".:^#~."]
const COLUMNS: Array[StringName] = [&"grass", &"sand", &"scrub", &"rock", &"water", &"grass"]
const TILE: int = 8
const GRASS: String = "5E7D4A"
## Per STYLE.md key: the tile (x, y), the probe texel (x, y) inside it and the colour.
const PROBES: Dictionary[StringName, Array] = {
	&"grass": [Vector2i(0, 0), Vector2i(3, 3), GRASS],
	&"grass_b": [Vector2i(0, 1), Vector2i(3, 3), "6F8F57"],
	&"sand": [Vector2i(1, 0), Vector2i(3, 3), "CDB98F"],
	&"scrub": [Vector2i(2, 0), Vector2i(6, 2), "4E5A3A"],
	&"scrub_b": [Vector2i(2, 0), Vector2i(2, 2), "6B7A4F"],
	&"scrub_c": [Vector2i(2, 0), Vector2i(4, 4), "8C9A6B"],
	&"rock": [Vector2i(3, 0), Vector2i(3, 3), "6E6A66"],
	&"rock_b": [Vector2i(3, 0), Vector2i(3, 0), "8C8782"],
	&"rock_c": [Vector2i(3, 0), Vector2i(7, 3), "4F4B48"],
	&"water": [Vector2i(4, 0), Vector2i(3, 3), "2E5E7E"],
	&"water_b": [Vector2i(4, 0), Vector2i(2, 2), "3C7396"],
}

var _runner: MatchRunner
var _view: MapView


func before_test() -> void:
	var map: MapDef = MapDef.new()
	map.rows = ROWS
	map.terrain = load(TERRAIN)
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map = map
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = scenario
	_runner.start()
	_view = _add_view()


func after_test() -> void:
	CommandQueue.clear()


func test_map_rect_is_columns_times_rows_times_64_and_empty_without_a_runner() -> void:
	assert_that(_view.map_rect_px()).is_equal(Rect2i(0, 0, 6 * 64, 2 * 64))
	assert_that(auto_free(MapView.new()).map_rect_px()).is_equal(Rect2i())


func test_the_bake_shows_every_key_of_the_style_table_at_its_probe_texel() -> void:
	assert_array(PROBES.keys()).has_size(11)
	for key: StringName in PROBES:
		var probe: Array = PROBES[key]
		assert_str(_hex(_view, probe[0], probe[1])).override_failure_message(str(key)).is_equal(
			probe[2]
		)


func test_there_is_no_grid_and_a_later_rect_wins_a_shared_texel() -> void:
	var base: Dictionary[Vector2i, String] = {
		Vector2i(0, 0): GRASS, Vector2i(0, 1): "6F8F57", Vector2i(1, 0): "CDB98F"
	}
	for tile: Vector2i in base:
		for texel: Vector2i in [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 3)]:
			assert_str(_hex(_view, tile, texel)).is_equal(base[tile])
	assert_str(_hex(_view, Vector2i(3, 0), Vector2i(7, 0))).is_equal("4F4B48")  # rock_c on rock_b.


func test_every_tile_equals_the_gallerys_texel_for_texel() -> void:
	for y: int in 2:
		for x: int in COLUMNS.size():
			var id: StringName = (
				&"grass_b" if COLUMNS[x] == &"grass" and (x + y) % 2 == 1 else COLUMNS[x]
			)
			var expected: Image = Gallery.tile_image(Gallery.TERRAIN_TILES[id])
			var tile: Image = _view.image().get_region(
				Rect2i(Vector2i(x, y) * TILE, Vector2i(8, 8))
			)
			(
				assert_bool(tile.get_data() == expected.get_data())
				. override_failure_message("tile %d,%d" % [x, y])
				. is_true()
			)


func test_the_texture_is_nearest_filtered_and_has_8_texels_per_tile() -> void:
	assert_int(_view.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_that(_view.image().get_size()).is_equal(Vector2i(6 * TILE, 2 * TILE))
	var wide: MapView = _make_view()
	wide.bake_px_per_tile = 16
	add_child(wide)
	assert_that(wide.image().get_size()).is_equal(Vector2i(96, 32))
	# Scrub's rects are doubled: 4,4,1,1 covers texels 8-9.
	assert_str(_hex(wide, Vector2i(2, 0), Vector2i(9, 9), 16)).is_equal("8C9A6B")


func test_one_bake_per_match_and_one_after_set_terrain_however_many_frames_pass() -> void:
	for _frame: int in 3:
		_runner.run_ticks(2)  # Ticks do not bake.
		await await_idle_frame()
	assert_int(_view.bake_count()).is_equal(1)
	_runner.start()  # A new match with the same map_version 0 is a new bake.
	await await_idle_frame()
	assert_int(_view.bake_count()).is_equal(2)
	_runner.world.set_terrain(0, 1)  # Two changes in one frame are one bake.
	_runner.world.set_terrain(1, 0)
	_runner.run_ticks(1)  # The view reads the snapshot, which shows a change from the next capture.
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_view.bake_count()).is_equal(3)
	assert_str(_hex(_view, Vector2i(0, 0), Vector2i(3, 3))).is_equal("CDB98F")  # Grass is now sand.
	assert_str(_hex(_view, Vector2i(1, 0), Vector2i(3, 3))).is_equal("6F8F57")  # Sand, now grass_b.
	assert_str(_hex(_view, Vector2i(0, 1), Vector2i(3, 3))).is_equal("6F8F57")  # Untouched.


func test_every_terrain_of_the_data_set_has_a_base_colour_and_a_tile() -> void:
	var terrains: TerrainSetDef = load(TERRAIN)
	assert_int(terrains.terrains.size()).is_equal(5)
	for def: TerrainDef in terrains.terrains:
		assert_bool(_view.colors.has(def.id)).override_failure_message(str(def.id)).is_true()
		assert_bool(_view.tiles.has(def.id)).override_failure_message(str(def.id)).is_true()


func test_a_missing_colour_or_tile_bakes_magenta_and_never_leaks_into_other_views() -> void:
	var broken: MapView = _make_view()
	broken.colors.erase(&"sand")
	broken.colors.erase(&"scrub_c")
	broken.tiles.erase(&"water")
	add_child(broken)
	assert_str(_hex(broken, Vector2i(1, 0), Vector2i(3, 3))).is_equal("FF00FF")  # No base colour.
	assert_str(_hex(broken, Vector2i(2, 0), Vector2i(4, 4))).is_equal("FF00FF")  # No highlight.
	assert_str(_hex(broken, Vector2i(2, 0), Vector2i(2, 2))).is_equal("6B7A4F")  # The bush stays.
	assert_str(_hex(broken, Vector2i(4, 0), Vector2i(3, 3))).is_equal("FF00FF")  # No water tile.
	var fresh: MapView = _add_view()  # Made after the erases: its dictionaries are its own.
	assert_str(_hex(fresh, Vector2i(1, 0), Vector2i(3, 3))).is_equal("CDB98F")
	assert_str(_hex(fresh, Vector2i(4, 0), Vector2i(3, 3))).is_equal("2E5E7E")
	assert_bool(_view.colors.has(&"sand") and _view.tiles.has(&"water")).is_true()


func test_a_later_match_without_a_map_or_of_another_size_is_drawn_for_itself() -> void:
	_restart(Vector2i.ZERO)  # No map: nothing of the last match is left.
	await await_idle_frame()
	assert_bool(_view.image().is_empty()).is_true()
	assert_that(_view.map_rect_px()).is_equal(Rect2i())
	await await_idle_frame()
	assert_int(_view.draw_count()).is_equal(0)
	assert_that(_view.drawn_rect()).is_equal(Rect2())
	_restart(Vector2i(4, 3))  # A map after none is drawn again.
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_view.draw_count()).is_equal(1)
	assert_that(_view.image().get_size()).is_equal(Vector2i(4, 3) * TILE)
	_restart(Vector2i(2, 5))  # Another size gets a new texture, not an update of the old one.
	await await_idle_frame()
	await await_idle_frame()
	assert_that(_view.image().get_size()).is_equal(Vector2i(2, 5) * TILE)
	assert_that(_view.drawn_rect()).is_equal(Rect2(0, 0, 2 * 64, 5 * 64))
	assert_int(_view.draw_count()).is_equal(1)


func test_the_map_is_one_draw_command_before_and_after_a_change() -> void:
	await await_idle_frame()
	assert_int(_view.draw_count()).is_equal(1)
	assert_that(_view.drawn_rect()).is_equal(Rect2(0, 0, 6 * 64, 2 * 64))  # Whole map, from 0,0.
	_runner.world.set_terrain(0, 3)
	_runner.run_ticks(1)  # The change reaches the snapshot at the next capture.
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_view.bake_count()).is_equal(2)  # The change was baked, and drawn once.
	assert_int(_view.draw_count()).is_equal(1)
	assert_int(auto_free(MapView.new()).draw_count()).is_equal(0)


func test_the_map_comes_from_the_snapshot_and_never_from_the_world() -> void:
	await await_idle_frame()
	assert_int(_view.bake_count()).is_equal(1)
	_runner.world = World.new()  # Test-only: an empty World where the match's was.
	await await_idle_frame()
	await await_idle_frame()
	assert_that(_view.map_rect_px()).is_equal(Rect2i(0, 0, 6 * 64, 2 * 64))
	assert_int(_view.bake_count()).is_equal(1)  # Nothing to bake again: same match, same version.
	assert_that(_view.drawn_rect()).is_equal(Rect2(0, 0, 6 * 64, 2 * 64))
	var late: MapView = _add_view()  # A view made after the swap bakes the map of the snapshot.
	assert_int(late.bake_count()).is_equal(1)
	assert_that(late.map_rect_px()).is_equal(Rect2i(0, 0, 6 * 64, 2 * 64))
	assert_that(late.image().get_size()).is_equal(Vector2i(6 * TILE, 2 * TILE))  # Not the World's.
	assert_str(_hex(late, Vector2i(1, 0), Vector2i(3, 3))).is_equal("CDB98F")  # Sand.


func test_a_view_with_no_runner_or_no_snapshot_bakes_nothing_until_it_has_one() -> void:
	var waiting: MatchRunner = auto_free(MatchRunner.new())  # Not started: no snapshot yet.
	waiting.scenario = _runner.scenario
	var bare: MapView = auto_free(MapView.new())  # No runner at all.
	var idle: MapView = auto_free(MapView.new())
	idle.runner = waiting
	for view: MapView in [bare, idle]:
		add_child(view)  # _ready()
		await await_idle_frame()
		assert_int(view.bake_count()).is_equal(0)
		assert_bool(view.image().is_empty()).is_true()
		assert_that(view.map_rect_px()).is_equal(Rect2i())
		assert_int(view.draw_count()).is_equal(0)
	waiting.start()
	await await_idle_frame()
	assert_int(idle.bake_count()).is_equal(1)
	assert_that(idle.map_rect_px()).is_equal(Rect2i(0, 0, 6 * 64, 2 * 64))
	assert_int(bare.bake_count()).is_equal(0)


func _make_view() -> MapView:
	var view: MapView = auto_free(MapView.new())
	view.runner = _runner
	return view


## A new match on an open-grass map of `size` tiles (no MapDef), in the same runner.
func _restart(size: Vector2i) -> void:
	_runner.scenario = ScenarioDef.new()
	_runner.scenario.map_size_tiles = size
	_runner.start()


func _add_view() -> MapView:
	var view: MapView = _make_view()
	add_child(view)
	return view


## The colour of `texel` inside `tile` (`px` texels a side), as 6 upper-case hex digits.
func _hex(view: MapView, tile: Vector2i, texel: Vector2i, px: int = TILE) -> String:
	return view.image().get_pixelv(tile * px + texel).to_html(false).to_upper()
