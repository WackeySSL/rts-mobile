extends GdUnitTestSuite
## Generator v5a, the ruin and the materials (plan row P163, ADR 0029 sections 3 to 5) on crafted
## buildings in a test's own output: the `ruin` pose, its refusals, the materials `interior`,
## `slab`, `hole`, `rebar` and `beam`, the moves `blow` and `soot`, and `char` of a team face.
## Points, emitters, `anim_kritisk`, the canvas and the key share are in test_artgen_v5_points.gd.

const Support = preload("res://tests/art/artgen_v5_support.gd")
## A body, a cap that the stages lower and drop, and a ruin slab; two damage points on the body's
## top and a ruin point on the slab.
const BODY: String = "box hull concrete 0 0 0 1.6 1.6 2.0 group=body"
const BASE: Array[String] = [
	"box hull steel 0.2 0.2 2.0 0.3 0.3 0.3 group=cap",
	"box hull concrete 0 0 0 1.2 1.2 0.1 group=base damage=3",
]
const STAGES: Array[String] = [
	"dmg1 0 cap shift 0 0 -0.05", "dmg2 0 cap hide", "ruin 0 body hide", "ruin 0 cap hide"
]
const POINTS: Array[String] = ["damage -0.3 -0.3 2.0", "dmg_gas -0.5 0.1 2.0", "ruin 0 0 0.1"]
## A renew building of four panes in a frame: the panes are `glass` of one group.
const PANES: Array[String] = [
	"box hull titanium 0 0 0 1.6 1.6 0.4",
	"box hull glass -0.45 -0.8 0.4 0.3 0.1 0.5 group=panes",
	"box hull glass -0.15 -0.8 0.4 0.3 0.1 0.5 group=panes",
	"box hull glass 0.15 -0.8 0.4 0.3 0.1 0.5 group=panes",
	"box hull glass 0.45 -0.8 0.4 0.3 0.1 0.5 group=panes",
	"box hull titanium 0 -0.85 0.9 1.4 0.1 0.1 group=panes",
]


func _with_ruin(prims: Array[String], poses: Array[String] = []) -> ArtModel:
	var lines: Array[String] = [BODY]
	lines.append_array(BASE)
	lines.append_array(prims)
	var moves: Array[String] = []
	moves.assign(STAGES + poses)
	return Support.with_prims(lines, moves, POINTS)


func _problems(model: ArtModel) -> String:
	return "\n".join(model.problems())


func _fills(polys: Array[ArtRender.Poly]) -> Array[String]:
	var found: Array[String] = []
	for poly: ArtRender.Poly in polys:
		found.append(poly.fill)
	return found


func test_a_ruin_pose_makes_a_whole_picture_cropped_to_its_ink() -> void:
	var model: ArtModel = Support.building()
	assert_array(Array(model.problems())).is_empty()
	assert_array(model.damage_parts()).is_equal([&"dmg1", &"dmg2", &"ruin"])
	assert_array(model.frame_parts()).is_equal(
		[&"hull", &"anim", &"dmg1", &"dmg2", &"ruin", &"shadow"]
	)
	var files: Dictionary[String, String] = ArtGen.build(model)
	var path: String = ArtGen.frame_path(model, &"ruin", -1)
	assert_str(path).ends_with("crafted_ruin.svg")
	assert_bool(files.has(path)).is_true()
	assert_bool(files.has(path + ".import")).is_true()
	var shots: Dictionary[StringName, ArtGen.Shot] = ArtGen.all_shots(model)
	var shot: ArtGen.Shot = shots[&"ruin"]
	assert_array(shot.dirs).is_equal([-1])
	assert_int(shot.frames).is_equal(1)
	# Cropped to its ink: the canvas is the ink and the margin, even in both directions.
	var box: Rect2 = ArtRender.bounds(ArtGen.stage_polys(model, 3))
	assert_int(shot.layout.size.x).is_between(int(box.size.x), int(box.size.x) + 5)
	assert_int(shot.layout.size.y).is_between(int(box.size.y), int(box.size.y) + 5)
	assert_int(shot.layout.size.x % 2).is_equal(0)
	assert_int(shot.layout.size.y % 2).is_equal(0)
	assert_float(box.position.x + shot.layout.origin.x).is_greater_equal(0.0)
	assert_float(box.end.y + shot.layout.origin.y).is_less_equal(shot.layout.size.y)
	assert_int(shot.layout.size.y).is_less(shots[&"hull"].layout.size.y / 2)
	assert_int(shot.layout.origin.y - shot.layout.anchor.y).is_equal(64)  # 32 px a footprint tile


