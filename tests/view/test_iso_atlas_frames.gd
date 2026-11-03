extends GdUnitTestSuite
## The frame axis of the atlas bake (plan P137, ADR 0027 section 4). Crafted sheets, read through
## the `reader` seam, because no committed model has a pose part yet: a squad with `walk` (4
## frames) and `idle` (2) in 8 directions, and a building with a 3-frame `anim` that has no
## direction. Pinned: the bake asks for the file of every frame (`_f<K>`) and of nothing else; each
## frame of each player holds its own picture; frame 0 is the region the atlas always gave; a frame
## change is a read of the packed region table and builds no key (`IsoAtlas.keys_built`, the hook),
## and a base index is resolved once; `show_frame` without a frame is what it was. The push_error
## paths (a frame with no text) are not tested on purpose: they print "ERROR:" even when asserted
## (ADR 0002, Consequences).

const KEY: PackedStringArray = ["#FF9446", "#E8681F", "#B04B12"]  ## Signal, the Derrick League's.
const ARKTISK: PackedStringArray = ["#62D6EE", "#1FA6C8", "#137C99"]
const FRAME: Vector2i = Vector2i(8, 4)  ## A crafted frame: its own colour, then a key stripe.
const HEAD: String = '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">'
const BLOCK: String = '<polygon points="%d,0 %d,0 %d,%d %d,%d" fill="%s"/>'
const CODES: Dictionary[StringName, int] = {
	&"hull": 0x40, &"walk": 0x60, &"idle": 0x80, &"anim": 0xA0
}
const ARRIVALS: int = 400  ## Frame changes of the no-key proof.
## What a frame path may not name: a string made some way, and (the tokens of
## test_effects_layer_frames.gd) a call or a literal that makes or grows an array or a dictionary.
const STRINGS: Array[String] = ["%", '"', "'", "String", "str(", "_key(", ".base(", "base_of("]
const ALLOCATING: Array[String] = [
	"Array(",
	".new(",
	".append",
	".push_back(",
	".resize(",
	".duplicate(",
	".map(",
	".filter(",
	"func(",
	"{",
	"[]",
	"= [",
	"([",
	", [",
	"return [",
	" in [",
	": Array",
	"Array[",
]
const SCRIPT_ATLAS: String = "res://game/view/IsoAtlas.gd"
const SCRIPT_SORT: String = "res://game/view/WorldSort.gd"

var _name: RegEx


func before_test() -> void:
	_name = RegEx.create_from_string(
		"^[a-z]+_(?<part>hull|walk|idle|anim|shadow)(?:_d(?<dir>\\d\\d))?(?:_f(?<frame>\\d+))?$"
	)


func test_the_bake_asks_for_the_file_of_every_frame_of_a_multi_frame_part_and_no_other() -> void:
	var sheet: IsoSheetDef = _squad_sheet()
	var reads: Array[String] = []
	var players: Array[IsoPlayerArt] = [_art(KEY, KEY), _art(KEY, ARKTISK)]
	var atlas: IsoAtlas = IsoAtlas.build([sheet], players, 1.0, true, _reader(reads))
	assert_bool(atlas.is_empty()).is_false()
	var want: Array[String] = []
	for part_name: String in sheet.parts:
		var part: StringName = StringName(part_name)
		for dir: int in sheet.directions(part):
			for frame: int in sheet.frame_count(part):
				want.append(sheet.path(part, dir, frame))
	assert_int(want.size()).is_equal(8 + 8 * 4 + 8 * 2 + 1)
	assert_bool(want.has("res://assets/art/iso/fossil/inf/squad_walk_d02_f3.svg")).is_true()
	assert_bool(want.has("res://assets/art/iso/fossil/inf/squad_idle_d14_f1.svg")).is_true()
	assert_bool(want.has("res://assets/art/iso/fossil/inf/squad_hull_d04.svg")).is_true()
	assert_int(reads.size()).is_equal(2 * want.size())  # Each player reads each file once.
	for path: String in want:
		assert_int(reads.count(path)).override_failure_message(path).is_equal(2)
	for path: String in reads:
		assert_bool(want.has(path)).override_failure_message(path).is_true()
	# The file of a part with frames has no frame-less name, and a frame has a region of its own.
	assert_bool(reads.has("res://assets/art/iso/fossil/inf/squad_walk_d02.svg")).is_false()


