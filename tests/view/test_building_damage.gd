extends "res://tests/view/support/damage_suite.gd"
## The damage stages of buildings (plan P159, ADR 0028 sections 2 and 3, ADR 0029 sections 2, 3 and
## 12): the stage function and its two lists, the trimmed body and the `Damage` sibling, the seam at
## every bake scale. Fixtures: support/damage_suite.gd.

# --- The stage function and its data ---


func test_the_building_lines_split_at_67_and_34_with_a_strict_under() -> void:
	var want: Dictionary[int, int] = {100: 0, 67: 0, 66: 1, 34: 1, 33: 2, 1: 2, 0: 2}
	for hp: int in want:
		(
			assert_int(BuildingDamage.stage_of(hp, 100, BUILDING_LINES))
			. override_failure_message("hp %d of 100" % hp)
			. is_equal(want[hp])
		)
	assert_int(BuildingDamage.stage_of(1, 1, BUILDING_LINES)).is_equal(0)  # Max hp 1, hp 1.
	assert_int(BuildingDamage.stage_of(670, 1000, BUILDING_LINES)).is_equal(0)  # Exactly 67 %.
	assert_int(BuildingDamage.stage_of(669, 1000, BUILDING_LINES)).is_equal(1)
	assert_int(BuildingDamage.stage_of(339, 1000, BUILDING_LINES)).is_equal(2)


func test_the_vehicle_lines_split_at_50_and_25() -> void:
	var want: Dictionary[int, int] = {100: 0, 50: 0, 49: 1, 25: 1, 24: 2, 1: 2}
	for hp: int in want:
		(
			assert_int(BuildingDamage.stage_of(hp, 100, VEHICLE_LINES))
			. override_failure_message("hp %d of 100" % hp)
			. is_equal(want[hp])
		)
	assert_int(BuildingDamage.stage_of(1, 1, VEHICLE_LINES)).is_equal(0)


func test_the_data_file_holds_both_lists_and_the_write_split() -> void:
	var from_file: LifeSettings = load("res://data/life_settings.tres") as LifeSettings
	for settings: LifeSettings in [from_file, LifeSettings.new()]:
		assert_array(Array(settings.building_stage_percent)).is_equal([67, 34])
		assert_array(Array(settings.vehicle_stage_percent)).is_equal([50, 25])
		for lines: PackedInt32Array in [
			settings.building_stage_percent, settings.vehicle_stage_percent
		]:
			assert_int(lines.size()).is_equal(2)
			assert_int(lines[0]).is_less(100)
			assert_int(lines[0]).is_greater(lines[1])
			assert_int(lines[1]).is_greater(0)
		assert_int(settings.damage_writes_per_frame).is_equal(60)
		assert_int(settings.damage_building_writes).is_equal(20)
		assert_int(settings.damage_building_writes).is_greater(0)
		assert_int(settings.damage_building_writes).is_less(settings.damage_writes_per_frame)
		# The dearest change fits one frame, so the queue can never stall at its head.
		assert_int(settings.damage_building_writes).is_greater_equal(
			BuildingDamage.cost(0, 2, true)
		)


# --- The pictures ---


func test_a_building_crossing_a_line_shows_the_trimmed_body_and_its_patch() -> void:
	_open(_pair())
	var node: Node2D = _layer.building(1)
	var at: Vector2 = node.position
	var rise: Rect2 = _layer.frame_box(_runner.snapshot.index_of(1))
	var lift: float = _layer.bar_lift_px(_runner.snapshot.index_of(1))
	assert_object(_patch(1)).is_not_null()
	assert_bool(_patch(1).visible).is_false()  # Intact: no patch.
	assert_bool(_body(1).region_filter_clip_enabled).is_false()
	var full: Rect2i = _region(&"hull")
	assert_that(_body(1).region_rect).is_equal(Rect2(full))
	_hit(1, 67)
	assert_bool(_patch(1).visible).is_false()  # Exactly 67 % is intact.
	_hit(1, 66)
	_check_intact(1)  # SKADET draws the intact picture (ADR 0034).
	_hit(1, 34)
	_check_intact(1)  # 34 % exactly is still SKADET.
	_hit(1, 33)
	_check_stage(1, 2)
	assert_that(node.position).is_equal(at)
	assert_that(_layer.frame_box(_runner.snapshot.index_of(1))).is_equal(rise)
	assert_float(_layer.bar_lift_px(_runner.snapshot.index_of(1))).is_equal(lift)
	assert_object(_layer.building(1)).is_same(node)


func test_the_children_stand_body_damage_anim_head() -> void:
	_open(_pair(), {"anim": true, "head": true})
	_hit(1, 20)
	var names: Array[String] = []
	for child: Node in _layer.building(1).get_children():
		names.append(String(child.name))
	assert_array(names).is_equal(["Body", "Damage", "Anim", "Head"])


