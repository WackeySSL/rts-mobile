extends GdUnitTestSuite
## The perf arena and the per-match atlas (plan P113, ADR 0023 section 2): `_ready` bakes the atlas
## once, before the card's preflight (so the long frame lies in no timed window), and gives the
## card the bake time and the page; the default bake is both factions with two players at scale 1.
## The other arena suites replace the bake by an empty atlas (the rig); one case here runs the real
## one.

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


func test_the_default_bake_is_both_factions_for_two_players_at_scale_1() -> void:
	var arena: Node2D = auto_free(Rig.make(_calls))
	var atlas: IsoAtlas = arena._bake_atlas()
	assert_float(atlas.bake_scale()).is_equal(1.0)
	assert_int(atlas.page_px().x).is_equal(IsoAtlas.PAGE_MAX_PX)
	assert_int(atlas.page_px().y).is_between(1, IsoAtlas.PAGE_MAX_PX)
	# Player 0 the Derrick League, player 1 the Lumen Accord, each in its faction's own triad.
	assert_bool(atlas.region(&"headquarters", &"hull", -1, 0).has_area()).is_true()
	assert_bool(atlas.region(&"renew_hq", &"hull", -1, 1).has_area()).is_true()
	assert_bool(atlas.region(&"headquarters", &"hull", -1, 1).has_area()).is_false()
	assert_bool(atlas.region(&"renew_hq", &"hull", -1, 0).has_area()).is_false()
	assert_float(atlas.bake_ms()).is_greater(0.0)
