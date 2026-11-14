extends GdUnitTestSuite
## The tight boxes of the directional frames (plan row P305, ADR 0036 section 15's P26bw note):
## every sheet gives, for each frame of a part with several directions, the drawn box plus the
## canvas margin, read off the frame itself; a part with one view has none and the whole canvas
## is its box. P306 packs the boxes and places the frames by them.

## A box is the drawn pixels plus the margin of `ArtGen.MARGIN_PX`; a pixel of slack covers the
## anti-aliased rim that a raster adds to the polygon bounds.
const SLACK_PX: int = 1

var _index: IsoIndex = null


func before() -> void:
	_index = load(IsoIndex.PATH) as IsoIndex


func test_a_directional_frame_has_a_box_that_holds_every_drawn_pixel_and_hugs_them() -> void:
	var checked: int = 0
	for sheet: IsoSheetDef in _index.sheets:
		for part: String in sheet.parts:
			var id: StringName = StringName(part)
			if not sheet.has_boxes(id):
				continue
			var canvas: Rect2i = Rect2i(Vector2i.ZERO, sheet.frame_size(id))
			for dir: int in sheet.directions(id):
				for frame: int in sheet.frame_count(id):
					var ink: Rect2i = _ink(sheet, id, dir, frame)
					var box: Rect2i = sheet.frame_box(id, dir, frame)
					var label: String = "%s %s d%02d f%d" % [sheet.art_id, part, dir, frame]
					# Every drawn pixel is inside the box.
					assert_bool(box.encloses(ink)).override_failure_message(label).is_true()
					# The ring of the box's own edge is clear wherever the box is not on the
					# canvas edge: the margin is at least 1 px beyond the alpha bounds.
					var inner: Rect2i = box.grow_individual(
						-1 if box.position.x > 0 else 0,
						-1 if box.position.y > 0 else 0,
						-1 if box.end.x < canvas.end.x else 0,
						-1 if box.end.y < canvas.end.y else 0
					)
					assert_bool(inner.encloses(ink)).override_failure_message(label).is_true()
					# And no more than 2 px: the box hugs the ink.
					var wide: Rect2i = ink.grow(2).intersection(canvas)
					assert_bool(wide.encloses(box)).override_failure_message(label).is_true()
					checked += 1
	assert_int(checked).is_greater(300)


func test_boxes_of_a_synthetic_shot_are_the_bounds_plus_the_margin_in_canvas_px() -> void:
	var shots: Dictionary[StringName, ArtGen.Shot] = {&"hull": _shot(2, 40, 30)}
	var boxes: PackedInt32Array = ArtSheet._boxes(shots)
	# Bounds (-10.3, -5.2)..(10.6, 4.0): floor -11, -6 and ceil 11, 4; margin 2; origin (20, 15).
	var want: Rect2i = Rect2i(7, 7, 26, 14)
	assert_array(Array(boxes)).is_equal(
		[want.position.x, want.position.y, want.size.x, want.size.y, 7, 7, 26, 14]
	)


func test_a_box_that_would_pass_the_canvas_is_clamped_to_it() -> void:
	var shot: ArtGen.Shot = _shot(2, 30, 20)
	shot.layout.origin = Vector2i(5, 5)
	shot.polys[0] = [_poly(PackedVector2Array([Vector2(-5, -5), Vector2(3, 3)]))]
	shot.polys[1] = [_poly(PackedVector2Array([Vector2(20, 10), Vector2(24.5, 14.5)]))]
	var boxes: PackedInt32Array = ArtSheet._boxes({&"hull": shot})
	# First: low -7 + 5 = -2 clamps to 0; high 3 + 2 + 5 = 10. Second: 20 - 2 + 5 = 23, high
	# ceil(24.5) + 2 + 5 = 32 clamps to 30; y 13 to 22 clamps to 20.
	assert_array(Array(boxes)).is_equal([0, 0, 10, 10, 23, 13, 7, 7])


func test_the_shadow_and_a_one_view_part_have_no_boxes_and_the_others_follow_in_file_order(
) -> void:
	var shots: Dictionary[StringName, ArtGen.Shot] = {
		&"hull": _shot(2, 40, 30), &"turret": _shot(2, 40, 30), &"shadow": _shot(2, 40, 30)
	}
	assert_int(ArtSheet._boxes(shots).size()).is_equal(2 * 4 * 2)
	assert_int(ArtSheet._boxes({&"hull": _shot(1, 40, 30)}).size()).is_equal(0)
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.parts = PackedStringArray(["hull", "turret", "shadow"])
	sheet.counts = PackedInt32Array([8, 16, 8])
	sheet.sizes = PackedInt32Array([40, 30, 40, 30, 40, 30])
	sheet.boxes = PackedInt32Array()
	for i: int in 8 + 16:
		sheet.boxes.append_array([i, 0, 1, 1])
	assert_object(sheet.frame_box(&"hull", 2)).is_equal(Rect2i(1, 0, 1, 1))
	assert_object(sheet.frame_box(&"turret", 1)).is_equal(Rect2i(9, 0, 1, 1))
	assert_object(sheet.frame_box(&"shadow", 2)).is_equal(Rect2i(0, 0, 40, 30))


