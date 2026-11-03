extends GdUnitTestSuite
## The damage moves of generator v4 (plan row P156, ADR 0028 sections 3 and 4) on a crafted
## building: `shift`, `turn`, `hide` and `char` in the poses `dmg1` and `dmg2`, primitives that
## appear from a stage on, the seated groups, the cut row read off the geometry (checked against
## the pixels), the patch with its overlap, `cuts`, the `damage` and `hang` emitter kinds, and
## `IsoSheetDef.root`. No committed model has any of it yet: that the committed bytes did not
## change is test_artgen.gd.

const SCALE: float = 1.0
## The crafted building: a body of 1.6 x 1.6 x 1, a roof slab, a stack, a flag in the team's colour,
## a seated mast, debris for each stage and a beacon that moves.
const PRIMS: Array[String] = [
	"box hull concrete 0 0 0 1.6 1.6 1.0",
	"box hull steel -0.4 -0.4 1.0 0.4 0.4 0.25 group=roof",
	"box hull rust -0.45 -0.45 1.0 0.2 0.2 0.35 group=stack",
	"box hull team 0.1 -0.5 1.0 0.25 0.25 0.2 group=flag",
	"box hull iron 0.4 -0.4 1.0 0.1 0.1 0.4 group=mount",
	"box hull iron -0.2 0.3 1.25 0.3 0.3 0.1 damage=1",
	"box hull iron 0.3 -0.1 1.25 0.2 0.2 0.1 damage=2",
	"box anim lamp 0 0 1.4 0.1 0.1 0.1 group=beacon",
]
const POSES: Array[String] = [
	"anim 2",
	"anim 1 beacon shift 0 0 0.05",
	"dmg1 0 roof shift 0 0 -0.1",
	"dmg1 0 stack char 60",
	"dmg2 0 stack hide",
	"dmg2 0 roof turn y 12 -0.4 -0.4 1.0",
	"dmg2 0 flag char 50",
]
const LID: Array[String] = [
	"box hull concrete 0 0 0 1.6 1.6 1.0", "box hull steel -0.4 -0.4 1.0 0.4 0.4 0.25 group=lid"
]


func _model(extra_poses: Array[String] = [], extra_prims: Array[String] = []) -> ArtModel:
	var model: ArtModel = ArtModel.new()
	model.art_id = &"crafted"
	model.faction = &"fossil"
	model.category = &"bld"
	model.footprint = 2
	model.anim_ms = 100
	model.prims = PackedStringArray(PRIMS + extra_prims)
	model.poses = PackedStringArray(POSES + extra_poses)
	return model


func test_the_crafted_model_is_valid_and_its_moves_parse() -> void:
	assert_array(Array(_model().problems())).is_empty()
	var hide: ArtMove = ArtMove.parse("dmg2 0 stack hide")
	assert_str(hide.kind).is_equal("hide")
	var scorch: ArtMove = ArtMove.parse("dmg1 0 stack char 60")
	assert_str(scorch.kind).is_equal("char")
	assert_float(scorch.char_percent).is_equal(60.0)
	assert_str(ArtMove.parse("dmg1 0 roof shift 0 0 -0.1").kind).is_equal("shift")
	assert_str(ArtMove.parse("dmg2 0 roof turn y 12 0 0 1").kind).is_equal("turn")
	for line: String in [
		"anim 1 beacon hide",  # hide and char are for the damage poses
		"walk 0 leg char 10",
		"dmg1 0 stack hide now",
		"dmg1 0 stack char",
		"dmg1 0 stack char 101",
		"dmg1 0 stack char -1",
		"dmg3 0 stack hide",
	]:
		assert_object(ArtMove.parse(line)).override_failure_message(line).is_null()