func test_each_frame_of_each_direction_holds_its_own_picture_for_each_player() -> void:
	var sheet: IsoSheetDef = _squad_sheet()
	var players: Array[IsoPlayerArt] = [_art(KEY, KEY), _art(KEY, ARKTISK)]
	var atlas: IsoAtlas = IsoAtlas.build([sheet], players, 1.0, true, _reader([]))
	var rects: Array[Rect2i] = []
	for player: int in players.size():
		for part_name: String in sheet.parts:
			var part: StringName = StringName(part_name)
			for dir: int in sheet.directions(part):
				for frame: int in sheet.frame_count(part):
					var rect: Rect2i = atlas.region(&"squad", part, dir, player, frame)
					var label: String = "%s d%02d f%d of player %d" % [part, dir, frame, player]
					assert_that(rect.size).override_failure_message(label).is_equal(FRAME)
					if part == &"shadow":
						continue  # No key colour: one region for both players, tested below.
					assert_bool(rects.has(rect)).override_failure_message(label).is_false()
					rects.append(rect)
					var picture: Image = atlas.image().get_region(rect)
					var own: String = "#" + picture.get_pixel(2, 2).to_html(false).to_upper()
					var stripe: String = "#" + picture.get_pixel(6, 2).to_html(false).to_upper()
					assert_str(own).override_failure_message(label).is_equal(
						_paint(part, dir, frame)
					)
					assert_str(stripe).override_failure_message(label).is_equal(
						players[player].triad[1]
					)
	assert_int(rects.size()).is_equal(2 * (8 + 8 * 4 + 8 * 2))
	assert_that(atlas.region(&"squad", &"shadow", -1, 1)).is_equal(
		atlas.region(&"squad", &"shadow", -1, 0)
	)


func test_frame_0_is_the_region_the_atlas_always_gave_and_the_table_reads_the_same() -> void:
	var sheet: IsoSheetDef = _squad_sheet()
	var atlas: IsoAtlas = IsoAtlas.build([sheet], [_art(KEY, ARKTISK)], 1.0, true, _reader([]))
	for part_name: String in sheet.parts:
		var part: StringName = StringName(part_name)
		for dir: int in sheet.directions(part):
			var first: Rect2i = atlas.region(&"squad", part, dir)  # The old call, no frame.
			assert_bool(first.has_area()).is_true()
			assert_that(first).is_equal(atlas.region(&"squad", part, dir, 0, 0))
			var base: int = atlas.base(&"squad", part, dir, 0)
			assert_that(first).is_equal(atlas.frame_region(base, 0))
			for frame: int in sheet.frame_count(part):
				assert_that(atlas.frame_region(base, frame)).is_equal(
					atlas.region(&"squad", part, dir, 0, frame)
				)
			# The group is its frames and not a frame more: the next one's start is not frame N.
			var count: int = sheet.frame_count(part)
			assert_that(atlas.frame_region(base, count)).is_equal(Rect2i())
			assert_that(atlas.region(&"squad", part, dir, 0, count)).is_equal(Rect2i())
			assert_that(atlas.frame_region(base, -1)).is_equal(Rect2i())
	# The frames of a part with one frame are today's: frame 0 only.
	assert_bool(atlas.region(&"squad", &"hull", 4).has_area()).is_true()
	assert_that(atlas.region(&"squad", &"hull", 4, 0, 1)).is_equal(Rect2i())
	assert_that(atlas.frame_region(-1, 0)).is_equal(Rect2i())
	assert_that(atlas.frame_region(99999, 0)).is_equal(Rect2i())
	assert_int(atlas.base(&"squad", &"walk", 3, 0)).is_equal(-1)  # No such direction.
	assert_int(atlas.base(&"squad", &"walk", 4, 1)).is_equal(-1)  # No such player.
	assert_int(atlas.base(&"nobody", &"walk", 4, 0)).is_equal(-1)


