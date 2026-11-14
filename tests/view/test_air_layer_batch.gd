extends GdUnitTestSuite
## The air layer's draw calls and its page (plan P243, ADR 0036 section 15: "+2 draw calls on the
## forecast"). Every sprite a flyer's rig draws is a region of the atlas's second page, in white,
## with no material: the hulls at z 20 are one call and the shadows at z 2 another, whatever the
## mix of types and owners. `IsoAtlas.page_of` is keyed by the part and by whether the sheet is an
## aircraft's, so a flyer's `hull` is on page 2 while a tank's stays on page 1, and the sorted page
## does not grow with the flyers. The marker of a type with no art is the dev fallback and is hidden
## when there is art.

const Air: GDScript = preload("res://tests/view/support/air_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const SortedTextures: GDScript = preload("res://tests/view/support/sorted_textures.gd")

var _runner: MatchRunner
var _layer: AirLayer


func before_test() -> void:
	_runner = auto_free(Air.runner())
	_layer = auto_free(Air.layer(self, _runner))
	var tiles: Array = []
	for y: int in 32:
		for x: int in 32:
			tiles.append(Vector2i(x, y))
	Buildings.see(_runner.snapshot, 1, tiles)
	_layer._process(0.0)


func test_the_hulls_are_one_call_and_the_shadows_one_more() -> void:
	var page_two: Texture2D = _layer.world_sort.atlas.texture(IsoAtlas.PAGE_UNSORTED)
	assert_object(page_two).is_not_null()
	assert_object(page_two).is_not_same(_layer.world_sort.atlas.texture())
	var hulls: Array[Sprite2D] = []
	var shadows: Array[Sprite2D] = []
	for sprite: Sprite2D in _sprites():
		assert_object(sprite.material).is_null()
		assert_that(sprite.modulate).is_equal(Color.WHITE)
		assert_object(sprite.texture).is_same(page_two)
		match SortedTextures.resolved_z(sprite):
			AirLayer.Z_AIR:
				hulls.append(sprite)
			WorldSort.Z_SHADOW:
				shadows.append(sprite)
			_:
				fail("a flyer's sprite at z %d" % SortedTextures.resolved_z(sprite))
	assert_int(hulls.size()).is_equal(2)  # One call at z 20, one texture...
	assert_int(shadows.size()).is_equal(2)  # ... and one at z 2: the +2.
	for rig: AirLayer.Rig in _rigs():
		assert_bool(rig.marker.visible).is_false()  # No untextured draw beside them.


func test_nothing_of_the_air_layer_draws_at_the_sorted_z() -> void:
	assert_int(SortedTextures.sprites(_layer).size()).is_equal(0)


func test_a_flyers_whole_sheet_is_on_page_two_and_a_tanks_hull_on_page_one() -> void:
	assert_int(IsoAtlas.page_of(&"hull", true)).is_equal(IsoAtlas.PAGE_UNSORTED)
	assert_int(IsoAtlas.page_of(&"hull", false)).is_equal(IsoAtlas.PAGE_SORTED)
	assert_int(IsoAtlas.page_of(&"shadow", false)).is_equal(IsoAtlas.PAGE_UNSORTED)
	assert_bool(Air.sheet(Air.FIGHTER, &"fossil", true).flies()).is_true()
	assert_bool(Air.sheet(Air.DRONE, &"renew", false).flies()).is_true()
	assert_bool(IsoSheetDef.new().flies()).is_false()
	var atlas: IsoAtlas = _layer.world_sort.atlas
	var slot: int = _layer.world_sort.slot_of(1)
	var hull: int = atlas.base(Air.FIGHTER, &"hull", 6, slot)
	assert_object(atlas.texture_at(hull)).is_same(atlas.texture(IsoAtlas.PAGE_UNSORTED))
	var tank: int = atlas.base(&"light_tank", &"hull", 6, slot)
	assert_object(atlas.texture_at(tank)).is_same(atlas.texture())


func test_the_flyers_add_nothing_to_the_sorted_page() -> void:
	var fossil: IsoPlayerArt = IsoPlayerArt.make(&"fossil", _key(), _key())
	var ground: Array[IsoSheetDef] = []
	for sheet: IsoSheetDef in IsoAtlas.load_sheets():
		if sheet.art_id == &"light_tank":
			ground.append(sheet)
	assert_int(ground.size()).is_equal(1)
	var both: Array[IsoSheetDef] = ground.duplicate()
	both.append(Air.sheet(Air.FIGHTER, &"fossil", true))
	var players: Array[IsoPlayerArt] = [fossil]
	var before: Vector2i = IsoAtlas.planned_page(ground, players, 1.0)
	assert_that(IsoAtlas.planned_page(both, players, 1.0)).is_equal(before)
	var shadows: Vector2i = IsoAtlas.planned_page(ground, players, 1.0, Callable(), 1)
	assert_int(IsoAtlas.planned_page(both, players, 1.0, Callable(), 1).y).is_greater_equal(
		shadows.y
	)
	var atlas: IsoAtlas = _layer.world_sort.atlas  # The flyer's frames lie inside page 2.
	var region: Rect2i = atlas.region(Air.FIGHTER, &"hull", 6, _layer.world_sort.slot_of(1))
	assert_bool(region.has_area()).is_true()
	assert_int(region.end.y).is_less_equal(atlas.page_px(IsoAtlas.PAGE_UNSORTED).y)


func _key() -> PackedStringArray:
	return (load(WorldSort.FACTION_FILE % &"fossil") as FactionDef).key_triad


func _rigs() -> Array[AirLayer.Rig]:
	var found: Array[AirLayer.Rig] = []
	for id: int in [Air.FIGHTER_ID, Air.DRONE_ID]:
		found.append(_layer.rig_of(id))
	return found


## Every sprite under a flyer's rig that shows a region: the hulls and the shadows.
func _sprites() -> Array[Sprite2D]:
	var found: Array[Sprite2D] = []
	for rig: AirLayer.Rig in _rigs():
		for sprite: Sprite2D in [rig.hull, rig.shadow]:
			assert_bool(sprite.region_enabled).is_true()
			found.append(sprite)
	return found