func test_a_primitive_tagged_damage_is_drawn_from_its_stage_on() -> void:
	var model: ArtModel = _model()
	assert_int(ArtPrim.parse(PRIMS[5]).damage).is_equal(1)
	assert_int(ArtPrim.parse(PRIMS[1]).damage).is_equal(0)
	for line: String in [
		"box hull steel 0 0 0 1 1 1 damage=0", "box hull steel 0 0 0 1 1 1 damage=3"
	]:
		assert_object(ArtPrim.parse(line)).is_null()
	assert_int(model.primitives(&"hull").size()).is_equal(5)  # intact: none of the tagged
	assert_int(model.damage_prims(1).size()).is_equal(6)  # plus the stage 1 debris
	assert_int(model.damage_prims(2).size()).is_equal(6)  # the stack hidden, both debris
	var materials: Array[String] = []
	for prim: ArtPrim in model.damage_prims(2):
		materials.append("%s %s" % [prim.material, prim.damage])
	assert_array(materials).contains(["iron 1", "iron 2"])
	assert_array(materials).not_contains(["rust 0"])
	assert_array(model.damage_parts()).is_equal([&"dmg1", &"dmg2"])
	assert_array(model.frame_parts()).is_equal([&"hull", &"anim", &"dmg1", &"dmg2", &"shadow"])
	assert_array(model.directions(&"dmg1")).is_equal([-1])
	assert_int(model.frames(&"dmg2")).is_equal(1)


func test_a_pose_moves_hides_and_scorches_its_group() -> void:
	var model: ArtModel = _model()
	var roof: ArtPrim = _find(model.damage_prims(1), &"roof")
	assert_float(roof.aabb().position.z).is_equal_approx(0.9, 1e-6)  # shifted down 0.1
	var stack: ArtPrim = _find(model.damage_prims(1), &"stack")
	assert_float(stack.char_percent).is_equal(60.0)
	assert_object(_find(model.damage_prims(2), &"stack")).is_null()  # hidden
	assert_float(_find(model.damage_prims(2), &"roof").aabb().size.z).is_greater(0.25)  # turned
	# The intact body never sees a damage move.
	assert_float(_find(model.primitives(&"hull"), &"roof").aabb().position.z).is_equal(1.0)
	assert_float(_find(model.primitives(&"hull"), &"stack").char_percent).is_equal(0.0)


func test_char_mixes_the_faces_towards_the_char_colour_and_spares_the_team_zone() -> void:
	var model: ArtModel = _model()
	var intact: Array[ArtRender.Poly] = ArtRender.render(model.primitives(&"hull"), 0.0, &"fossil")
	var burnt: Array[ArtRender.Poly] = ArtGen.stage_polys(model, 1)
	var rust_fill: String = ArtPalette.tone(&"fossil", &"rust", ArtPalette.TOP)
	var want: String = ArtPalette.scorched(rust_fill, 60.0)
	assert_str(want).is_not_equal(rust_fill)
	assert_array(_fills(intact)).contains([rust_fill])
	assert_array(_fills(burnt)).contains([want])
	assert_array(_fills(burnt)).not_contains([rust_fill])
	# 0 % is the colour itself, 100 % the char colour.
	assert_str(ArtPalette.scorched("#6E5D50", 0.0)).is_equal("#6E5D50")
	assert_str(ArtPalette.scorched("#6E5D50", 100.0)).is_equal(ArtPalette.CHAR)
	# The flag is charred at stage 2 and keeps its key triad.
	var stage2: Array[ArtRender.Poly] = ArtGen.stage_polys(model, 2)
	for key: String in ArtPalette.KEYS[&"fossil"]:
		assert_array(_fills(stage2)).contains([key])


func test_the_seated_groups_may_not_be_touched() -> void:
	var anim_named: Array[String] = ["box hull steel 0.2 0.2 1.0 0.1 0.1 0.1 group=beacon"]
	var cases: Array[Array] = [
		[[], "dmg1 0 mount shift 0 0 -0.1", "moving element or mount"],
		[[], "dmg2 0 beacon hide", "no such hull group"],
		[anim_named, "dmg2 0 beacon hide", "moving element or mount"],
		[[], "dmg1 0 nothing hide", "no such hull group"],
		[[], "dmg1 1 roof hide", "frame 0"],
	]
	for found: Array in cases:
		var extra: Array[String] = []
		extra.assign(found[0])
		var line: String = found[1]
		var model: ArtModel = _model([line], extra)
		var problems: PackedStringArray = model.problems()
		assert_int(problems.size()).override_failure_message(line).is_equal(1)
		assert_str(problems[0]).override_failure_message(line).contains(found[2])
	# Damage is a building's: a vehicle with a damage pose is refused by that rule, and the
	# primitive tag is the hull's of a building.
	var vehicle: ArtModel = ArtModel.new()
	vehicle.art_id = &"tank"
	vehicle.faction = &"fossil"
	vehicle.category = &"veh"
	vehicle.prims = PackedStringArray(["box hull steel 0 0 0 1 1 1 group=roof"])
	vehicle.poses = PackedStringArray(["dmg1 0 roof hide"])
	var refused: String = "\n".join(vehicle.problems())
	assert_str(refused).contains("a damage pose is a building's")
	var turret: PackedStringArray = _model([], ["box turret steel 0 0 0 1 1 1 damage=1"]).problems()
	assert_int(turret.size()).is_equal(1)
	assert_str(turret[0]).contains("damage= is for the hull primitives of a building")