func test_a_building_anim_has_its_frames_and_no_direction_and_is_anchored_at_the_centre() -> void:
	var sheet: IsoSheetDef = _plant_sheet()
	var reads: Array[String] = []
	var players: Array[IsoPlayerArt] = [_art(KEY, KEY), _art(KEY, ARKTISK)]
	var atlas: IsoAtlas = IsoAtlas.build([sheet], players, 1.0, true, _reader(reads))
	assert_bool(reads.has("res://assets/art/iso/fossil/bld/plant_anim_f0.svg")).is_true()
	assert_bool(reads.has("res://assets/art/iso/fossil/bld/plant_anim_f2.svg")).is_true()
	assert_bool(reads.has("res://assets/art/iso/fossil/bld/plant_hull.svg")).is_true()
	assert_int(reads.size()).is_equal(2 * (3 + 1 + 1))
	for player: int in players.size():
		var seen: Array[Rect2i] = []
		for frame: int in 3:
			var rect: Rect2i = atlas.region(&"plant", &"anim", -1, player, frame)
			var picture: Image = atlas.image().get_region(rect)
			var own: String = "#" + picture.get_pixel(2, 2).to_html(false).to_upper()
			assert_str(own).is_equal(_paint(&"anim", -1, frame))
			assert_bool(seen.has(rect)).is_false()
			seen.append(rect)
		assert_that(atlas.region(&"plant", &"anim", -1, player, 3)).is_equal(Rect2i())
		assert_bool(atlas.region(&"plant", &"hull", -1, player).has_area()).is_true()
	# The canvas is anchored at the footprint centre: its origin is its anchor, so a sprite of it
	# dressed at the centre needs no mount; the body's origin is a footprint lower.
	assert_that(sheet.origin(&"anim")).is_equal(sheet.anchor(&"anim"))
	assert_that(sheet.origin(&"hull")).is_equal(sheet.anchor(&"hull") + Vector2i(0, 64))
	var sort: WorldSort = _sort([sheet])
	var sprite: Sprite2D = auto_free(Sprite2D.new())
	sort.dress(sprite, sheet, &"anim")
	assert_that(sprite.offset).is_equal(-Vector2(sheet.origin(&"anim")) * sort.atlas.bake_scale())


func test_a_frame_change_builds_no_key_and_a_base_is_resolved_once() -> void:
	var sheet: IsoSheetDef = _squad_sheet()
	var sort: WorldSort = _sort([sheet])
	var sprite: Sprite2D = auto_free(Sprite2D.new())
	sort.dress(sprite, sheet, &"walk")
	var want: Array[Rect2] = []
	for frame: int in 4:
		want.append(Rect2(sort.atlas.region(&"squad", &"walk", 6, 0, frame)))
	assert_int(want.count(want[0])).is_equal(1)  # Four frames, four regions.
	assert_int(want.count(want[3])).is_equal(1)
	# The hook counts: resolving a base builds one key, and so does a dress-time show_frame.
	var before: int = IsoAtlas.keys_built()
	var base: int = sort.base_of(sheet, &"walk", 6, 1)
	assert_int(IsoAtlas.keys_built() - before).is_equal(1)
	assert_int(base).is_greater_equal(0)
	# A dress or a turn through show_frame builds that one key too and hands the base back.
	before = IsoAtlas.keys_built()
	assert_int(sort.show_frame(sprite, sheet, &"walk", 6, 1)).is_equal(base)
	assert_int(IsoAtlas.keys_built() - before).is_equal(1)
	# Frame changes, wrapped by the atlas's own count: a table read each, which builds nothing.
	before = IsoAtlas.keys_built()
	var count: int = sort.frame_count_at(base)
	assert_int(count).is_equal(4)
	for step: int in ARRIVALS:
		sort.show_base(sprite, base, step % count)
		assert_that(sprite.region_rect).is_equal(want[step % count])
		assert_bool(sprite.visible).is_true()
	assert_int(IsoAtlas.keys_built() - before).is_equal(0)
	# A frame the part lacks hides the sprite, and the next real one shows it again.
	sort.show_base(sprite, base, 4)
	assert_bool(sprite.visible).is_false()
	sort.show_base(sprite, base, 1)
	assert_bool(sprite.visible).is_true()
	assert_that(sprite.region_rect).is_equal(want[1])
	sort.show_base(sprite, -1, 0)  # A frame the owner's faction lacks.
	assert_bool(sprite.visible).is_false()
	assert_int(IsoAtlas.keys_built() - before).is_equal(0)


