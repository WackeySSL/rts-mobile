extends GdUnitTestSuite
## The page budget of the sorted world's atlas (plan P137, ADR 0027 section 4): with every life
## frame the page of a two-player match at bake scale 1.0 is at most 3584 px tall (7/8 of 4096),
## which leaves 512 rows for later types. It is computed with `IsoAtlas.planned_page` from the
## committed sheets and their files, with no raster, so every art row that adds frames (P139, P143,
## P153, P154) trips this test before it trips the bake scale. The cross-faction match is the
## largest; the two mirror matches must pass too. Each case prints its page, which the PR quotes.
## The pages of today are pinned too (`TODAY_*`): an art row that adds frames moves them, and
## updates them in the PR that changes them, so that the PR shows how much of the budget it spent.

const BUDGET_PX: int = 3584  ## 7/8 of the 4096 px page.
## The pages of the committed sheets, px tall (4096 wide), with the squads' walk and idle frames
## (P139; before them the pages were 2682, 2206 and 2226): P143 (and P153, P154) update these in the
## PR that changes them. The cross-faction page does not depend on the triads the two players wear
## (3066 for every pair of the eight); a mirror page can: Derrick's is 2524 when a player wears
## Signal, its key triad (the default match), 2516 when neither does (the slot names, which break
## ties between frames of one height, order the shelves).
const TODAY_CROSS: int = 3066
const TODAY_MIRROR_DERRICK: int = 2524
const TODAY_MIRROR_LUMEN: int = 2624
const CRAFTED: String = (
	'<svg xmlns="http://www.w3.org/2000/svg" width="8" height="4">'
	+ '<polygon points="0,0 8,0 8,4" fill="#E8681F"/></svg>'
)


func test_the_budget_is_seven_eighths_of_the_page() -> void:
	assert_int(BUDGET_PX).is_equal(3584)
	assert_int(BUDGET_PX).is_equal(IsoAtlas.PAGE_MAX_PX * 7 / 8)


func test_the_cross_faction_page_at_full_scale_is_within_the_budget() -> void:
	# The Derrick League and the Lumen Accord, each in its own key triad (ADR 0027 section 4).
	var players: Array[IsoPlayerArt] = [_key_art(&"fossil"), _key_art(&"renew")]
	var page: Vector2i = _page(players)
	_assert_within_budget("cross-faction", page)
	_assert_today("cross-faction", page, TODAY_CROSS)
	# Another pair of triads gives the same page: no frame is shared between two factions.
	var others: Array[IsoPlayerArt] = [_art(&"fossil", 2), _art(&"renew", 3)]
	assert_that(_page(others)).is_equal(page)


func test_the_derrick_league_mirror_page_is_within_the_budget() -> void:
	var players: Array[IsoPlayerArt] = [_art(&"fossil", 0), _art(&"fossil", 1)]
	var page: Vector2i = _page(players)
	_assert_within_budget("mirror Derrick", page)
	_assert_today("mirror Derrick", page, TODAY_MIRROR_DERRICK)
	var others: Array[IsoPlayerArt] = [_art(&"fossil", 2), _art(&"fossil", 3)]
	_assert_within_budget("mirror Derrick in other triads", _page(others))


func test_the_lumen_accord_mirror_page_is_within_the_budget() -> void:
	var players: Array[IsoPlayerArt] = [_art(&"renew", 0), _art(&"renew", 1)]
	var page: Vector2i = _page(players)
	_assert_within_budget("mirror Lumen", page)
	_assert_today("mirror Lumen", page, TODAY_MIRROR_LUMEN)


func test_a_set_of_frames_past_the_budget_is_seen() -> void:
	# A 16-frame part of 1000 x 500 px (the most the ADR allows an `anim`, on a canvas far bigger
	# than a real one) in two triads is 32 slots of 1004 x 504 cells, 4 to a 4096 shelf: 8 shelves,
	# 4032 px, which `_assert_within_budget` must fail on.
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.art_id = &"giant"
	sheet.faction = &"fossil"
	sheet.category = &"bld"
	sheet.parts = PackedStringArray(["anim"])
	sheet.counts = PackedInt32Array([1])
	sheet.frames = PackedInt32Array([16])
	sheet.sizes = PackedInt32Array([1000, 500])
	sheet.anchors = PackedInt32Array([0, 0])
	var players: Array[IsoPlayerArt] = [_art(&"fossil", 0), _art(&"fossil", 1)]
	var reader: Callable = func(_path: String) -> String: return CRAFTED  # A key colour in it.
	var page: Vector2i = IsoAtlas.planned_page([sheet], players, 1.0, reader)
	assert_int(page.y).is_equal(8 * (500 + 2 * RuntimeAtlas.GUTTER_PX))
	assert_int(page.y).is_greater(BUDGET_PX)
	assert_failure(func() -> void: _assert_within_budget("giant", page)).is_failed()
	assert_failure(func() -> void: _assert_today("giant", page, TODAY_CROSS)).is_failed()


## The page of the committed sheets for `players` at bake scale 1.0, nothing lowered.
func _page(players: Array[IsoPlayerArt]) -> Vector2i:
	return IsoAtlas.planned_page(IsoAtlas.load_sheets(), players, 1.0)


func _assert_within_budget(label: String, page: Vector2i) -> void:
	print("atlas page %s at bake scale 1.0: %dx%d, budget %d" % [label, page.x, page.y, BUDGET_PX])
	assert_int(page.x).is_equal(IsoAtlas.PAGE_MAX_PX)
	assert_int(page.y).is_greater(0)
	var why: String = (
		"%s page is %d px tall, past the budget of %d: cut frames or crop"
		% [label, page.y, BUDGET_PX]
	)
	assert_int(page.y).override_failure_message(why).is_less_equal(BUDGET_PX)


func _assert_today(label: String, page: Vector2i, want: int) -> void:
	var why: String = (
		"%s page is %d px tall, not the %d of before this change: update TODAY_* in this PR"
		% [label, page.y, want]
	)
	assert_int(page.y).override_failure_message(why).is_equal(want)


## The key triad of faction `faction`, as its `.tres` writes it.
func _key(faction: StringName) -> PackedStringArray:
	return (load(WorldSort.FACTION_FILE % faction) as FactionDef).key_triad


## A player of `faction` in its own key triad.
func _key_art(faction: StringName) -> IsoPlayerArt:
	return IsoPlayerArt.make(faction, _key(faction), _key(faction))


## A player of `faction` in triad number `triad` of the sorted world's table (player 1 the first).
func _art(faction: StringName, triad: int) -> IsoPlayerArt:
	return IsoPlayerArt.make(faction, _key(faction), PackedStringArray(WorldSort.TRIADS[triad]))