func test_the_cut_row_is_the_lowest_row_of_what_the_stage_changes() -> void:
	var model: ArtModel = _model()
	var shots: Dictionary[StringName, ArtGen.Shot] = ArtGen.all_shots(model)
	var body: ArtGen.Layout = shots[&"hull"].layout
	for part: StringName in ArtModel.DAMAGE_PARTS:
		var stage: int = ArtModel.DAMAGE_PARTS.find(part) + 1
		var low: float = -INF
		for pair: Array in model.damage_changes(stage):
			for prim: ArtPrim in pair:
				if prim != null:
					var one: Array[ArtPrim] = [prim]
					var polys: Array[ArtRender.Poly] = ArtRender.render(one, 0.0, &"fossil")
					low = maxf(low, ArtRender.bounds(polys).end.y)
		assert_int(shots[part].cut).is_equal(ceili(low + 1.0) + body.origin.y)


func test_the_cut_is_in_the_top_third_of_the_body() -> void:
	var shots: Dictionary[StringName, ArtGen.Shot] = ArtGen.all_shots(_model())
	var body: ArtGen.Shot = shots[&"hull"]
	var polys: Array[ArtRender.Poly] = []
	polys.assign(body.polys[0])
	var ink: Rect2 = ArtRender.bounds(polys)
	var top: float = ink.position.y + body.layout.origin.y
	for part: StringName in ArtModel.DAMAGE_PARTS:
		assert_float(float(shots[part].cut)).is_less(top + ink.size.y / 3.0)


func test_below_the_cut_the_stage_picture_is_the_intact_one() -> void:
	var model: ArtModel = _model()
	var shots: Dictionary[StringName, ArtGen.Shot] = ArtGen.all_shots(model)
	var body: ArtGen.Layout = shots[&"hull"].layout
	var intact: Image = _image(shots[&"hull"].polys[0], body)
	for part: StringName in ArtModel.DAMAGE_PARTS:
		var stage: int = ArtModel.DAMAGE_PARTS.find(part) + 1
		var full: Array[ArtRender.Poly] = ArtGen.stage_polys(model, stage)
		var posed: Image = _image(full, body)
		var cut: int = shots[part].cut
		assert_int(_differing_rows(intact, posed, cut, body.size.y)).is_equal(0)
		assert_int(_differing_rows(intact, posed, 0, cut)).is_greater(0)  # it does change above


func test_the_patch_over_the_body_gives_the_stage_picture() -> void:
	var model: ArtModel = _model()
	var files: Dictionary[String, String] = ArtGen.build(model)
	var shots: Dictionary[StringName, ArtGen.Shot] = ArtGen.all_shots(model)
	var body: ArtGen.Layout = shots[&"hull"].layout
	for part: StringName in ArtModel.DAMAGE_PARTS:
		var stage: int = ArtModel.DAMAGE_PARTS.find(part) + 1
		var shot: ArtGen.Shot = shots[part]
		var layout: ArtGen.Layout = shot.layout
		# The patch ends the overlap below the cut, and its canvas is even.
		var bottom: int = body.origin.y + layout.size.y - layout.origin.y
		assert_int(bottom - shot.cut).is_equal(ArtGen.CUT_OVERLAP_PX)
		assert_int(layout.size.x % 2).is_equal(0)
		assert_int(layout.size.y % 2).is_equal(0)
		assert_vector(Vector2(layout.anchor)).is_equal(Vector2(layout.origin - Vector2i(0, 64)))
		# The view's composition: the body from the cut down, the patch over it at the shared model
		# origin. That is the stage picture in every row.
		var posed: Image = _image(ArtGen.stage_polys(model, stage), body)
		var comp: Image = _image(shots[&"hull"].polys[0], body)
		comp.fill_rect(Rect2i(0, 0, body.size.x, shot.cut), Color(0, 0, 0, 0))
		var patch: Image = Image.create(layout.size.x, layout.size.y, false, Image.FORMAT_RGBA8)
		patch.load_svg_from_string(files[ArtGen.frame_path(model, part, -1)], SCALE)
		var at: Vector2i = body.origin - layout.origin
		comp.blend_rect(patch, Rect2i(Vector2i.ZERO, layout.size), at)
		var overlap: int = shot.cut + ArtGen.CUT_OVERLAP_PX
		assert_int(_differing_rows(comp, posed, 0, shot.cut, 6)).is_equal(0)
		assert_int(_differing_rows(comp, posed, overlap, body.size.y)).is_equal(0)
		# In the overlap both pictures are the same and an edge is drawn twice: the antialiased
		# fringe of the edge pixels doubles (up to about 80 of 255), nothing else differs.
		assert_int(_differing_rows(comp, posed, shot.cut, overlap, 90)).is_equal(0)
		# Cropped to its ink left and right: the ink starts and ends within the margin, and the
		# patch is narrower than the body.
		assert_int(layout.size.x).is_less(body.size.x)
		var columns: Array[int] = []
		for x: int in layout.size.x:
			for y: int in layout.size.y:
				if patch.get_pixel(x, y).a > 0.0:
					columns.append(x)
					break
		assert_int(columns.min()).is_less_equal(ArtGen.MARGIN_PX + 1)
		assert_int(layout.size.x - 1 - columns.max()).is_less_equal(ArtGen.MARGIN_PX + 2)


