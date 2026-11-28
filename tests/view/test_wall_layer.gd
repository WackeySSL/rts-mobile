extends GdUnitTestSuite
## `WallLayer` (ADR 0053 amendment A1 to A6, plan P656d2) on an 8 x 6 map (`wall_rig.gd`) with
## PLACEHOLDER pieces made in memory: the flag, the row nodes and their y, the pieces and their
## order, the sort keys, no material, the three fog states and their write bound, the fallback.
## Rock cells: (1, 1) (2, 1) (1, 2) (2, 2) a block, (0, 4) at the map's edge and (4, 4) alone.

const Rig: GDScript = preload("res://tests/view/support/wall_rig.gd")
const FogRig: GDScript = preload("res://tests/view/support/fog_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const BLOCK: Array[int] = [9, 10, 17, 18]  ## Cell indices, 8 wide.

var _runner: MatchRunner
var _sort: WorldSort
var _fog: FogLayer
var _layer: WallLayer


func before_test() -> void:
	MenuRig.begin()  # One test builds the main scene (test_menu_rig_scan).
	_runner = auto_free(MatchRunner.new())
	_runner.snapshot = Rig.snapshot(true)
	_sort = auto_free(WorldSort.new())
	add_child(_sort)
	_fog = auto_free(FogLayer.new())
	_fog.runner = _runner
	add_child(_fog)
	_fog.set_process(false)


func after_test() -> void:
	MenuRig.end()


func test_with_the_flag_off_there_is_no_wall_node_and_no_band() -> void:
	_make(false)
	_layer._process(0.0)
	assert_int(_sort.get_child_count()).is_equal(0)
	assert_int(_layer.row_count()).is_equal(0)
	assert_bool(_sort.wall_loader.is_valid()).is_false()
	assert_int(_sort.bake(null).wall_band_rows()).is_equal(0)


func test_one_row_node_per_diagonal_at_its_centre_y_under_the_sorted_world() -> void:
	_make(true)
	assert_int(_layer.row_count()).is_equal(4)  # d = 2, 3, 4 and 8.
	for d: int in [2, 3, 4, 8]:
		var row: Node2D = _layer.row_node(d)
		assert_object(row).is_not_null()
		assert_object(row.get_parent()).is_same(_sort)
		assert_float(row.position.y).is_equal((d + 1) * 16.0)
		assert_bool(row.y_sort_enabled).is_false()
	assert_int(_layer.row_node(3).get_child_count()).is_equal(6)
	assert_object(_layer.row_node(5)).is_null()


func test_a_cells_pieces_stand_at_its_centre_in_the_order_face_top_rim() -> void:
	_make(true)
	var inner: Array[Sprite2D] = _layer.sprites_of(9)  # (1, 1): no face, a top, the rim `n`.
	assert_int(inner.size()).is_equal(2)
	assert_str(_key_of(inner[0])).contains("wall_top")
	assert_str(_key_of(inner[1])).is_equal("rock/wall_rim/n")
	var front: Array[Sprite2D] = _layer.sprites_of(18)  # (2, 2): the face `s`, a top, no rim.
	assert_int(front.size()).is_equal(2)
	assert_str(_key_of(front[0])).is_equal("rock/wall_face/s")
	for sprite: Sprite2D in front:
		var centre: Vector2 = sprite.get_parent().position + sprite.position
		assert_that(centre).is_equal(IsoProjection.cell_centre_px(2, 2))
		assert_that(sprite.offset).is_equal(-Vector2(TerrainKitDef.WALL_ORIGIN))
		assert_that(sprite.scale).is_equal(Vector2(0.5, 0.5))


func test_a_wall_row_sorts_like_a_one_by_one_building_and_a_unit_at_the_same_key() -> void:
	_make(true)
	# A 1 x 1 building on cell (3, 0) and a unit on its centre both stand at the centre y of the
	# cell, which is the row node's y for diagonal 3; so does the wall row there.
	var building_y: float = IsoProjection.cell_centre_px(3, 0).y
	var unit_y: float = IsoProjection.ground_to_px(3500, 500).y
	assert_float(_layer.row_node(3).position.y).is_equal(building_y)
	assert_float(_layer.row_node(3).position.y).is_equal(unit_y)
	# What stands behind (the cell (1, 0), diagonal 1) sorts before, in front ((3, 1)) after.
	assert_float(IsoProjection.cell_centre_px(1, 0).y).is_less(_layer.row_node(3).position.y)
	assert_float(IsoProjection.cell_centre_px(3, 1).y).is_greater(_layer.row_node(3).position.y)


func test_every_wall_sprite_shows_a_region_of_the_sorted_page_and_has_no_material() -> void:
	_make(true)
	var atlas: IsoAtlas = _sort.atlas
	for cell: int in BLOCK + [32, 36]:
		for sprite: Sprite2D in _layer.sprites_of(cell):
			assert_object(sprite.texture).is_same(atlas.texture(IsoAtlas.PAGE_SORTED))
			assert_object(sprite.material).is_null()
			assert_bool(sprite.region_enabled).is_true()
			assert_bool(sprite.region_rect.has_area()).is_true()
			assert_bool(sprite.visible).is_true()  # The fog sees every cell: all lit.


func test_the_three_fog_states_are_baked_copies_switched_by_region_writes() -> void:
	_runner.snapshot = Rig.snapshot(false, 2)
	_make(true)  # The fog layer rebuilt: nothing seen, so every wall is hidden.
	for cell: int in BLOCK:
		assert_int(_layer.state_of(cell)).is_equal(WallLayer.State.HIDDEN)
		for sprite: Sprite2D in _layer.sprites_of(cell):
			assert_bool(sprite.visible).is_false()
	var one: Array[Vector2i] = [Vector2i(2, 2)]
	FogRig.flip(_runner.snapshot, 1, one, true)
	_runner.ticked.emit(_runner.snapshot.tick)
	assert_int(_layer.state_of(18)).is_equal(WallLayer.State.LIT)
	var lit: Sprite2D = _layer.sprites_of(18)[0]
	assert_that(lit.region_rect).is_equal(Rect2(_sort.atlas.wall_region(_key_of(lit), false)))
	FogRig.flip(_runner.snapshot, 1, one, false)
	_runner.ticked.emit(_runner.snapshot.tick)
	assert_int(_layer.state_of(18)).is_equal(WallLayer.State.DIM)
	assert_that(lit.region_rect).is_equal(Rect2(_sort.atlas.wall_region(_key_of(lit), true)))
	assert_that(lit.region_rect).is_not_equal(Rect2(_sort.atlas.wall_region(_key_of(lit), false)))
	assert_bool(lit.visible).is_true()


func test_a_patch_of_k_wall_cells_writes_at_most_three_k_sprites() -> void:
	_runner.snapshot = Rig.snapshot(false, 2)
	_make(true)
	var before: int = _layer.write_count()
	# Two wall cells and four others flip in one tick.
	var flipped: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 0), Vector2i(5, 5)]
	FogRig.flip(_runner.snapshot, 1, flipped, true)
	_runner.ticked.emit(_runner.snapshot.tick)
	assert_int(_layer.write_count() - before).is_between(1, 3 * 2)
	# The same state again writes nothing.
	var again: int = _layer.write_count()
	FogRig.flip(_runner.snapshot, 1, flipped, true)
	_runner.ticked.emit(_runner.snapshot.tick)
	assert_int(_layer.write_count()).is_equal(again)
	assert_bool(_layer.is_wall(0)).is_false()  # A cell that is no wall has no state to write.


