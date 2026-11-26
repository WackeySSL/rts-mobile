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
## P306 (the atlas trim, option c1: a directional frame is packed as its tight box) moved page 1
## from 2852, 2776 and 2782 to the pins below (-685, -649 and -714 rows); page 2 (shadows) is not
## trimmed and its pins stay. Page 1 has left 1417 rows on the cross-faction page, 1457 on the
## Derrick League mirror and 1516 on the Lumen Accord mirror.
## P245b (the Flight Yard and the Glide Deck: 3 x 3 hull, KRITISK patch and shadow each, no head
## frames) moved page 1 to the pins below (+62, +86 and +71 rows) and page 2 by 0, +2 and 0.
## Page 1 has left 1270 rows on the cross-faction page, 1326 on the Derrick League mirror and 1346
## on the Lumen Accord mirror.
## P245 (the four aircraft: a 16-direction hull and a 16-direction shadow each, every frame of a
## flyer on page 2, which is not trimmed) left page 1 as it was and moved page 2 from 1514, 782 and
## 814 to the pins below (+472, +312 and +384 rows). Page 2 has left 1598 rows on the cross-faction
## page, 2490 on the Derrick League mirror and 2386 on the Lumen Accord mirror.
## P239b (the Burst Stack and the Sky Needle: 1 x 1 hull, 16 head frames each as boxes, a KRITISK
## patch and a shadow) moved page 1 from 2167, 2127 and 2068 to 2252, 2172 and 2167 (+85, +45 and
## +99 rows) and page 2 from 1514, 704 and 814 to 1514, 780 and 814 (0, +76, 0: the packer fills
## shelves tallest first and never goes back to an earlier shelf, so the shadows push shorter cells
## on). Page 1 then had left 1332 rows on the cross-faction page, 1412 on the Derrick League mirror
## and 1417 on the Lumen Accord mirror.
## P249 (the Draft Shop and the Lens Works: 2 x 2 hull, KRITISK patch and shadow each, no head
## frames) moved page 1 from 2314, 2258 and 2238 to the pins below (+53, +21 and +28 rows) and page
## 2 from 1986, 1094 and 1198 to the pins below (+60, +64 and +46; the cross page's 60 rows are the
## page-2 allocation of ADR 0036 section 15, P26bz note; the shadows are one slot for both players).
## Page 1 has left 1217 rows on the cross-faction page, 1305 on the Derrick League mirror and
## 1318 on the Lumen Accord mirror; page 2 has left 1538, 2426 and 2340.
## P291 (the Bunk Wagon and the Linecar: a 16-direction hull and a 16-direction shadow each, the
## hull trimmed on page 1, the shadows untrimmed on page 2) moved page 1 from 2367, 2279 and 2266 to
## the pins below (+105, +128 and +75 rows) and page 2 from 2046, 1158 and 1244 (+218, +106 and
## +42).
## A 16-direction vehicle shadow set costs about one shelf (its frame height, 112 and 108 rows), so
## the cross page's +218 is the floor, not the 60 rows ADR 0036 section 15's P26bz note allocated;
## the lead's revised page-2 allocation (2026-11-17) is P291 about 220 rows, and a page-2 trim row
## comes before P204 (8-direction shadows are the fallback for later rows only). Page 1 has left
## 1112 rows on the cross-faction page, 1177 on the Derrick League mirror and 1243 on the Lumen
## Accord mirror; page 2 has left 1320, 2320 and 2298.
## P292 (the Shot Truck and the Seeder, the same kind of two sheets) moved page 1 from 2472, 2407
## and 2341 to the pins below (+110, +119 and +94 rows) and page 2 from 2264, 1264 and 1286 (+222,
## +122 and +100), the lead's allocation of about 220 rows on the cross page. Page 1 has left 1002
## rows on the cross-faction page, 1058 on the Derrick League mirror and 1149 on the Lumen Accord
## mirror; page 2 has left 1098, 2198 and 2198 (every page under the 3584 budget).
## P279 (the Weld Shed and the Drone Dock: 2 x 2 hull, an 8-frame `anim` loop cropped to the moving
## element, KRITISK patch and shadow each, no head frames) moved page 1 from 2582, 2526 and 2435
## to the pins below (+46, +26 and +67 rows) and page 2 from 2486, 1386 and 1386 (+18, 0 and +22:
## the packer fills shelves tallest first and never goes back to an earlier shelf, so the shadows
## push shorter cells on, under the 60 rows the plan allocated). Page 1 has left 956 rows on the
## cross-faction page, 1032 on the Derrick League mirror and 1082 on the Lumen Accord mirror; page 2
## has left 1080, 2198 and 2176.
## P280 (the Patchers and the Menders: two-figure squads, an 8-direction hull, walk of 4, idle
## of 2 and shadow each, 64 frames a sheet) moved page 1 from 2628, 2552 and 2502 to the pins
## below (+102, +105 and +96 rows) and page 2 from 2504, 1386 and 1408 (+6, +70 and +70: the
## packer fills shelves tallest first and never goes back to an earlier shelf, so the medic shadows
## push shorter cells on: the cross page's tail re-flows (a 76-row shelf becomes 82), and on each
## mirror page fighter shadows spill into a new 70-row shelf). Page 1 has left 854 rows on the
## cross-faction page, 927 on the Derrick League mirror and 986 on the Lumen Accord mirror; page 2
## has left 1074, 2128 and 2106.
## P638 (the Nordvaern ground vehicles, rebuilt at detail 2 with fixed faction panels: the same
## 16-direction hull, turret and shadow sets, new tight boxes) moved page 1 from 2730, 2657 and 2598
## to 2731, 2582 and 2598 (+1, -75 and 0: the Derrick mirror's shelves fall differently, the
## packer never goes back to an earlier shelf) and page 2 from 2510, 1456 and 1478 to 2512, 1458
## and 1478 (+2, +2 and 0). Page 1 has left 853 rows on the cross-faction page, 1002 on the Derrick
## League mirror and 986 on the Lumen Accord mirror; page 2 has left 1072, 2126 and 2106.
## P639 (the Facet ground vehicles, rebuilt at detail 2 the same way) moved page 1 from 2731, 2582
## and 2598 to 2725, 2582 and 2525 (-6, 0 and -73: the Facet hulls and turrets got tighter boxes
## and the Lumen mirror's shelves fall differently) and page 2 from 2512, 1458 and 1478 to 2516,
## 1458 and 1478 (+4, 0 and 0). Page 1 has left 859 rows on the cross-faction page, 1002 on the
## Derrick League mirror and 1059 on the Lumen Accord mirror; page 2 has left 1068, 2126 and 2106.
## P640: 2725 + 19; P639: 2731 - 6; P638: 2730 + 1; P280: 2628 + 102; P279: 2582 + 46;
## P292: 2472 + 110; P291: 2367 +
## 105;
## P249: 2314 + 53
## (P245b: 2252 + 62; P239b: 2167 + 85; P306: -685).
const TODAY_CROSS: int = 2744
## P640: 2582 + 33; P639: 2582 + 0; P638: 2657 - 75; P280: 2552 + 105; P279: 2526 + 26;
## P292: 2407 + 119; P291: 2279
## + 128;
## P249: 2258 + 21
## (P245b: 2172 + 86; P239b: 2127 + 45).
const TODAY_MIRROR_DERRICK: int = 2615
## P640: 2525 + 0; P639: 2598 - 73; P280: 2502 + 96; P279: 2435 + 67; P292: 2341 + 94;
## P291: 2266 + 75; P249: 2238 +
## 28
## (P245b: 2167 + 71; P239b: 2068 + 99).
const TODAY_MIRROR_LUMEN: int = 2525
## Page 2 (the shadows and the flyers): until P204 puts a key colour in a unit's shadow a shadow is
## one slot for both players. The packer fills shelves tallest first and never goes back to an
## earlier shelf, so a shadow added pushes shorter cells on and the trailing shelves grow. An
## aircraft's hull carries the team colour, so it has a slot per player (P245).
## P639: 2512 + 4; P638: 2510 + 2; P280: 2504 + 6; P279: 2486 + 18; P292: 2264 + 222; P291: 2046 +
## 218;
## P249: 1986 + 60
## (P245: 1514 + 472; P203: 1116 + 398, the pads).
const TODAY2_CROSS: int = 2516
## P639: 1458 + 0; P638: 1456 + 2; P280: 1386 + 70; P279: 1386 + 0; P292: 1264 + 122; P291: 1158 +
## 106;
## P249: 1094 + 64
## (P245: 782 + 312; P245b: 780 + 2).
const TODAY2_MIRROR_DERRICK: int = 1458
## P639: 1478 + 0; P280: 1408 + 70; P279: 1386 + 22; P292: 1286 + 100; P291: 1244 + 42; P249: 1198 +
## 46
## (P245: 814 + 384; P203: 634 + 180).
const TODAY2_MIRROR_LUMEN: int = 1478
const OTHER_TRIADS_PX: int = 40  ## How far another pair of triads may move the page.
const CRAFTED: String = (
	'<svg xmlns="http://www.w3.org/2000/svg" width="8" height="4">'
	+ '<polygon points="0,0 8,0 8,4" fill="#D234D2"/></svg>'
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
	# The routes' interim colours (orange, Kobolt) and the coming defaults, Sne and Karmin (P632, ADR
	# 0050 section 3): the page of the sentinel migration stays within the same 40 rows.
	for pair: Array in [[0, 3], [6, 2]]:
		var routes: Vector2i = _page([_art(&"fossil", pair[0]), _art(&"renew", pair[1])])
		_assert_within_budget("cross-faction in triads %s" % [pair], routes)
		assert_int(absi(routes.y - TODAY_CROSS)).is_less_equal(OTHER_TRIADS_PX)
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