## `frame_box` reports a frame the sheet lacks with `push_error` and answers the whole canvas; the
## test asks `has_frame`, its guard, so no error reaches the log (verify.sh fails on one).
func test_has_frame_refuses_a_frame_the_sheet_lacks() -> void:
	var sheet: IsoSheetDef = load("res://assets/art/iso/fossil/inf/rifle_squad_sheet.tres")
	var frames: int = sheet.frame_count(&"walk")
	# A squad has the even directions only; `dir` and `frame` out of range, and a part it lacks.
	for dir: int in [1, 16, -1]:
		assert_bool(sheet.has_frame(&"hull", dir)).override_failure_message(str(dir)).is_false()
	assert_bool(sheet.has_frame(&"hull", 0)).is_true()
	assert_bool(sheet.has_frame(&"hull", 14)).is_true()
	assert_bool(sheet.has_frame(&"walk", 2, frames)).is_false()
	assert_bool(sheet.has_frame(&"walk", 2, -1)).is_false()
	assert_bool(sheet.has_frame(&"walk", 2, frames - 1)).is_true()
	assert_bool(sheet.has_frame(&"nope", 0)).is_false()
	var walk: Rect2i = Rect2i(Vector2i.ZERO, sheet.frame_size(&"walk"))
	assert_object(sheet.frame_box(&"walk", 2, frames - 1)).is_not_equal(walk)


func test_a_part_with_one_view_has_the_whole_canvas_as_its_box_and_no_entry_in_boxes() -> void:
	var sheet: IsoSheetDef = load("res://assets/art/iso/fossil/bld/defence_turret_sheet.tres")
	var canvas: Vector2i = sheet.frame_size(&"hull")
	assert_int(sheet.counts[sheet.parts.find("hull")]).is_equal(1)
	assert_object(sheet.frame_box(&"hull", -1)).is_equal(Rect2i(Vector2i.ZERO, canvas))
	var entries: int = 0
	for part: String in sheet.parts:
		if sheet.counts[sheet.parts.find(part)] > 1:
			entries += sheet.counts[sheet.parts.find(part)] * sheet.frame_count(StringName(part))
	assert_int(sheet.boxes.size()).is_equal(4 * entries)


func test_a_sheet_without_boxes_answers_the_whole_canvas() -> void:
	var sheet: IsoSheetDef = load("res://assets/art/iso/fossil/veh/heavy_tank_sheet.tres")
	var bare: IsoSheetDef = sheet.duplicate() as IsoSheetDef
	bare.boxes = PackedInt32Array()
	assert_object(bare.frame_box(&"hull", 4)).is_equal(
		Rect2i(Vector2i.ZERO, sheet.frame_size(&"hull"))
	)


func test_a_building_without_a_head_has_no_boxes() -> void:
	for sheet: IsoSheetDef in _index.sheets:
		if not sheet.counts.is_empty() and sheet.counts.count(1) == sheet.counts.size():
			assert_int(sheet.boxes.size()).override_failure_message(String(sheet.art_id)).is_equal(
				0
			)


## The pixels of a frame that are not clear, in canvas px.
func _ink(sheet: IsoSheetDef, part: StringName, dir: int, frame: int) -> Rect2i:
	var image: Image = Image.new()
	image.load_svg_from_string(FileAccess.get_file_as_string(sheet.path(part, dir, frame)), 1.0)
	image.convert(Image.FORMAT_RGBA8)
	var used: Rect2i = image.get_used_rect()
	return used


## A shot of `dirs` directions in a canvas of `width` x `height`, origin at its middle, each frame
## one rectangle of the bounds (-10.3, -5.2) to (10.6, 4.0).
func _shot(dirs: int, width: int, height: int) -> ArtGen.Shot:
	var shot: ArtGen.Shot = ArtGen.Shot.new()
	shot.layout = ArtGen.Layout.new()
	shot.layout.size = Vector2i(width, height)
	shot.layout.origin = Vector2i(width / 2, height / 2)
	for i: int in dirs:
		shot.dirs.append(i * (16 / dirs) if dirs > 1 else -1)
		shot.polys.append([_poly(PackedVector2Array([Vector2(-10.3, -5.2), Vector2(10.6, 4.0)]))])
	return shot


func _poly(points: PackedVector2Array) -> ArtRender.Poly:
	var poly: ArtRender.Poly = ArtRender.Poly.new()
	poly.points = points
	return poly
