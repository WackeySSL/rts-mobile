extends GdUnitTestSuite
## Generator v5a, the materials and moves (plan row P163, ADR 0029 section 5) on crafted buildings
## in a test's own output: the materials `interior`, `slab`, `hole`, `rebar` and `beam`, the move
## `blow` (hash order, rounding, glass only) and `char` of a team face. Points, emitters,
## `anim_kritisk`, the canvas and the key share are in test_artgen_v5_points.gd.

const Support = preload("res://tests/art/artgen_v5_support.gd")
const GOLDEN_THREE: Array[int] = [1, 3, 2]
const GOLDEN_OTHER: Array[int] = [1, 2, 3]


func _problems(model: ArtModel) -> String:
	return "\n".join(model.problems())


func _fills(polys: Array[ArtRender.Poly]) -> Array[String]:
	var found: Array[String] = []
	for poly: ArtRender.Poly in polys:
		found.append(poly.fill)
	return found


func test_the_new_materials_draw_their_pinned_colours() -> void:
	var pinned: Dictionary[StringName, Array] = {
		&"slab": ["#AEA89B", "#8F8A7F", "#6C6860"],
		&"hole": ["#272E34", "#20262B", "#181D21"],
		&"rebar": ["#5A4E44", "#4A4038", "#38302A"],
		&"beam": ["#707A6F", "#5C645B", "#464C45"],
	}
	for faction: StringName in ArtPalette.KEYS:
		assert_str(ArtPalette.tone(faction, &"interior", ArtPalette.TOP)).is_equal("#1A1715")
		assert_str(ArtPalette.tone(faction, &"interior", ArtPalette.LEFT)).is_equal("#1A1715")
		assert_str(ArtPalette.tone(faction, &"interior", ArtPalette.RIGHT)).is_equal("#100E0D")
		assert_str(ArtPalette.edge(faction, &"interior", true)).is_equal("#100E0D")
		for material: StringName in pinned:
			assert_bool(ArtPalette.has_material(faction, material)).is_true()
			for level: int in 3:
				var got: String = ArtPalette.tone(faction, material, level)
				(
					assert_str(got)
					. override_failure_message("%s %s %d" % [faction, material, level])
					. is_equal(pinned[material][level])
				)
		# None of them is in a key band.
		for material: StringName in [&"interior", &"slab", &"hole", &"rebar", &"beam"]:
			for level: int in 3:
				var hex: String = ArtPalette.tone(faction, material, level)
				assert_bool(ArtPalette.in_key_band(faction, hex)).is_false()
	# A primitive of the new material renders with them.
	var model: ArtModel = Support.building(["box hull interior 0 0 1.2 0.3 0.3 0.1 damage=1"])
	assert_array(_fills(ArtGen.stage_polys(model, 1))).contains(["#1A1715", "#100E0D"])


func _holes(model: ArtModel, stage: int) -> Array[int]:
	var found: Array[int] = []
	for prim: ArtPrim in model.damage_prims(stage):
		if prim.material == &"hole":
			found.append(prim.index)
	found.sort()
	return found


## A renew building of `count` panes in a frame, lines 1 to `count` the panes; two damage points.
func _glasshouse(id: StringName, count: int, poses: Array[String]) -> ArtModel:
	var prims: Array[String] = ["box hull titanium 0 0 0 1.6 1.6 0.4"]
	for i: int in count:
		prims.append("box hull glass %s -0.8 0.4 0.2 0.1 0.5 group=panes" % (-0.5 + 0.3 * i))
	prims.append("box hull titanium 0 -0.85 0.9 1.4 0.1 0.1 group=panes")
	var model: ArtModel = ArtModel.new()
	model.art_id = id
	model.faction = &"renew"
	model.category = &"bld"
	model.footprint = 2
	model.prims = PackedStringArray(prims)
	model.poses = PackedStringArray(poses)
	model.emitters = PackedStringArray(["damage -0.6 -0.4 0.4", "dmg_spark -0.3 -0.5 0.4"])
	return model