func test_the_sheet_lists_the_patches_cuts_and_files() -> void:
	var model: ArtModel = _model()
	var files: Dictionary[String, String] = ArtGen.build(model)
	var shots: Dictionary[StringName, ArtGen.Shot] = ArtGen.all_shots(model)
	var sheet: IsoSheetDef = ArtSheet.of(model, shots)
	assert_array(Array(sheet.parts)).is_equal(["hull", "anim", "dmg1", "dmg2", "shadow"])
	assert_array(Array(sheet.counts)).is_equal([1, 1, 1, 1, 1])
	assert_array(Array(sheet.cuts)).is_equal([shots[&"dmg1"].cut, shots[&"dmg2"].cut])
	assert_vector(Vector2(sheet.frame_size(&"dmg1"))).is_equal(Vector2(shots[&"dmg1"].layout.size))
	assert_vector(Vector2(sheet.anchor(&"dmg2"))).is_equal(Vector2(shots[&"dmg2"].layout.anchor))
	assert_vector(Vector2(sheet.origin(&"dmg1"))).is_equal(Vector2(shots[&"dmg1"].layout.origin))
	for part: StringName in ArtModel.DAMAGE_PARTS:
		var path: String = "res://assets/art/iso/fossil/bld/crafted_%s.svg" % part
		assert_str(sheet.path(part, -1)).is_equal(path)
		assert_bool(files.has(path)).is_true()
		assert_str(files.get(path + ".import", "")).is_equal(ArtGen.IMPORT_TEXT)
		assert_str(files[path]).contains("do not edit")
	var text: String = ArtSheet.text(sheet)
	assert_str(text).contains("cuts = PackedInt32Array(")
	assert_str(text).not_contains("root =")
	assert_str(text).not_contains("scar_milli")
	assert_dict(ArtGen.build(_model())).is_equal(files)  # a second run gives the same bytes


func test_a_model_without_damage_has_no_patch_no_cuts_and_the_same_sheet_text() -> void:
	var plain: ArtModel = _model()
	plain.poses = PackedStringArray(["anim 2", "anim 1 beacon shift 0 0 0.05"])
	plain.prims = PackedStringArray(PRIMS.slice(0, 5) + [PRIMS[7]])
	assert_array(plain.damage_parts()).is_empty()
	var sheet: IsoSheetDef = ArtSheet.of(plain, ArtGen.all_shots(plain))
	assert_array(Array(sheet.parts)).is_equal(["hull", "anim", "shadow"])
	assert_array(Array(sheet.cuts)).is_empty()
	var text: String = ArtSheet.text(sheet)
	assert_str(text).not_contains("cuts")
	assert_str(text).not_contains("root")
	assert_str(text).not_contains("scar_milli")


func test_a_stage_with_nothing_to_show_has_cut_0() -> void:
	var model: ArtModel = _model()
	model.poses = PackedStringArray(["anim 2", "anim 1 beacon shift 0 0 0.05", "dmg2 0 stack hide"])
	model.prims = PackedStringArray(PRIMS.slice(0, 5) + [PRIMS[7]])
	assert_array(model.damage_parts()).is_equal([&"dmg2"])
	var sheet: IsoSheetDef = ArtSheet.of(model, ArtGen.all_shots(model))
	assert_int(sheet.cuts[0]).is_equal(0)
	assert_int(sheet.cuts[1]).is_greater(0)


