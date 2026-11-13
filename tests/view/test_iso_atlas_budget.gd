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
## (P139; before them the pages were 2682, 2206 and 2226) and the buildings' `anim` frames (P143;
## before them 3066, 2524 and 2624) and the damage patches at 75 % of both factions (P158a and
## P158b, ADR 0029; before them 3266, 2702 and 2894): P153 and P154 update these in the PR that
## changes them. The cross-faction page is 3550 for the default pair (Signal and Arktisk, the key
## triads) and 3558 for Karmin and Kobolt (`OTHER_TRIADS_PX` allows that); a mirror page can
## differ too: Derrick's is 3008 for the default match and other triads alike (the slot names, which
## break ties between frames of one height, order the shelves).
## P237 (ADR 0036 section 15, option a) moved every cast shadow, units' and buildings', to page 2
## (`IsoAtlas.PAGE_UNSORTED`): page 1 (the y-sorted world, the budget below) went from 3550, 3008
## and 3140 to the pins that follow, and page 2 holds the shadows (1040 rows in the cross-faction
## match). **Re-pin rule:** an art row that adds frames with a shadow (P236, P239b, P245, P245b,
## P249, P266, P279, P280, P291, P292, the flyers) moves both `TODAY_*` and `TODAY2_*` in its own
## PR; the polish rows P203 and P204 move `TODAY2_*` (and `TODAY_*` only if a model changes);
## P202 (it drops `dmg1`, a page-1 part) moves `TODAY_*` only. Both pages keep the 3584 budget;
## a page past it stops the row (ADR 0036 section 15: Michael allows 3840 on page 1 only if needed).
## P236 (the two space centres, Skyrig and Zenith: a 384 px hull each, a lift of 16 and 12 frames,
## a KRITISK patch and a shadow, no `dmg1`, ADR 0034) moved page 1 from 2659, 2542 and 2650 to the
## pins below (+334, +336, +260 rows) and page 2 from 1040, 566 and 622 (+76, +4, +12). The two
## buildings packed alone are 676 rows on page 1 and 202 on page 2: they share shelves with what
## was there. What page 1 has left against the 3584 budget is 591 rows on the cross-faction page,
## 706 on the Derrick League mirror and 674 on the Lumen Accord mirror.
## P202 (ADR 0034) dropped the 16 `dmg1` frames: page 1 went from 2993, 2878 and 2910 to the pins
## below (-141, -102 and -128 rows); page 2 is unchanged. What page 1 has left is now 732 rows on
## the cross-faction page, 808 on the Derrick League mirror and 802 on the Lumen Accord mirror.
const TODAY_CROSS: int = 2852  ## P202: 2993 - 141 (P236: 2659 + 334, two hulls, lifts, patches).
const TODAY_MIRROR_DERRICK: int = 2776  ## P202: 2878 - 102 (P236: 2542 + 336, the Skyrig).
## P202: 2910 - 128 (P236: 2650 + 260, the Zenith, its lift and patch, once per player).
const TODAY_MIRROR_LUMEN: int = 2782
## Page 2 (shadows only): no key colour in a shadow, so one slot for both players, and each shadow
## fits the free width of shelf 1; only the trailing shelf grows.
const TODAY2_CROSS: int = 1514  ## P203: 1116 + 398 (the pads widen every shadow frame).
const TODAY2_MIRROR_DERRICK: int = 704  ## P203: 570 + 134 (the pads; P236: 566 + 4).
const TODAY2_MIRROR_LUMEN: int = 814  ## P203: 634 + 180 (the pads; P236: 622 + 12).
const OTHER_TRIADS_PX: int = 40  ## How far another pair of triads may move the page.
const CRAFTED: String = (
	'<svg xmlns="http://www.w3.org/2000/svg" width="8" height="4">'
	+ '<polygon points="0,0 8,0 8,4" fill="#E8681F"/></svg>'
)