func test_the_frame_path_builds_no_string_and_allocates_nothing_in_its_source() -> void:
	# The hook counts the keys; this keeps a string from arriving some other way (a format, a
	# StringName or String made of the part, a literal), and an array, dictionary or lambda from
	# being made (ADR 0027 section 9, as test_effects_layer_frames.gd scans), in the functions a
	# frame change runs.
	var runs: Array = [
		[SCRIPT_ATLAS, "frame_region"],
		[SCRIPT_ATLAS, "frame_count_at"],
		[SCRIPT_SORT, "show_base"],
		[SCRIPT_SORT, "frame_count_at"]
	]
	for entry: Array in runs:
		var code: String = _code_of(entry[0], entry[1])
		assert_int(code.count("\n")).is_greater(1)  # The function and not its first line.
		for token: String in STRINGS:
			var note: String = "%s makes a string with %s" % [entry[1], token]
			assert_bool(code.contains(token)).override_failure_message(note).is_false()
		for token: String in ALLOCATING:
			var note: String = "%s makes an array or a lambda with %s" % [entry[1], token]
			assert_bool(code.contains(token)).override_failure_message(note).is_false()


func test_the_neutral_base_read_makes_no_string_and_allocates_nothing_in_its_body() -> void:
	# Its signature names `StringName`, so the scan starts after the first line.
	var code: String = _code_of(SCRIPT_SORT, "neutral_base")
	code = code.substr(code.find("\n") + 1)
	assert_int(code.count("\n")).is_greater(1)
	for token: String in STRINGS + ALLOCATING:
		var note: String = "neutral_base makes a string or an allocation with %s" % token
		assert_bool(code.contains(token)).override_failure_message(note).is_false()


func test_show_frame_with_no_frame_is_what_it_was_and_a_frame_is_its_last_argument() -> void:
	var sheet: IsoSheetDef = _squad_sheet()
	var sort: WorldSort = _sort([sheet])
	var sprite: Sprite2D = auto_free(Sprite2D.new())
	sort.dress(sprite, sheet, &"hull")
	sort.show_frame(sprite, sheet, &"hull", 4, 1)
	assert_bool(sprite.visible).is_true()
	assert_that(Rect2i(sprite.region_rect)).is_equal(sort.atlas.region(&"squad", &"hull", 4, 0))
	sort.show_frame(sprite, sheet, &"hull", 4, 1, 0)
	assert_that(Rect2i(sprite.region_rect)).is_equal(sort.atlas.region(&"squad", &"hull", 4, 0))
	# A direction the faction lacks hides the sprite, as before.
	sort.show_frame(sprite, sheet, &"hull", 5, 1)
	assert_bool(sprite.visible).is_false()
	# A frame of a pose part.
	sort.dress(sprite, sheet, &"idle")
	sort.show_frame(sprite, sheet, &"idle", 2, 1, 1)
	assert_that(Rect2i(sprite.region_rect)).is_equal(sort.atlas.region(&"squad", &"idle", 2, 0, 1))
	assert_that(Rect2i(sprite.region_rect)).is_not_equal(sort.atlas.region(&"squad", &"idle", 2, 0))
	sort.show_frame(sprite, sheet, &"idle", 2, 1, 2)  # The part has two frames.
	assert_bool(sprite.visible).is_false()


func test_the_atlas_says_how_many_frames_a_group_has() -> void:
	var sheet: IsoSheetDef = _squad_sheet()
	var sort: WorldSort = _sort([sheet])
	var atlas: IsoAtlas = sort.atlas
	for part_name: String in sheet.parts:
		var part: StringName = StringName(part_name)
		for dir: int in sheet.directions(part):
			var base: int = atlas.base(&"squad", part, dir, 0)
			assert_int(atlas.frame_count_at(base)).is_equal(sheet.frame_count(part))
			assert_int(sort.frame_count_at(base)).is_equal(sheet.frame_count(part))
	var walk: int = atlas.base(&"squad", &"walk", 0, 0)
	assert_int(atlas.frame_count_at(walk)).is_equal(4)
	assert_int(atlas.frame_count_at(atlas.base(&"squad", &"idle", 0, 0))).is_equal(2)
	assert_int(atlas.frame_count_at(atlas.base(&"squad", &"hull", 0, 0))).is_equal(1)
	# No base, an index that is no base (the second frame of a group) and one past the table: 0.
	assert_int(atlas.frame_count_at(-1)).is_equal(0)
	assert_int(atlas.frame_count_at(walk + 1)).is_equal(0)
	assert_int(atlas.frame_count_at(99999)).is_equal(0)
	assert_int(sort.frame_count_at(-1)).is_equal(0)
	assert_int(IsoAtlas.new().frame_count_at(0)).is_equal(0)