func test_blow_turns_the_first_panes_in_the_hash_order_and_keeps_the_frames() -> void:
	var model: ArtModel = _glasshouse(
		&"glasshouse", 4, ["dmg1 0 panes blow 50", "dmg2 0 panes blow 100"]
	)
	assert_array(Array(model.problems())).is_empty()
	var order: Array[int] = ArtDamage.blow_order(model, &"panes")
	assert_array(order).has_size(4)  # the four panes; the frames are titanium
	assert_array(order).is_equal(ArtDamage.blow_order(model, &"panes"))  # the same on a second run
	var first_two: Array[int] = [order[0], order[1]]
	first_two.sort()
	assert_array(_holes(model, 1)).is_equal(first_two)  # exactly the two first
	assert_int(_holes(model, 2).size()).is_equal(4)
	# The frames stay what they were, in both stages.
	for stage: int in [1, 2]:
		var frames: int = 0
		for prim: ArtPrim in model.damage_prims(stage):
			if prim.material == &"titanium":
				frames += 1
		assert_int(frames).is_equal(2)
	# The intact picture has its panes.
	for prim: ArtPrim in model.primitives(&"hull"):
		assert_str(prim.material).is_not_equal("hole")
	# The hole is drawn in the hole colour.
	var hole: String = ArtPalette.tone(&"renew", &"hole", ArtPalette.LEFT)
	assert_array(_fills(ArtGen.stage_polys(model, 1))).contains([hole])
	assert_object(ArtMove.parse("dmg1 0 panes blow 101")).is_null()
	assert_object(ArtMove.parse("walk 0 panes blow 10")).is_null()


func test_blow_order_is_pinned_and_another_id_orders_the_panes_otherwise() -> void:
	var poses: Array[String] = ["dmg1 0 panes blow 50", "dmg2 0 panes blow 100"]
	var first: ArtModel = _glasshouse(&"glasshouse", 3, poses)
	assert_array(ArtDamage.blow_order(first, &"panes")).is_equal(GOLDEN_THREE)
	var second: ArtModel = _glasshouse(&"another_house", 3, poses)
	assert_array(ArtDamage.blow_order(second, &"panes")).is_not_equal(GOLDEN_THREE)
	assert_array(ArtDamage.blow_order(second, &"panes")).is_equal(GOLDEN_OTHER)
	assert_int(ArtDamage._djb2("glasshouse")).is_equal("glasshouse".hash())  # as String.hash()


func test_blow_rounds_to_the_nearest_pane() -> void:
	var three: ArtModel = _glasshouse(
		&"glasshouse", 3, ["dmg1 0 panes blow 50", "dmg2 0 panes blow 100"]
	)
	assert_int(_holes(three, 1).size()).is_equal(2)  # 1.5 rounds up
	var four: ArtModel = _glasshouse(
		&"glasshouse", 4, ["dmg1 0 panes blow 10", "dmg2 0 panes blow 100"]
	)
	assert_int(_holes(four, 1).size()).is_equal(0)  # 0.4 rounds down


func test_blow_needs_intact_glass_in_its_group() -> void:
	var model: ArtModel = _glasshouse(
		&"glasshouse", 3, ["dmg1 0 panes blow 50", "dmg2 0 panes blow 100"]
	)
	assert_str(_problems(model)).is_equal("")
	model.poses = PackedStringArray(["dmg1 0 panes blow 50", "dmg2 0 frame blow 100"])
	assert_str(_problems(model)).contains("no such hull group")
	var no_glass: ArtModel = Support.building([], Support.POSES + ["dmg1 0 stack blow 50"])
	assert_str(_problems(no_glass)).contains("blow needs intact glass")


func test_char_of_a_team_face_must_leave_the_key_band() -> void:
	assert_bool(ArtPalette.char_leaves_band(&"fossil", 100.0)).is_true()
	assert_bool(ArtPalette.char_leaves_band(&"renew", 100.0)).is_true()
	for percent: float in [0.0, 30.0, 60.0, 80.0]:
		for faction: StringName in ArtPalette.KEYS:
			assert_bool(ArtPalette.char_leaves_band(faction, percent)).is_false()
	# Outside the band: passes, and the face takes the char colour.
	var model: ArtModel = Support.building()
	assert_array(Array(model.problems())).is_empty()
	assert_array(_fills(ArtGen.stage_polys(model, 1))).contains([ArtPalette.CHAR])
	# Inside it: refused.
	var half: Array[String] = Support.POSES.duplicate()
	half[half.find("dmg1 0 t1 char 100")] = "dmg1 0 t1 char 40"
	assert_str(_problems(Support.building([], half))).contains("stays in the key band")
	# A char of a group that has no team face is not held to it.
	var rust: Array[String] = Support.POSES.duplicate()
	rust.append("dmg1 0 body char 40")
	assert_str(_problems(Support.building([], rust))).is_equal("")