func test_damage_3_primitives_are_drawn_in_the_ruin_only_and_no_anim_is() -> void:
	var model: ArtModel = Support.building()
	for prim: ArtPrim in model.primitives(&"hull"):
		assert_int(prim.damage).is_equal(0)
	for stage: int in [1, 2]:
		for prim: ArtPrim in model.damage_prims(stage):
			assert_int(prim.damage).is_not_equal(3)
	var tagged: Array[ArtPrim] = []
	for prim: ArtPrim in model.damage_prims(3):
		assert_str(prim.part).is_equal("hull")  # the anim element is not in the ruin
		if prim.damage == 3:
			tagged.append(prim)
	assert_int(tagged.size()).is_equal(3)
	assert_int(model.pose_frames(&"ruin")).is_equal(0)
	for path: String in ArtGen.build(model):
		assert_bool(path.contains("ruin") and path.contains("anim")).is_false()
	assert_object(ArtPrim.parse("box hull steel 0 0 0 1 1 1 damage=4")).is_null()
	assert_int(ArtPrim.parse("box hull steel 0 0 0 1 1 1 damage=3").damage).is_equal(3)


func test_the_sheet_lists_the_ruin_without_a_cut_and_anchors_it_like_the_body() -> void:
	var model: ArtModel = Support.building()
	var shots: Dictionary[StringName, ArtGen.Shot] = ArtGen.all_shots(model)
	var sheet: IsoSheetDef = ArtSheet.of(model, shots)
	assert_array(Array(sheet.parts)).contains(["dmg1", "dmg2", "ruin"])
	assert_int(sheet.cuts.size()).is_equal(2)  # cuts keeps its two entries
	assert_bool(sheet.has_part(&"ruin")).is_true()
	assert_vector(Vector2(sheet.frame_size(&"ruin"))).is_equal(Vector2(shots[&"ruin"].layout.size))
	# A building's ruin carries the footprint-centre offset like dmg1 and dmg2 (32 px a tile).
	for part: StringName in [&"hull", &"dmg1", &"dmg2", &"ruin"]:
		var offset: int = sheet.origin(part).y - sheet.anchor(part).y
		assert_int(offset).override_failure_message(part).is_equal(32 * model.footprint)
	assert_str(sheet.path(&"ruin", -1)).ends_with("crafted_ruin.svg")


func test_a_ruin_may_move_mount_and_dmg1_and_dmg2_may_not() -> void:
	assert_array(Array(Support.building().problems())).is_empty()  # the ruin shifts mount
	for part: String in ["dmg1", "dmg2"]:
		var moves: Array[String] = Support.POSES.duplicate()
		moves.append("%s 0 mount shift 0 0 -0.1" % part)
		assert_str(_problems(Support.building([], moves))).contains("moving element or mount")
	# A hull group that the anim element shares is refused in the ruin too.
	var anim_moves: Array[String] = Support.POSES.duplicate()
	anim_moves.append("ruin 0 beacon hide")
	var named: Array[String] = ["box hull iron 0.2 0.2 1.0 0.1 0.1 0.1 group=beacon"]
	assert_str(_problems(Support.building(named, anim_moves))).contains("moving element or mount")


func test_a_ruin_primitive_off_the_footprint_or_high_there_is_refused() -> void:
	# Footprint 2: it reaches 1.0 from the centre; a quarter tile outside is 1.25.
	var ok: ArtModel = _with_ruin(["box hull concrete 1.1 0 0 0.3 0.3 0.1 damage=3"])
	assert_str(_problems(ok)).is_equal("")
	var far: ArtModel = _with_ruin(["box hull concrete 1.3 0 0 0.3 0.3 0.05 damage=3"])
	assert_str(_problems(far)).contains("quarter tile")
	var high: ArtModel = _with_ruin(["box hull concrete 1.1 0 0 0.3 0.3 0.2 damage=3"])
	assert_str(_problems(high)).contains("0.1 high")
	# Inside the footprint a ruin primitive may be higher.
	var inside: ArtModel = _with_ruin(["box hull concrete 0 0 0 0.6 0.6 0.4 damage=3"])
	assert_str(_problems(inside)).is_equal("")