func test_a_part_a_sheet_gives_0_frames_has_its_one_frame_and_not_the_next_groups() -> void:
	# A malformed sheet (`frames` 0 for `walk`) must not leave its groups pointing at the base of
	# the next part's, which would show another part's picture: it is read as one frame.
	var sheet: IsoSheetDef = _squad_sheet()
	sheet.frames = PackedInt32Array([1, 0, 2, 1])
	var reads: Array[String] = []
	var atlas: IsoAtlas = IsoAtlas.build([sheet], [_art(KEY, ARKTISK)], 1.0, true, _reader(reads))
	assert_bool(reads.has("res://assets/art/iso/fossil/inf/squad_walk_d04.svg")).is_true()
	for dir: int in sheet.directions(&"walk"):
		var base: int = atlas.base(&"squad", &"walk", dir, 0)
		assert_int(atlas.frame_count_at(base)).is_equal(1)
		var picture: Image = atlas.image().get_region(atlas.frame_region(base, 0))
		var own: String = "#" + picture.get_pixel(2, 2).to_html(false).to_upper()
		assert_str(own).is_equal(_paint(&"walk", dir, 0))
		assert_that(atlas.frame_region(base, 1)).is_equal(Rect2i())
	# The parts after it keep their own groups.
	var idle: int = atlas.base(&"squad", &"idle", 4, 0)
	assert_int(atlas.frame_count_at(idle)).is_equal(2)
	var idle_picture: Image = atlas.image().get_region(atlas.frame_region(idle, 1))
	assert_str("#" + idle_picture.get_pixel(2, 2).to_html(false).to_upper()).is_equal(
		_paint(&"idle", 4, 1)
	)


func test_the_planned_page_is_the_page_of_the_bake_and_grows_with_the_frames() -> void:
	var sheet: IsoSheetDef = _squad_sheet()
	var players: Array[IsoPlayerArt] = [_art(KEY, KEY), _art(KEY, ARKTISK)]
	var atlas: IsoAtlas = IsoAtlas.build([sheet], players, 1.0, false, _reader([]))
	assert_that(IsoAtlas.planned_page([sheet], players, 1.0, _reader([]))).is_equal(atlas.page_px())
	# Planned from the metadata alone, a squad of big canvases: 57 frames a player is a taller page
	# than the same squad with one frame in each pose part (24 a player).
	var big: IsoSheetDef = _squad_sheet()
	big.sizes = PackedInt32Array([1000, 500, 1000, 500, 1000, 500, 1000, 500])
	var plain: IsoSheetDef = _squad_sheet()
	plain.sizes = big.sizes
	plain.frames = PackedInt32Array([1, 1, 1, 1])
	var tall: Vector2i = IsoAtlas.planned_page([big], players, 1.0, _reader([]))
	var short: Vector2i = IsoAtlas.planned_page([plain], players, 1.0, _reader([]))
	assert_int(short.x).is_equal(IsoAtlas.PAGE_MAX_PX)
	assert_int(short.y).is_greater(0)
	assert_int(tall.y).is_greater(short.y)


func test_the_bake_reports_atlas_bake_ms_in_one_line() -> void:
	var sheet: IsoSheetDef = _squad_sheet()
	var atlas: IsoAtlas = IsoAtlas.build([sheet], [_art(KEY, KEY)], 1.0, false, _reader([]))
	var line: RegEx = RegEx.create_from_string(
		"^atlas_bake_ms \\d+\\.\\d \\| page 4096x\\d+ at 1\\.000$"
	)
	assert_object(line.search(atlas.report())).is_not_null()
	assert_str(atlas.report()).is_equal(
		"atlas_bake_ms %.1f | page %dx%d at 1.000" % [atlas.bake_ms(), 4096, atlas.page_px().y]
	)
	assert_str(IsoAtlas.new().report()).ends_with("| page none")