func test_the_body_is_trimmed_again_after_every_frame_written_to_it() -> void:
	_open(_pair())
	_hit(1, 20)
	var trimmed: Rect2 = _body(1).region_rect
	var offset: float = _body(1).offset.y
	# A bare show_frame rewrites the whole region (the seam rule says why it must be followed).
	_sort.show_frame(_body(1), _def, BuildingLayer.BODY, BuildingLayer.NO_FRAME, 1)
	assert_that(_body(1).region_rect).is_equal(Rect2(_region(&"hull")))
	BuildingDamage.show_body(_sort, _def, _body(1), _body_base(), _bases(), 2)
	assert_that(_body(1).region_rect).is_equal(trimmed)
	assert_float(_body(1).offset.y).is_equal(offset)
	# And a show_base of the same frame.
	var base: int = _sort.base_of(_def, BuildingLayer.BODY, BuildingLayer.NO_FRAME, 1)
	_sort.show_base(_body(1), base, 0)
	BuildingDamage.trim(_sort, _def, _body(1), _bases(), 2)
	assert_that(_body(1).region_rect).is_equal(trimmed)
	# Back to intact un-trims it.
	BuildingDamage.show_body(_sort, _def, _body(1), _body_base(), _bases(), 0)
	assert_that(_body(1).region_rect).is_equal(Rect2(_region(&"hull")))
	assert_bool(_body(1).region_filter_clip_enabled).is_false()


func test_the_patch_overlaps_the_trimmed_body_strictly_at_every_bake_scale() -> void:
	for scale: float in SCALES:
		_open(_pair(), {}, scale)
		assert_float(_sort.atlas.bake_scale()).is_equal(scale)
		for stage: int in [2]:  # SKADET has no patch.
			_hit(1, 10)
			var body: Sprite2D = _body(1)
			var patch: Sprite2D = _patch(1)
			var bottom: float = (patch.offset.y + patch.region_rect.size.y) * patch.scale.y
			var top: float = body.offset.y * body.scale.y
			(
				assert_float(bottom)
				. override_failure_message(
					"scale %s stage %d: %s vs %s" % [scale, stage, bottom, top]
				)
				. is_greater(top)
			)
		_layer.queue_free()
		_sort.queue_free()


func test_an_odd_canvas_at_the_lowest_scale_has_no_overlap_the_reason_for_the_generators_refusal(
) -> void:
	var extras: Dictionary = {
		"cuts": PackedInt32Array([97, 97]),
		"sizes": {&"hull": Vector2i(100, 101), &"dmg2": Vector2i(100, 101)},
	}
	_open(_pair(), extras, IsoAtlas.MIN_SCALE)
	_hit(1, 10)
	var body: Sprite2D = _body(1)
	var patch: Sprite2D = _patch(1)
	var bottom: float = (patch.offset.y + patch.region_rect.size.y) * patch.scale.y
	assert_float(bottom - body.offset.y * body.scale.y).is_equal_approx(0.0, 0.001)


func test_a_body_is_not_trimmed_where_its_patch_has_no_region() -> void:
	_open(_pair())
	var none: PackedInt32Array = PackedInt32Array([-1, -1])
	for stage: int in [1, 2]:
		BuildingDamage.show_body(_sort, _def, _body(1), _body_base(), none, stage)
		assert_that(_body(1).region_rect).is_equal(Rect2(_region(&"hull")))
		assert_bool(_body(1).region_filter_clip_enabled).is_false()
		var per_px: Vector2 = _sort.texels(_def, &"hull")
		assert_float(_body(1).offset.y).is_equal_approx(
			-float(_def.origin(&"hull").y) * per_px.y, 0.001
		)
	BuildingDamage.show_body(_sort, _def, _body(1), _body_base(), _bases(), 2)
	assert_bool(_body(1).region_filter_clip_enabled).is_true()  # With its patch it is cut.


# --- SKADET draws the intact picture (ADR 0034) ---


func test_picture_is_intact_at_skadet_for_every_building_sheet_and_the_crafted_one() -> void:
	var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
	var sheets: Array[IsoSheetDef] = [Dmg.sheet()]
	for sheet: IsoSheetDef in index.sheets:
		if sheet.category == &"bld":
			sheets.append(sheet)
	assert_int(sheets.size()).is_greater(1)
	for sheet: IsoSheetDef in sheets:
		var note: String = String(sheet.art_id)
		assert_int(BuildingDamage.picture(sheet, 0)).override_failure_message(note).is_equal(0)
		assert_int(BuildingDamage.picture(sheet, 1)).override_failure_message(note).is_equal(0)
		var kritisk: int = 2 if sheet.has_part(&"dmg2") and sheet.cuts.size() >= 2 else 0
		assert_int(BuildingDamage.picture(sheet, 2)).override_failure_message(note).is_equal(
			kritisk
		)


func test_bases_of_reads_only_the_kritisk_patch() -> void:
	_open(_pair())
	var bases: PackedInt32Array = BuildingDamage.bases_of(_sort, _def, 1)
	assert_int(bases.size()).is_equal(2)
	assert_int(bases[0]).is_equal(-1)  # SKADET: no patch, `dmg1` is not read even where it exists.
	assert_int(bases[1]).is_greater_equal(0)