func test_a_ruin_that_rises_above_half_the_canvas_is_refused() -> void:
	var low: ArtModel = _with_ruin(["box hull concrete 0 0 0 1.2 1.2 0.3 damage=3"])
	assert_str(_problems(low)).is_equal("")
	var tall: ArtModel = _with_ruin(["box hull concrete 0 0 0 1.2 1.2 0.9 damage=3"])
	assert_str(_problems(tall)).contains("half at most")
	# A ruin that draws nothing is refused too.
	var empty: ArtModel = _with_ruin([], ["ruin 0 base hide"])
	assert_str(_problems(empty)).contains("draws nothing")


func test_a_ruin_needs_dmg2() -> void:
	var prims: Array[String] = [BODY, "box hull concrete 0 0 0 1.2 1.2 0.2 damage=3"]
	var model: ArtModel = Support.with_prims(prims, ["ruin 0 body hide"], POINTS)
	assert_str(_problems(model)).contains("needs dmg2")
	var with_dmg1: ArtModel = Support.with_prims(
		prims, ["dmg1 0 body shift 0 0 -0.05", "ruin 0 body hide"], POINTS
	)
	assert_str(_problems(with_dmg1)).contains("dmg1 without dmg2")
	assert_str(_problems(with_dmg1)).contains("needs dmg2")


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
	var model: ArtModel = _with_ruin(["box hull interior 0 0 0 0.6 0.6 0.2 damage=3"])
	assert_array(_fills(ArtGen.stage_polys(model, 3))).contains(["#1A1715", "#100E0D"])


func _holes(model: ArtModel, stage: int) -> Array[int]:
	var found: Array[int] = []
	for prim: ArtPrim in model.damage_prims(stage):
		if prim.material == &"hole":
			found.append(prim.index)
	found.sort()
	return found


func test_blow_turns_the_first_panes_in_the_hash_order_and_keeps_the_frames() -> void:
	var model: ArtModel = ArtModel.new()
	model.art_id = &"glasshouse"
	model.faction = &"renew"
	model.category = &"bld"
	model.footprint = 2
	model.prims = PackedStringArray(PANES)
	model.poses = PackedStringArray(["dmg1 0 panes blow 50", "dmg2 0 panes blow 100"])
	assert_array(Array(model.problems())).is_empty()
	var order: Array[int] = ArtDamage.blow_order(model, &"panes")
	assert_array(order).has_size(4)  # the four panes; the frame is titanium
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


func test_soot_chars_every_hull_face_of_the_stage_but_the_team_faces() -> void:
	var prims: Array[String] = [
		"box hull iron 0.5 0.5 0 0.2 0.2 0.2 group=a",
		"box hull rust -0.5 -0.5 0 0.2 0.2 0.2",
		"box hull team 0.1 0.85 0 0.3 0.1 0.3 group=t",
	]
	var model: ArtModel = _with_ruin(prims, ["ruin 0 soot 50"])
	assert_array(Array(model.problems())).is_empty()
	assert_float(ArtMove.parse("ruin 0 soot 50").char_percent).is_equal(50.0)
	assert_object(ArtMove.parse("ruin 0 soot")).is_null()
	assert_object(ArtMove.parse("ruin 0 soot 101")).is_null()
	assert_object(ArtMove.parse("walk 0 soot 10")).is_null()
	var fills: Array[String] = _fills(ArtGen.stage_polys(model, 3))
	# The rust-coloured ungrouped primitive is charred as well as the grouped one.
	for material: StringName in [&"iron", &"rust"]:
		for level: int in 3:
			var plain: String = ArtPalette.tone(&"fossil", material, level)
			assert_array(fills).not_contains([plain])
	var iron: String = ArtPalette.scorched(ArtPalette.tone(&"fossil", &"iron", 1), 50.0)
	assert_array(fills).contains([iron])
	# The team faces keep their key colours.
	assert_array(fills).contains([ArtPalette.KEYS[&"fossil"][0]])
	# In dmg1 or dmg2 a soot changes every primitive, so the cut falls to the lowest of them.
	var sooty: Array[String] = Support.POSES.duplicate()
	sooty.append("dmg1 0 soot 30")
	var plain: ArtModel = Support.building()
	var burnt: ArtModel = Support.building([], sooty)
	var body: ArtGen.Layout = ArtGen.all_shots(plain)[&"hull"].layout
	assert_int(ArtGen.damage_cut(burnt, 1, body)).is_greater(ArtGen.damage_cut(plain, 1, body))


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