## The crafted squad: a hull and a shadow of one frame, `walk` (4) and `idle` (2), 8 directions.
func _squad_sheet() -> IsoSheetDef:
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.art_id = &"squad"
	sheet.faction = &"fossil"
	sheet.category = &"inf"
	sheet.parts = PackedStringArray(["hull", "walk", "idle", "shadow"])
	sheet.counts = PackedInt32Array([8, 8, 8, 1])
	sheet.frames = PackedInt32Array([1, 4, 2, 1])
	for part: int in 4:
		sheet.sizes.append_array([FRAME.x, FRAME.y])
		sheet.anchors.append_array([0, 0])
	return sheet


## The crafted building: a body and a shadow, and an `anim` of 3 frames that has no direction.
func _plant_sheet() -> IsoSheetDef:
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.art_id = &"plant"
	sheet.faction = &"fossil"
	sheet.category = &"bld"
	sheet.footprint = 2
	sheet.parts = PackedStringArray(["hull", "anim", "shadow"])
	sheet.counts = PackedInt32Array([1, 1, 1])
	sheet.frames = PackedInt32Array([1, 3, 1])
	for part: int in 3:
		sheet.sizes.append_array([FRAME.x, FRAME.y])
		sheet.anchors.append_array([4, 2] if part == 1 else [0, 0])
	return sheet


## The colour a crafted frame is painted in: unique to its part, direction and frame number.
func _paint(part: StringName, dir: int, frame: int) -> String:
	return "#%02X%02X%02X" % [CODES[part], 8 + 8 * (dir + 1), 8 + 16 * frame]


## The crafted frames, found by the part, `d<NN>` and `_f<K>` of the path asked for: the left half
## in `_paint`, the right half a key stripe the player recolours, a shadow all black. `reads` gets
## every path asked for.
func _reader(reads: Array[String]) -> Callable:
	return func(path: String) -> String:
		reads.append(path)
		var hit: RegExMatch = _name.search(path.get_file().get_basename())
		assert_object(hit).override_failure_message(path).is_not_null()
		var part: StringName = StringName(hit.get_string("part"))
		var dir: int = hit.get_string("dir").to_int() if hit.get_string("dir") != "" else -1
		var frame: int = hit.get_string("frame").to_int()
		if part == &"shadow":
			return HEAD % [FRAME.x, FRAME.y] + _block(0, FRAME.x, "#000000") + "</svg>"
		return (
			HEAD % [FRAME.x, FRAME.y]
			+ _block(0, 4, _paint(part, dir, frame))
			+ _block(4, 8, KEY[1])
			+ "</svg>"
		)


## One block of `colour` from `left` to `right` across the height of a crafted frame.
func _block(left: int, right: int, colour: String) -> String:
	return BLOCK % [left, right, right, FRAME.y, left, FRAME.y, colour]


func _art(key: PackedStringArray, triad: PackedStringArray) -> IsoPlayerArt:
	return IsoPlayerArt.make(&"fossil", key, triad)


## A sort whose atlas holds `sheets` for one player (owner 1, slot 0), baked from crafted frames.
func _sort(sheets: Array[IsoSheetDef]) -> WorldSort:
	var sort: WorldSort = auto_free(WorldSort.new())
	sort.atlas = IsoAtlas.build(sheets, [_art(KEY, ARKTISK)], 1.0, true, _reader([]))
	return sort


## The code of function `func_name` of the script at `path`, without its comments.
func _code_of(path: String, func_name: String) -> String:
	var source: String = FileAccess.get_file_as_string(path)
	var start: int = source.find("func %s(" % func_name)
	assert_int(start).is_greater_equal(0)
	var end: int = source.find("\n\n\n", start)  # Two blank lines end a function (gdformat).
	if end < 0:
		end = source.length()
	var code: String = ""
	for line: String in source.substr(start, end - start).split("\n"):
		code += line.get_slice("#", 0) + "\n"  # Words in a comment make nothing.
	return code
