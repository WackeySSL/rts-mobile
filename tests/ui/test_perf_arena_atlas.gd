extends GdUnitTestSuite
## The perf arena and the per-match atlas (plan P113, ADR 0023 section 2): `_ready` bakes the atlas
## once, before the card's preflight (so the long frame lies in no timed window), and gives the
## card the bake time and the page; the default bake is the scenario's match (P114), its types for
## its two players, made by the sorted world that draws from it, at scale 1. The other arena
## suites replace the bake by an empty atlas (the rig); two cases here run the real one.

const Rig: GDScript = preload("res://tests/ui/support/arena_rig.gd")

var _calls: Array[String] = []
var _arenas: Array[Node2D] = []


func before_test() -> void:
	CommandQueue.clear()


func after_test() -> void:
	_arenas.reverse()  # Each arena restores the frame cap it found, the last in first out.
	for arena: Node2D in _arenas:
		if is_instance_valid(arena):
			Rig.close(self, arena)
	_arenas.clear()
	_calls.clear()
	CommandQueue.clear()


func test_ready_bakes_the_atlas_before_the_preflight_and_hands_the_card_its_numbers() -> void:
	var arena: Node2D = Rig.make(_calls)
	_arenas.append(arena)
	var baked: Array[IsoAtlas] = []
	arena.atlas_source = func() -> IsoAtlas:
		_calls.append("atlas")
		var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
		var sheets: Array[IsoSheetDef] = [index.sheet(&"headquarters")]
		var key: PackedStringArray = ArtPalette.KEYS[&"fossil"]
		var players: Array[IsoPlayerArt] = [IsoPlayerArt.make(&"fossil", key, key)]
		baked.append(IsoAtlas.build(sheets, players, 0.5))
		return baked[0]
	add_child(arena)
	assert_str(_calls[0]).is_equal("atlas")  # Before the self-check and the burst.
	(
		assert_bool(
			_calls.slice(1).any(func(call: String) -> bool: return call.begins_with("self_check"))
		)
		. is_true()
	)
	assert_object(arena.atlas).is_same(baked[0])
	var page: Vector2i = baked[0].page_px()
	assert_float(arena.hud.atlas_bake_ms).is_equal(baked[0].bake_ms())
	assert_str(arena.hud.atlas_page).is_equal("%dx%d at 0.500" % [page.x, page.y])
	assert_bool(page.x > 0 and page.y > 0).is_true()


func test_an_arena_that_bakes_nothing_reports_none() -> void:
	var arena: Node2D = Rig.open(self, _calls)
	_arenas.append(arena)
	assert_object(arena.atlas).is_not_null()
	assert_bool(arena.atlas.is_empty()).is_true()
	assert_float(arena.hud.atlas_bake_ms).is_equal(0.0)
	assert_str(arena.hud.atlas_page).is_equal("none")


func test_the_default_bake_is_the_scenarios_match_for_two_players_at_scale_1() -> void:
	var arena: Node2D = auto_free(Rig.make(_calls))
	var atlas: IsoAtlas = arena._bake_atlas()
	assert_float(atlas.bake_scale()).is_equal(1.0)
	assert_object(arena.world_sort.atlas).is_same(atlas)  # The sorted world draws from it.
	# The scenario lists no faction, so both players take the faction of their own units, the
	# Derrick League, in the first two triads: three types, two players.
	for art_id: StringName in [&"light_tank", &"rifle_squad", &"rocket_squad"]:
		for player: int in 2:
			assert_bool(atlas.region(art_id, &"hull", 6, player).has_area()).is_true()
			assert_bool(atlas.region(art_id, &"shadow", 6, player).has_area()).is_true()
	(
		assert_bool(
			atlas.region(&"light_tank", &"hull", 6, 0) != atlas.region(&"light_tank", &"hull", 6, 1)
		)
		. is_true()
	)
	assert_bool(atlas.region(&"headquarters", &"hull", -1, 0).has_area()).is_false()  # Not here.
	assert_bool(atlas.region(&"renew_tank", &"hull", 6, 1).has_area()).is_false()
	assert_float(atlas.bake_ms()).is_greater(0.0)
	assert_int(atlas.page_px().x).is_less_equal(IsoAtlas.PAGE_MAX_PX)


func test_the_match_start_draws_from_the_atlas_the_ready_baked_and_bakes_nothing_more() -> void:
	var arena: Node2D = Rig.make(_calls)
	_arenas.append(arena)
	arena.atlas_source = arena._bake_atlas  # The real bake, as the scene runs it.
	add_child(arena)
	var atlas: IsoAtlas = arena.atlas
	assert_bool(atlas.is_empty()).is_false()
	arena.unit_layer._process(0.0)  # The first frame of the match: its rigs are dressed.
	assert_object(arena.world_sort.atlas).is_same(atlas)
	assert_int(arena.unit_layer.rig_count()).is_equal(150)
	var hull: Sprite2D = arena.unit_layer.rig(0).get_node("Hull")
	assert_object(hull.texture).is_same(atlas.texture())
	assert_that(hull.modulate).is_equal(Color.WHITE)