func test_each_move_alone_sets_the_cut_at_its_own_outline() -> void:
	var cuts: Dictionary[String, int] = {}
	for move: String in [
		"dmg1 0 lid shift 0 0 0.2",
		"dmg1 0 lid turn z 20 -0.4 -0.4 1.0",
		"dmg1 0 lid hide",
		"dmg1 0 lid char 70",
	]:
		var model: ArtModel = _model()
		model.prims = PackedStringArray(LID)
		model.anim_ms = 0
		model.poses = PackedStringArray([move, "dmg2 0 lid hide"])
		assert_array(Array(model.problems())).override_failure_message(move).is_empty()
		var shots: Dictionary[StringName, ArtGen.Shot] = ArtGen.all_shots(model)
		cuts[move] = shots[&"dmg1"].cut
		# The lid sits on top: every change stays above two thirds of the body's canvas.
		assert_int(cuts[move]).override_failure_message(move).is_less(
			shots[&"hull"].layout.size.y * 2 / 3
		)
	# Hide and char change the lid where it stands; their cut is the lid's own bottom.
	assert_int(cuts["dmg1 0 lid hide"]).is_equal(cuts["dmg1 0 lid char 70"])
	# Lifting it leaves the old outline in the union, so the cut stays at the lid's own bottom;
	# turning widens the outline, so it can only go lower.
	assert_int(cuts["dmg1 0 lid shift 0 0 0.2"]).is_equal(cuts["dmg1 0 lid hide"])
	assert_int(cuts["dmg1 0 lid turn z 20 -0.4 -0.4 1.0"]).is_greater_equal(cuts["dmg1 0 lid hide"])


func test_the_damage_and_hang_kinds_are_emitters() -> void:
	var model: ArtModel = _model()
	model.emitters = PackedStringArray(["damage 0.2 0.1 1.2", "damage -0.2 0.1 1.2"])
	assert_array(Array(model.problems())).is_empty()
	var sheet: IsoSheetDef = ArtSheet.of(model, ArtGen.all_shots(model))
	assert_array(Array(sheet.emitters)).is_equal(["damage", "damage"])
	assert_int(sheet.emitter_points.size()).is_equal(2)  # a building: one point each
	var tank: ArtModel = _vehicle()
	tank.emitters = PackedStringArray(["damage 0.1 0 0.5", "hang 0.5 0.5 0.3"])
	assert_array(Array(tank.problems())).is_empty()
	assert_int(tank.emitter_list().size()).is_equal(2)
	sheet = ArtSheet.of(tank, ArtGen.all_shots(tank))
	assert_array(Array(sheet.emitters)).is_equal(["damage", "hang"])
	assert_int(sheet.emitter_points.size()).is_equal(32)  # a vehicle: a point per hull frame
	tank.emitters = PackedStringArray(["scorch 0 0 0"])
	assert_int(tank.problems().size()).is_equal(1)


func test_scar_milli_is_a_vehicles_sheet_number_written_when_set() -> void:
	var model: ArtModel = _vehicle()
	var plain: String = ArtSheet.text(ArtSheet.of(model, ArtGen.all_shots(model)))
	assert_str(plain).not_contains("scar_milli")
	model.scar_milli = 850
	assert_array(Array(model.problems())).is_empty()
	var sheet: IsoSheetDef = ArtSheet.of(model, ArtGen.all_shots(model))
	assert_int(sheet.scar_milli).is_equal(850)
	assert_str(ArtSheet.text(sheet)).contains("scar_milli = 850")
	model.scar_milli = -1
	assert_int(model.problems().size()).is_equal(1)
	# Like `marks`, it is a vehicle's.
	var building: ArtModel = _model()
	building.scar_milli = 850
	var refused: PackedStringArray = building.problems()
	assert_int(refused.size()).is_equal(1)
	assert_str(refused[0]).contains("scar_milli")