func test_a_look_without_wall_pieces_draws_no_wall() -> void:
	_make(true, Callable(self, "_no_pieces"))
	assert_int(_layer.row_count()).is_equal(0)
	assert_int(_sort.get_child_count()).is_equal(0)
	assert_int(_sort.atlas.wall_band_rows()).is_equal(0)


func test_the_standard_kit_has_every_wall_piece_so_the_loader_gives_all() -> void:
	_make(false)
	# P656d4 baked the standard kit's wall pieces: every key loads at the full wall canvas.
	var pieces: Dictionary[StringName, Image] = _layer.load_pieces(&"")
	assert_int(pieces.size()).is_equal(WallKit.all_keys().size())
	for key: StringName in WallKit.all_keys():
		assert_object(pieces.get(key)).override_failure_message(String(key)).is_not_null()


func test_a_map_version_with_the_same_rock_keeps_the_nodes_and_new_rock_rebuilds() -> void:
	_make(true)
	var row: Node2D = _layer.row_node(3)
	_runner.snapshot.map_version += 1  # A building went up: the terrain is as it was.
	_layer._process(0.0)
	assert_object(_layer.row_node(3)).is_same(row)
	_runner.snapshot.terrain[0] = 1  # A rock cell appears at (0, 0).
	_runner.snapshot.map_version += 1
	_layer._process(0.0)
	assert_bool(_layer.is_wall(0)).is_true()
	assert_object(_layer.row_node(0)).is_not_null()


func test_the_ghost_layer_draws_over_the_sorted_world() -> void:
	assert_int(GhostMemoryLayer.Z_GHOSTS).is_greater(WorldSort.Z_SORT)


func _make(on: bool, loader: Callable = Callable()) -> void:
	_layer = auto_free(WallLayer.new())
	_layer.runner = _runner
	_layer.world_sort = _sort
	_layer.fog = _fog
	_layer.walls_enabled = on
	_layer.loader = loader if loader.is_valid() else Callable(self, "_pieces")
	add_child(_layer)  # Sets the loader of the sorted world, which then bakes its band.
	_fog._process(0.0)
	_sort.bake(null)
	_layer._process(0.0)


func _pieces(_look: StringName) -> Dictionary[StringName, Image]:
	return Rig.pieces()


func _no_pieces(_look: StringName) -> Dictionary[StringName, Image]:
	return {}


## The kit key of the piece a sprite shows, found from its region on the lit band.
func _key_of(sprite: Sprite2D) -> String:
	for key: StringName in WallKit.all_keys():
		var region: Rect2i = _sort.atlas.wall_region(key, false)
		if Rect2(region) == sprite.region_rect:
			return String(key)
	for key: StringName in WallKit.all_keys():
		if Rect2(_sort.atlas.wall_region(key, true)) == sprite.region_rect:
			return String(key)
	return ""


func test_the_flag_is_off_in_the_main_scene_until_the_silhouettes_land() -> void:
	var main: Node = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	var layer: WallLayer = main.get_node("WallLayer") as WallLayer
	assert_object(layer).is_not_null()
	assert_bool(layer.walls_enabled).is_false()  # P656d3 turns it on, with the silhouettes.
