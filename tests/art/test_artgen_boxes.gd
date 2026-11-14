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
			if sheet.counts[sheet.parts.find(part)] <= 1:
				continue
			for dir: int in sheet.directions(StringName(part)):
				for frame: int in sheet.frame_count(StringName(part)):
					var ink: Rect2i = _ink(sheet, StringName(part), dir, frame)
					var box: Rect2i = sheet.frame_box(StringName(part), dir, frame)
					var label: String = "%s %s d%02d f%d" % [sheet.art_id, part, dir, frame]
					assert_bool(box.encloses(ink)).override_failure_message(label).is_true()
					var wide: Rect2i = ink.grow(ArtGen.MARGIN_PX + SLACK_PX).intersection(
						Rect2i(Vector2i.ZERO, sheet.frame_size(StringName(part)))
					)
					assert_bool(wide.encloses(box)).override_failure_message(label).is_true()
					checked += 1
	assert_int(checked).is_greater(500)


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