func test_root_empty_is_the_generated_tree_and_set_is_its_own_folder() -> void:
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.art_id = &"scar"
	sheet.faction = &"neutral"
	sheet.category = &"dmg"
	sheet.parts = PackedStringArray(["scar1", "loose"])
	sheet.counts = PackedInt32Array([1, 1])
	sheet.frames = PackedInt32Array([1, 4])
	assert_str(sheet.path(&"scar1", -1)).is_equal("res://assets/art/iso/neutral/dmg/scar_scar1.svg")
	assert_str(sheet.path(&"loose", -1, 2)).is_equal(
		"res://assets/art/iso/neutral/dmg/scar_loose_f2.svg"
	)
	sheet.root = "res://assets/art/svg/damage"
	assert_str(sheet.path(&"scar1", -1)).is_equal("res://assets/art/svg/damage/scar_scar1.svg")
	assert_str(sheet.path(&"loose", -1, 2)).is_equal(
		"res://assets/art/svg/damage/scar_loose_f2.svg"
	)
	sheet.counts = PackedInt32Array([16, 1])  # a direction suffix stays in a root too
	assert_str(sheet.path(&"scar1", 5)).is_equal("res://assets/art/svg/damage/scar_scar1_d05.svg")
	assert_str(ArtSheet.text(sheet)).contains('root = "res://assets/art/svg/damage"')
	sheet.root = ""
	assert_str(ArtSheet.text(sheet)).not_contains("root")
	# The generator never sets it: no committed sheet writes one.
	for path: String in ArtGen.model_paths():
		var found: ArtModel = load(path) as ArtModel
		var text: String = FileAccess.get_file_as_string(ArtGen.sheet_path(found))
		assert_str(text).override_failure_message(path).is_not_empty()
		assert_str(text).override_failure_message(path).not_contains("\nroot =")


func test_clip_below_cuts_a_polygon_at_the_row() -> void:
	var poly: ArtRender.Poly = ArtRender.Poly.new()
	poly.points = PackedVector2Array(
		[Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]
	)
	poly.fill = "#FFFFFF"
	var gone: ArtRender.Poly = ArtRender.Poly.new()
	gone.points = PackedVector2Array([Vector2(0, 8), Vector2(4, 8), Vector2(4, 12)])
	var both: Array[ArtRender.Poly] = [poly, gone]
	var kept: Array[ArtRender.Poly] = ArtRender.clip_below(both, 4.0)
	assert_int(kept.size()).is_equal(1)
	assert_float(ArtRender.bounds(kept).end.y).is_equal(4.0)
	assert_float(ArtRender.bounds(kept).size.x).is_equal(10.0)
	assert_str(kept[0].fill).is_equal("#FFFFFF")


func _vehicle() -> ArtModel:
	var model: ArtModel = ArtModel.new()
	model.art_id = &"tank"
	model.faction = &"fossil"
	model.category = &"veh"
	model.prims = PackedStringArray(["box hull steel 0 0 0 1.2 0.8 0.4"])
	return model


func _find(prims: Array[ArtPrim], group: StringName) -> ArtPrim:
	for prim: ArtPrim in prims:
		if prim.group == group:
			return prim
	return null


func _fills(polys: Array[ArtRender.Poly]) -> Array[String]:
	var found: Array[String] = []
	for poly: ArtRender.Poly in polys:
		found.append(poly.fill)
	return found


## The body's canvas with `polys` drawn in it.
func _image(polys: Array, layout: ArtGen.Layout) -> Image:
	var typed: Array[ArtRender.Poly] = []
	typed.assign(polys)
	var text: String = ArtSvg.frame("t", layout.size, layout.origin, typed)
	var image: Image = Image.create(layout.size.x, layout.size.y, false, Image.FORMAT_RGBA8)
	image.load_svg_from_string(text, SCALE)
	return image


## How many rows from `from` to `to` (exclusive) differ between two images of one size, a
## premultiplied channel or the alpha by more than `tolerance` (255 is a whole channel).
func _differing_rows(a: Image, b: Image, from: int, to: int, tolerance: int = 0) -> int:
	var rows: int = 0
	for y: int in range(maxi(from, 0), mini(to, a.get_height())):
		var differs: bool = false
		for x: int in a.get_width():
			var pa: Color = a.get_pixel(x, y)
			var pb: Color = b.get_pixel(x, y)
			for c: int in 3:
				differs = (differs or absf(pa[c] * pa.a - pb[c] * pb.a) * 255.0 > tolerance)
			differs = differs or absf(pa.a - pb.a) * 255.0 > tolerance
		rows += 1 if differs else 0
	return rows