const CRAFTED_ROOT: String = "res://tests/crafted_damage"
const NEUTRAL_FRAME: String = (
	'<svg xmlns="http://www.w3.org/2000/svg" width="8" height="4">'
	+ '<polygon points="0,0 8,0 8,4" fill="#808080"/></svg>'
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
	# Another pair of triads gives a page of nearly the same height (the slot names break ties
	# between frames of one height, so the shelves can fall differently: 3402 for this pair too).
	var others: Array[IsoPlayerArt] = [_art(&"fossil", 2), _art(&"renew", 3)]
	var other: Vector2i = _page(others)
	_assert_within_budget("cross-faction in other triads", other)
	assert_int(absi(other.y - page.y)).is_less_equal(OTHER_TRIADS_PX)
	# Page 2, the shadows: the same budget, its own pin (P204's team pads make it triad-dependent).
	var second: Vector2i = _page(players, IsoAtlas.PAGE_UNSORTED)
	_assert_within_budget("cross-faction page 2", second)
	_assert_today("cross-faction page 2", second, TODAY2_CROSS)
	var other2: Vector2i = _page(others, IsoAtlas.PAGE_UNSORTED)
	_assert_within_budget("cross-faction page 2 in other triads", other2)
	assert_int(absi(other2.y - second.y)).is_less_equal(OTHER_TRIADS_PX)


func test_the_derrick_league_mirror_page_is_within_the_budget() -> void:
	var players: Array[IsoPlayerArt] = [_art(&"fossil", 0), _art(&"fossil", 1)]
	var page: Vector2i = _page(players)
	_assert_within_budget("mirror Derrick", page)
	_assert_today("mirror Derrick", page, TODAY_MIRROR_DERRICK)
	var others: Array[IsoPlayerArt] = [_art(&"fossil", 2), _art(&"fossil", 3)]
	_assert_within_budget("mirror Derrick in other triads", _page(others))
	var second: Vector2i = _page(players, IsoAtlas.PAGE_UNSORTED)
	_assert_within_budget("mirror Derrick page 2", second)
	_assert_today("mirror Derrick page 2", second, TODAY2_MIRROR_DERRICK)
	_assert_within_budget(
		"mirror Derrick page 2 in other triads", _page(others, IsoAtlas.PAGE_UNSORTED)
	)


func test_the_lumen_accord_mirror_page_is_within_the_budget() -> void:
	var players: Array[IsoPlayerArt] = [_art(&"renew", 0), _art(&"renew", 1)]
	var page: Vector2i = _page(players)
	_assert_within_budget("mirror Lumen", page)
	_assert_today("mirror Lumen", page, TODAY_MIRROR_LUMEN)
	var second: Vector2i = _page(players, IsoAtlas.PAGE_UNSORTED)
	_assert_within_budget("mirror Lumen page 2", second)
	_assert_today("mirror Lumen page 2", second, TODAY2_MIRROR_LUMEN)


func test_only_shadows_are_on_page_two() -> void:
	assert_int(IsoAtlas.page_of(&"shadow")).is_equal(IsoAtlas.PAGE_UNSORTED)
	for part: StringName in [
		&"hull", &"turret", &"head", &"walk", &"idle", &"anim", &"dmg1", &"dmg2"
	]:
		assert_int(IsoAtlas.page_of(part)).override_failure_message(part).is_equal(
			IsoAtlas.PAGE_SORTED
		)


func test_a_built_atlas_has_two_textures_and_a_shadow_region_on_the_second() -> void:
	var players: Array[IsoPlayerArt] = [_key_art(&"fossil")]
	var atlas: IsoAtlas = IsoAtlas.build(IsoAtlas.load_sheets(), players, 0.25)
	assert_bool(atlas.is_empty()).is_false()
	assert_object(atlas.texture_for(&"shadow")).is_not_null()
	assert_object(atlas.texture_for(&"shadow")).is_not_same(atlas.texture())
	assert_object(atlas.texture_for(&"hull")).is_same(atlas.texture())
	assert_int(atlas.page_px(IsoAtlas.PAGE_UNSORTED).x).is_equal(IsoAtlas.PAGE_MAX_PX)
	var shadow: Rect2i = atlas.region(&"barracks", &"shadow", -1, 0)
	assert_bool(shadow.has_area()).is_true()
	assert_int(shadow.end.y).is_less_equal(atlas.page_px(IsoAtlas.PAGE_UNSORTED).y)
	# A sprite's texture follows its region's page: the table says which (`texture_at`).
	var base: int = atlas.base(&"barracks", &"shadow", -1, 0)
	assert_object(atlas.texture_at(base)).is_same(atlas.texture_for(&"shadow"))
	var hull: int = atlas.base(&"barracks", &"hull", -1, 0)
	assert_object(atlas.texture_at(hull)).is_same(atlas.texture())


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


func test_the_pages_of_the_budget_include_the_neutral_sheet() -> void:
	var sheets: Array[IsoSheetDef] = _page_sheets()
	assert_int(sheets.size()).is_equal(IsoAtlas.load_sheets().size() + 1)
	assert_str(sheets[-1].faction).is_equal(String(IsoAtlas.NEUTRAL))
	var frames: int = 0
	for part: String in sheets[-1].parts:
		frames += sheets[-1].frame_count(StringName(part))
	assert_int(frames).is_greater_equal(8)  # scar1 x2, scar2 x2, loose x4 at least (ADR 0028).


func test_the_neutral_sheet_is_counted_once_for_all_players() -> void:
	# A neutral sheet (P157, ADR 0028 section 4) is on every match's page as shared slots: a crafted
	# one of 16 frames of 1000 x 500 px takes 16 slots for two players, where a faction's sheet with
	# frames of the same colour takes 32 (a key colour in each, so one per player).
	var players: Array[IsoPlayerArt] = [_art(&"fossil", 0), _art(&"fossil", 1)]
	var base: int = IsoAtlas.planned_page(IsoAtlas.load_sheets(), players, 1.0).y
	var reader: Callable = _giant_reader(NEUTRAL_FRAME)
	var shared: Vector2i = IsoAtlas.planned_page(_with_giant(&"neutral"), players, 1.0, reader)
	var shelf: int = 500 + 2 * RuntimeAtlas.GUTTER_PX
	assert_int(shared.y).is_equal(base + 4 * shelf)  # 16 cells, 4 to a shelf, tallest first.
	var own: Vector2i = IsoAtlas.planned_page(
		_with_giant(&"fossil"), players, 1.0, _giant_reader(CRAFTED)
	)
	assert_int(own.y).is_equal(base + 8 * shelf)  # A slot per player: 32 cells.


## Reads the committed frames, except the crafted sheet's, which are `text`.
func _giant_reader(text: String, marker: String = "/giant_") -> Callable:
	return func(path: String) -> String:
		return text if marker in path else FileAccess.get_file_as_string(path)


func _with_giant(faction: StringName) -> Array[IsoSheetDef]:
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.art_id = &"giant"
	sheet.faction = faction
	sheet.category = &"dmg"
	sheet.parts = PackedStringArray(["anim"])
	sheet.counts = PackedInt32Array([1])
	sheet.frames = PackedInt32Array([16])
	sheet.sizes = PackedInt32Array([1000, 500])
	sheet.anchors = PackedInt32Array([0, 0])
	var sheets: Array[IsoSheetDef] = IsoAtlas.load_sheets()
	sheets.append(sheet)
	return sheets


## Page `page` of the committed sheets for `players` at bake scale 1.0, nothing lowered.
## The neutral damage sheet (P157, ADR 0028 section 4) is in it: the committed one once its file
## exists (P160), else a crafted one of the ADR's shape, 8 slots of 64 x 48 px.
func _page(players: Array[IsoPlayerArt], page: int = IsoAtlas.PAGE_SORTED) -> Vector2i:
	var sheets: Array[IsoSheetDef] = _page_sheets()
	var reader: Callable = Callable()
	if IsoAtlas.load_neutral_sheet(IsoAtlas.NEUTRAL_SHEET) == null:
		reader = _giant_reader(NEUTRAL_FRAME, CRAFTED_ROOT)
	return IsoAtlas.planned_page(sheets, players, 1.0, reader, page)


## The committed sheets and, last, the neutral one (the committed one, else the crafted one).
func _page_sheets() -> Array[IsoSheetDef]:
	var sheets: Array[IsoSheetDef] = IsoAtlas.load_sheets()
	var neutral: IsoSheetDef = IsoAtlas.load_neutral_sheet(IsoAtlas.NEUTRAL_SHEET)
	sheets.append(neutral if neutral != null else _crafted_neutral())
	return sheets


## scar1 and scar2 (2 frames each) and loose (4), each frame 64 x 48 px, faction neutral.
func _crafted_neutral() -> IsoSheetDef:
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.art_id = &"damage"
	sheet.faction = IsoAtlas.NEUTRAL
	sheet.category = &"dmg"
	sheet.root = CRAFTED_ROOT
	sheet.parts = PackedStringArray(["scar1", "scar2", "loose"])
	sheet.counts = PackedInt32Array([1, 1, 1])
	sheet.frames = PackedInt32Array([2, 2, 4])
	sheet.sizes = PackedInt32Array([64, 48, 64, 48, 64, 48])
	sheet.anchors = PackedInt32Array([0, 0, 0, 0, 0, 0])
	return sheet


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
		"%s page is %d px tall, not the %d of before this change: update TODAY_* and TODAY2_*"
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
