extends GdUnitTestSuite
## The view's names of the damage patches and the generator's are one list (plan P158a, ADR 0029):
## `tools/artgen` may not reference `game/view`, so each keeps its literal and this test pins them.
## There is no third picture (the ruin is dropped), so both lists stay `[dmg1, dmg2]` (`dmg1` names
## stage 1, which has no picture, ADR 0034) and both patches are baked at `IsoAtlas.DAMAGE_SCALE`.


func test_the_views_damage_parts_are_the_generators() -> void:
	assert_array(IsoAtlas.DAMAGE_PARTS).is_equal(ArtModel.DAMAGE_PARTS)
	assert_array(BuildingDamage.PARTS).is_equal(ArtModel.DAMAGE_PARTS)
	assert_int(IsoAtlas.DAMAGE_PARTS.size()).is_equal(2)


func test_every_damage_part_is_baked_at_the_damage_scale_and_nothing_else_is() -> void:
	for part: StringName in IsoAtlas.DAMAGE_PARTS:
		assert_float(IsoAtlas.part_factor(part)).is_equal(IsoAtlas.DAMAGE_SCALE)
	for part: StringName in [&"hull", &"shadow", &"anim", &"turret", &"head", &"ruin"]:
		assert_float(IsoAtlas.part_factor(part)).is_equal(1.0)


func test_the_sheets_origin_treats_the_same_parts_as_the_body() -> void:
	# `IsoSheetDef.origin` anchors a damage patch like the body, from its own literal.
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.footprint = 2
	sheet.parts = PackedStringArray(["hull", "dmg1", "dmg2", "anim"])
	sheet.anchors = PackedInt32Array([10, 20, 30, 40, 50, 60, 70, 80])
	for part: StringName in IsoAtlas.DAMAGE_PARTS:
		assert_that(sheet.origin(part)).is_equal(sheet.anchor(part) + Vector2i(0, 64))
	assert_that(sheet.origin(&"anim")).is_equal(sheet.anchor(&"anim"))
